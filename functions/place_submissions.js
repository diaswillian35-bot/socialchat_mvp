"use strict";

/**
 * Callables do "Adicionar local" (app). Escrita somente via Admin SDK:
 * as Rules de `places` continuam fechadas para o cliente e só mostram
 * locais `published`. Dono lê o pendente via places/{id}/private/access.
 */
const { HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { isSuperAdminAuth } = require("./super_admin");
const {
  parsePlaceInput,
  canEditPlace,
  moderationPatch,
  placeSummary,
} = require("./place_submission_logic");

const MAX_PENDING_PER_USER = 5;

function requireAuth(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }
  return request.auth.uid;
}

function requireSuperAdmin(request) {
  requireAuth(request);
  if (!isSuperAdminAuth(request.auth)) {
    throw new HttpsError("permission-denied", "Admin only.");
  }
}

function placeIdOf(data) {
  const id = String((data && data.placeId) || "").trim();
  if (!id || id.length > 128 || id.includes("/")) {
    throw new HttpsError("invalid-argument", "Invalid placeId.");
  }
  return id;
}

async function submitPlaceHandler(request) {
  const uid = requireAuth(request);
  const parsed = parsePlaceInput(request.data, { creating: true });
  if (parsed.error) {
    throw new HttpsError("invalid-argument", parsed.error);
  }
  const db = admin.firestore();
  const pending = await db.collection("places")
    .where("ownerId", "==", uid)
    .where("moderationStatus", "==", "pending")
    .limit(MAX_PENDING_PER_USER)
    .get();
  if (pending.size >= MAX_PENDING_PER_USER && !isSuperAdminAuth(request.auth)) {
    throw new HttpsError("resource-exhausted", "too_many_pending");
  }
  const ref = db.collection("places").doc();
  const now = admin.firestore.FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(ref, {
    ...parsed.fields,
    contractVersion: "remdy.places.v1",
    schemaVersion: 1,
    slug: ref.id,
    moderationStatus: "pending",
    status: "pending",
    active: false,
    deleted: false,
    ownerId: uid,
    source: "app",
    photoUrls: [],
    coverUrl: "",
    createdAt: now,
    updatedAt: now,
  });
  batch.set(ref.collection("private").doc("access"), {
    ownerUid: uid,
    managerUids: [],
    createdAt: now,
  });
  await batch.commit();
  return { placeId: ref.id, status: "pending" };
}

async function loadEditable(request, placeId) {
  const uid = requireAuth(request);
  const db = admin.firestore();
  const ref = db.collection("places").doc(placeId);
  const [snap, access] = await Promise.all([
    ref.get(),
    ref.collection("private").doc("access").get(),
  ]);
  if (!snap.exists || snap.data().deleted === true) {
    throw new HttpsError("not-found", "Place not found.");
  }
  if (!canEditPlace({
    uid,
    isSuperAdmin: isSuperAdminAuth(request.auth),
    placeData: snap.data(),
    accessData: access.exists ? access.data() : null,
  })) {
    throw new HttpsError("permission-denied", "Not the owner.");
  }
  return { ref, snap };
}

async function updateMyPlaceHandler(request) {
  const placeId = placeIdOf(request.data);
  const { ref, snap } = await loadEditable(request, placeId);
  const parsed = parsePlaceInput(request.data, { creating: false, placeId });
  if (parsed.error) {
    throw new HttpsError("invalid-argument", parsed.error);
  }
  const patch = {
    ...parsed.fields,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  // Dono editando local já publicado: volta para análise (como avaliações).
  const current = snap.data() || {};
  const keys = Object.keys(parsed.fields);
  const onlyMedia = keys.every((k) => ["photoUrls", "coverUrl"].includes(k));
  if (!isSuperAdminAuth(request.auth) &&
      current.moderationStatus === "published" && !onlyMedia) {
    patch.moderationStatus = "pending";
    patch.status = "pending";
    patch.active = false;
  }
  if (current.moderationStatus === "rejected" &&
      !isSuperAdminAuth(request.auth)) {
    patch.moderationStatus = "pending";
    patch.status = "pending";
  }
  await ref.update(patch);
  return { placeId, status: patch.status || current.status || "pending" };
}

async function getMyPlaceHandler(request) {
  const placeId = placeIdOf(request.data);
  const { snap } = await loadEditable(request, placeId);
  return { place: placeSummary(placeId, snap.data()) };
}

async function listMyPlacesHandler(request) {
  const uid = requireAuth(request);
  const snap = await admin.firestore().collection("places")
    .where("ownerId", "==", uid)
    .limit(50)
    .get();
  return {
    places: snap.docs
      .filter((d) => d.data().deleted !== true)
      .map((d) => placeSummary(d.id, d.data())),
  };
}

async function listPendingPlacesHandler(request) {
  requireSuperAdmin(request);
  const snap = await admin.firestore().collection("places")
    .where("moderationStatus", "==", "pending")
    .limit(100)
    .get();
  return {
    places: snap.docs
      .filter((d) => d.data().deleted !== true)
      .map((d) => placeSummary(d.id, d.data())),
  };
}

async function moderatePlaceHandler(request) {
  requireSuperAdmin(request);
  const placeId = placeIdOf(request.data);
  const patch = moderationPatch(String((request.data || {}).decision || ""));
  if (!patch) throw new HttpsError("invalid-argument", "Invalid decision.");
  const ref = admin.firestore().collection("places").doc(placeId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Place not found.");
  const d = snap.data() || {};
  if (patch.active && !(d.coverUrl || (d.photoUrls || []).length)) {
    // O app só exibe locais com ao menos uma foto.
    throw new HttpsError("failed-precondition", "photo_required");
  }
  await ref.update({
    ...patch,
    moderatedAt: admin.firestore.FieldValue.serverTimestamp(),
    moderatedBy: request.auth.uid,
  });
  return { placeId, status: patch.status };
}

module.exports = {
  submitPlaceHandler,
  updateMyPlaceHandler,
  getMyPlaceHandler,
  listMyPlacesHandler,
  listPendingPlacesHandler,
  moderatePlaceHandler,
};
