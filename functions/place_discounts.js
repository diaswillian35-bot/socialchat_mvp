"use strict";

const admin = require("firebase-admin");
const { httpsError } = require("./i18n/httpsError");
const { isSuperAdminAuth } = require("./super_admin");
const { canEditPlace } = require("./place_submission_logic");
const L = require("./place_discount_logic");

function requireAuth(request) {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw httpsError("unauthenticated", "Login required.");
  return uid;
}

function placeIdOf(data) {
  const id = String((data && data.placeId) || "").trim();
  if (!id || id.length > 128 || id.includes("/")) {
    throw httpsError("invalid-argument", "Invalid placeId.");
  }
  return id;
}

async function loadPlace(placeId) {
  const db = admin.firestore();
  const ref = db.collection("places").doc(placeId);
  const [snap, access] = await Promise.all([
    ref.get(),
    ref.collection("private").doc("access").get(),
  ]);
  return {
    db,
    ref,
    snap,
    access,
    placeData: snap.exists ? snap.data() : null,
    accessData: access.exists ? access.data() : null,
  };
}

function newPromotionId() {
  const { randomBytes } = require("crypto");
  return randomBytes(16).toString("hex");
}

function randomCodeChars() {
  const { randomBytes } = require("crypto");
  const bytes = randomBytes(4);
  let out = "";
  for (let i = 0; i < 4; i++) {
    out += L.CODE_ALPHABET[bytes[i] % L.CODE_ALPHABET.length];
  }
  return out;
}

function applyPatch(ref, patch, promotionId, uid) {
  const now = admin.firestore.FieldValue.serverTimestamp();
  const discount = {
    enabled: patch.enabled === true,
    active: patch.enabled === true && patch.validUntil.getTime() >= Date.now(),
    percent: patch.percent,
    validUntil: admin.firestore.Timestamp.fromDate(patch.validUntil),
    validUntilIso: patch.validUntil.toISOString(),
    condition: L.CONDITION,
    source: patch.source,
    coveredBy: patch.coveredBy,
    promotionId,
    updatedAt: now,
    updatedBy: uid,
  };
  return ref.update({
    discount,
    updatedAt: now,
  });
}

async function setPlaceDiscountHandler(request) {
  const uid = requireAuth(request);
  const data = request.data || {};
  const placeId = placeIdOf(data);
  const loaded = await loadPlace(placeId);
  const now = new Date();
  const decision = L.setDiscountDecision({
    uid,
    isSuperAdmin: isSuperAdminAuth(request.auth),
    placeData: loaded.placeData,
    accessData: loaded.accessData,
    exists: loaded.snap.exists,
    percent: data.percent,
    validUntilRaw: data.validUntil,
    enabled: data.enabled,
    now,
    canEdit: canEditPlace,
  });
  if (decision.error) {
    throw httpsError(decision.error.code, decision.error.message);
  }
  const promotionId = decision.promotionId || newPromotionId();
  await applyPatch(loaded.ref, decision.patch, promotionId, uid);
  return {
    ok: true,
    placeId,
    promotionId,
    enabled: decision.patch.enabled === true,
  };
}

async function setPlacePartnershipDiscountHandler(request) {
  const uid = requireAuth(request);
  const data = request.data || {};
  const placeId = placeIdOf(data);
  const loaded = await loadPlace(placeId);
  const now = new Date();
  const decision = L.setPartnershipDecision({
    uid,
    isSuperAdmin: isSuperAdminAuth(request.auth),
    placeData: loaded.placeData,
    accessData: loaded.accessData,
    exists: loaded.snap.exists,
    percent: data.percent,
    validUntilRaw: data.validUntil,
    enabled: data.enabled,
    coveredBy: data.coveredBy,
    now,
  });
  if (decision.error) {
    throw httpsError(decision.error.code, decision.error.message);
  }
  const promotionId = decision.promotionId || newPromotionId();
  await applyPatch(loaded.ref, decision.patch, promotionId, uid);
  return {
    ok: true,
    placeId,
    promotionId,
    enabled: decision.patch.enabled === true,
    coveredBy: decision.patch.coveredBy,
  };
}

function codesCol(ref) {
  return ref.collection("discountCodes");
}

function redemptionsCol(ref) {
  return ref.collection("discountRedemptions");
}

function openCol(ref) {
  // Doc por (promo + uid): get por id, sem índice composto.
  return ref.collection("discountOpen");
}

function redemptionId(promotionId, uid) {
  return `${promotionId}_${uid}`;
}

function openId(promotionId, uid) {
  return `${promotionId}_${uid}`;
}

async function issuePlaceDiscountCodeHandler(request) {
  const uid = requireAuth(request);
  const placeId = placeIdOf(request.data || {});
  const loaded = await loadPlace(placeId);
  const now = new Date();
  const discount = L.publicDiscount(loaded.placeData && loaded.placeData.discount, now);
  let alreadyRedeemed = false;
  let existingOpen = null;
  if (discount && discount.promotionId) {
    const [redSnap, openSnap] = await Promise.all([
      redemptionsCol(loaded.ref).doc(redemptionId(discount.promotionId, uid)).get(),
      openCol(loaded.ref).doc(openId(discount.promotionId, uid)).get(),
    ]);
    alreadyRedeemed = redSnap.exists;
    if (openSnap.exists) {
      const row = openSnap.data() || {};
      existingOpen = { ...row, code: row.code || openSnap.id };
    }
  }

  let decision;
  try {
    decision = L.issueCodeDecision({
      uid,
      placeData: loaded.placeData,
      exists: loaded.snap.exists,
      now,
      existingOpen,
      alreadyRedeemed,
    });
  } catch (e) {
    throw e;
  }
  if (decision.error) {
    throw httpsError(decision.error.code, decision.error.message);
  }
  if (decision.reuse) {
    return {
      ok: true,
      placeId,
      code: decision.code,
      payload: `RMD1:${placeId}:${decision.code}`,
      expiresAtMs: decision.expiresAt.getTime(),
      promotionId: decision.promotionId,
      percent: decision.percent,
      reused: true,
    };
  }

  let code;
  let ref;
  for (let i = 0; i < 6; i++) {
    code = L.formatCode(decision.percent, randomCodeChars());
    ref = codesCol(loaded.ref).doc(code);
    // eslint-disable-next-line no-await-in-loop
    const hit = await ref.get();
    if (!hit.exists) break;
    code = null;
  }
  if (!code) {
    throw httpsError("internal", "Could not allocate discount code.");
  }
  const expiresAt = decision.expiresAt;
  const payload = {
    uid,
    placeId,
    code,
    promotionId: decision.promotionId,
    percent: decision.percent,
    expiresAt: admin.firestore.Timestamp.fromDate(expiresAt),
    expiresAtIso: expiresAt.toISOString(),
    usedAt: null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  const batch = loaded.db.batch();
  batch.set(ref, payload);
  batch.set(openCol(loaded.ref).doc(openId(decision.promotionId, uid)), payload);
  await batch.commit();
  return {
    ok: true,
    placeId,
    code,
    payload: `RMD1:${placeId}:${code}`,
    expiresAtMs: expiresAt.getTime(),
    promotionId: decision.promotionId,
    percent: decision.percent,
    reused: false,
  };
}

async function redeemPlaceDiscountHandler(request) {
  const uid = requireAuth(request);
  const data = request.data || {};
  const placeId = placeIdOf(data);
  const code = L.normalizeCode(data.code);
  if (!/^REM-\d{1,2}-[A-Z0-9]{4}$/.test(code)) {
    throw httpsError("invalid-argument", "Discount code is invalid.");
  }
  const loaded = await loadPlace(placeId);
  const now = new Date();
  const issSnap = await codesCol(loaded.ref).doc(code).get();
  const issuance = issSnap.exists ? { code, ...issSnap.data() } : null;
  let alreadyRedeemed = false;
  if (issuance && issuance.promotionId && issuance.uid) {
    const redSnap = await redemptionsCol(loaded.ref).doc(
      redemptionId(issuance.promotionId, issuance.uid),
    ).get();
    alreadyRedeemed = redSnap.exists;
  }
  const decision = L.redeemDecision({
    uid,
    isSuperAdmin: isSuperAdminAuth(request.auth),
    placeData: loaded.placeData,
    accessData: loaded.accessData,
    exists: loaded.snap.exists,
    issuance,
    alreadyRedeemed,
    now,
    canEdit: canEditPlace,
  });
  if (decision.error) {
    throw httpsError(decision.error.code, decision.error.message);
  }
  const nowTs = admin.firestore.FieldValue.serverTimestamp();
  const batch = loaded.db.batch();
  batch.update(codesCol(loaded.ref).doc(code), {
    usedAt: nowTs,
    redeemedBy: uid,
  });
  batch.delete(openCol(loaded.ref).doc(openId(decision.promotionId, decision.uid)));
  batch.set(redemptionsCol(loaded.ref).doc(
    redemptionId(decision.promotionId, decision.uid),
  ), {
    uid: decision.uid,
    promotionId: decision.promotionId,
    code,
    percent: decision.percent,
    redeemedBy: uid,
    redeemedAt: nowTs,
  });
  await batch.commit();
  return {
    ok: true,
    placeId,
    code,
    percent: decision.percent,
    promotionId: decision.promotionId,
  };
}

module.exports = {
  setPlaceDiscountHandler,
  setPlacePartnershipDiscountHandler,
  issuePlaceDiscountCodeHandler,
  redeemPlaceDiscountHandler,
};
