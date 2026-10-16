"use strict";

const { HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {
  parseReviewInput,
  parseReplyInput,
  parseClaimInput,
  canReceiveReviews,
  canManage,
  claimId,
  ratingAfterPendingEdit,
} = require("./place_actions_logic");

function fail(code, message) {
  throw new HttpsError(code, message);
}

async function tokensFor(db, uid) {
  const user = await db.collection("users").doc(uid).get();
  const entries = await user.ref.collection("fcmTokens").get();
  const tokens = new Set();
  const legacy = String((user.data() || {}).fcmToken || "").trim();
  if (legacy) tokens.add(legacy);
  entries.docs.forEach((doc) => {
    const token = String(doc.data().token || doc.id || "").trim();
    if (token) tokens.add(token);
  });
  return [...tokens];
}

async function placePush(db, uid, title, body, placeId, type) {
  if (!uid) return;
  const tokens = await tokensFor(db, uid);
  if (!tokens.length) return;
  await admin.messaging().sendEachForMulticast({
    tokens,
    notification: { title, body },
    data: { type, placeId },
    android: { priority: "high", notification: { channelId: "high_importance_channel", priority: "high", sound: "default" } },
    apns: { headers: { "apns-priority": "10" }, payload: { aps: { alert: { title, body }, sound: "default" } } },
  });
}

async function submitReviewHandler(request, deps = {}) {
  const uid = request.auth && request.auth.uid;
  if (!uid) fail("unauthenticated", "authentication_required");
  const parsed = parseReviewInput(request.data);
  if (!parsed.ok) fail("invalid-argument", parsed.code);
  const db = deps.db || admin.firestore();
  const now = deps.now || new Date();
  const placeRef = db.collection("places").doc(parsed.placeId);
  const accessRef = placeRef.collection("private").doc("access");
  const reviewRef = placeRef.collection("reviews").doc(uid);
  const rateRef = db.collection("placeReviewRate").doc(uid);
  const userRef = db.collection("users").doc(uid);
  const [placeSnap, accessSnap, userSnap] = await Promise.all([placeRef.get(), accessRef.get(), userRef.get()]);
  const place = placeSnap.data();
  if (!canReceiveReviews(place)) fail("failed-precondition", "place_unavailable");
  if (canManage(accessSnap.data(), uid)) fail("permission-denied", "owner_cannot_review");
  let action = "created";
  await db.runTransaction(async (tx) => {
    const [current, currentPlace, rateSnap] = await Promise.all([
      tx.get(reviewRef), tx.get(placeRef), tx.get(rateRef),
    ]);
    if (!canReceiveReviews(currentPlace.data())) fail("failed-precondition", "place_unavailable");
    const recent = Array.isArray(rateSnap.data()?.writes)
      ? rateSnap.data().writes.filter((at) => Number.isFinite(at) && now.getTime() - at < 60 * 60 * 1000)
      : [];
    const last = recent.length ? recent[recent.length - 1] : 0;
    if (recent.length >= 8 || (last && now.getTime() - last < 30000)) fail("resource-exhausted", "review_rate");
    action = current.exists ? "updated" : "created";
    const existing = current.data() || {};
    const publicId = String(existing.publicId || `rev_${reviewRef.id}`);
    const displayName = String((userSnap.data() || {}).displayName || request.auth.token.name || "Visitante").trim().split(/\s+/)[0].slice(0, 60) || "Visitante";
    tx.set(reviewRef, {
      contractVersion: "remdy.places.reviews.v1",
      publicId,
      placeId: parsed.placeId,
      stars: parsed.stars,
      comment: parsed.comment,
      status: "pending",
      authorDisplayName: displayName,
      primary: true,
      ownerReply: existing.ownerReply || null,
      createdAtIso: existing.createdAtIso || now.toISOString(),
      updatedAtIso: now.toISOString(),
      editedAtIso: current.exists ? now.toISOString() : null,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    const placeRow = currentPlace.data() || {};
    const ratingPatch = ratingAfterPendingEdit(placeRow, current.exists ? existing : null);
    if (ratingPatch) {
      tx.set(placeRef, { ...ratingPatch, rating: { ...ratingPatch.rating, updatedAtIso: now.toISOString() }, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
    }
    tx.set(rateRef, { writes: [...recent, now.getTime()], updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
  });
  const access = accessSnap.data() || {};
  const recipients = [...new Set([access.ownerUid, ...(Array.isArray(access.managerUids) ? access.managerUids : [])])].filter((id) => id && id !== uid);
  const placeName = String(place.name || "Local").slice(0, 80);
  await Promise.all(recipients.map((id) => placePush(db, id, "Nova avaliação", `Há uma nova avaliação em ${placeName}.`, parsed.placeId, "place_review").catch(() => undefined)));
  return { ok: true, action, moderationStatus: "pending" };
}

async function replyHandler(request, deps = {}) {
  const uid = request.auth && request.auth.uid;
  if (!uid) fail("unauthenticated", "authentication_required");
  const parsed = parseReplyInput(request.data);
  if (!parsed.ok) fail("invalid-argument", parsed.code);
  const db = deps.db || admin.firestore();
  const now = deps.now || new Date();
  const placeRef = db.collection("places").doc(parsed.placeId);
  const access = (await placeRef.collection("private").doc("access").get()).data();
  if (!canManage(access, uid)) fail("permission-denied", "not_place_manager");
  const reviews = await placeRef.collection("reviews").where("publicId", "==", parsed.reviewId).limit(1).get();
  if (reviews.empty) fail("not-found", "review_not_found");
  const review = reviews.docs[0];
  const data = review.data();
  if (data.status !== "approved" && data.status !== "published") fail("failed-precondition", "review_not_public");
  await review.ref.set({ ownerReply: { text: parsed.text, authorRole: "owner", createdAtIso: data.ownerReply?.createdAtIso || now.toISOString(), updatedAtIso: now.toISOString() }, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
  const place = (await placeRef.get()).data() || {};
  await placePush(db, review.id, "Resposta do estabelecimento", `${String(place.name || "Local").slice(0, 80)} respondeu sua avaliação.`, parsed.placeId, "place_reply").catch(() => undefined);
  return { ok: true };
}

async function claimHandler(request, deps = {}) {
  const uid = request.auth && request.auth.uid;
  if (!uid) fail("unauthenticated", "authentication_required");
  const parsed = parseClaimInput(request.data);
  if (!parsed.ok) fail("invalid-argument", parsed.code);
  const db = deps.db || admin.firestore();
  const now = deps.now || new Date();
  const placeRef = db.collection("places").doc(parsed.placeId);
  const [placeSnap, accessSnap, userSnap] = await Promise.all([placeRef.get(), placeRef.collection("private").doc("access").get(), db.collection("users").doc(uid).get()]);
  if (!placeSnap.exists || placeSnap.data().deleted === true) fail("not-found", "place_not_found");
  if (canManage(accessSnap.data(), uid)) fail("already-exists", "already_linked");
  const id = claimId(parsed.placeId, uid);
  const protocol = `LOC-REV-${now.toISOString().slice(0, 10).replace(/-/g, "")}-${id.slice(-4).toUpperCase()}`;
  await db.collection("placeClaims").doc(id).set({
    id, protocol, placeId: parsed.placeId, claimantUid: uid,
    claimantName: String((userSnap.data() || {}).displayName || request.auth.token.name || "").slice(0, 100),
    contactEmail: String(request.auth.token.email || "").slice(0, 200),
    phone: parsed.phone, role: parsed.role, note: parsed.note,
    status: "pending", source: "app", createdAtIso: now.toISOString(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  return { ok: true, protocol, status: "pending" };
}

async function listReviewsHandler(request, deps = {}) {
  const uid = request.auth && request.auth.uid;
  if (!uid) fail("unauthenticated", "authentication_required");
  const parsed = parseClaimInput({ placeId: request.data && request.data.placeId, phone: "000000" });
  if (!parsed.ok) fail("invalid-argument", "place");
  const db = deps.db || admin.firestore();
  const placeRef = db.collection("places").doc(parsed.placeId);
  const place = (await placeRef.get()).data();
  if (!canReceiveReviews(place)) fail("not-found", "place_not_found");
  const snap = await placeRef.collection("reviews").where("status", "in", ["approved", "published"]).limit(20).get();
  return { reviews: snap.docs.map((doc) => {
    const row = doc.data();
    return {
      publicId: String(row.publicId || "").slice(0, 120),
      authorDisplayName: String(row.authorDisplayName || "Visitante").slice(0, 60),
      stars: Number(row.stars) || 0,
      comment: String(row.comment || "").slice(0, 1500),
      status: row.status,
      ownerReply: row.ownerReply && typeof row.ownerReply === "object" ? {
        text: String(row.ownerReply.text || "").slice(0, 800),
        createdAtIso: String(row.ownerReply.createdAtIso || "").slice(0, 40),
      } : null,
      createdAtIso: String(row.createdAtIso || "").slice(0, 40),
    };
  }) };
}

exports.submitReviewHandler = submitReviewHandler;
exports.replyHandler = replyHandler;
exports.claimHandler = claimHandler;
exports.listReviewsHandler = listReviewsHandler;
