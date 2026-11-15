"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {
  OPS_SETTINGS_COLLECTION,
  OPS_SETTINGS_DOC,
  OPS_STATS_COLLECTION,
  OPS_STATS_DOC,
  isOpsNewUserPushPaused,
  buildOpsNewUsersDisplay,
} = require("./ops_new_user_notify_logic");

async function requireOwnerAdmin(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Faça login para continuar.");
  }
  const uid = request.auth.uid;
  const snap = await admin.firestore().collection("admins").doc(uid).get();
  if (!snap.exists) {
    throw new HttpsError("permission-denied", "Admin only.");
  }
  const doc = snap.data() || {};
  if (doc.isActive === false || doc.isOwner !== true) {
    throw new HttpsError(
      "permission-denied",
      "Somente o administrador principal.",
    );
  }
  return { uid, adminDoc: doc };
}

/**
 * Pause/resume ONLY the push/sound to the ops admin phone.
 * Counter and systemInbox continue regardless.
 * Resume flips the flag only — does NOT replay skipped pushes.
 * Independent of sendAdminSystemNotice (manual Admin avisos).
 */
async function setOpsNewUserPushPausedHandler(request) {
  const { uid } = await requireOwnerAdmin(request);
  const paused = request.data?.pushPaused === true;
  const db = admin.firestore();
  const ref = db.collection(OPS_SETTINGS_COLLECTION).doc(OPS_SETTINGS_DOC);
  await ref.set(
    {
      pushPaused: paused,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedBy: uid,
    },
    { merge: true },
  );
  return { ok: true, pushPaused: paused };
}

/**
 * Snapshot for Admin TV/dashboard (no PII). Prefer Firestore listen when Rules allow;
 * this callable is a safe fallback.
 */
async function getOpsNewUserStatsHandler(request) {
  await requireOwnerAdmin(request);
  const db = admin.firestore();
  const [statsSnap, settingsSnap] = await Promise.all([
    db.collection(OPS_STATS_COLLECTION).doc(OPS_STATS_DOC).get(),
    db.collection(OPS_SETTINGS_COLLECTION).doc(OPS_SETTINGS_DOC).get(),
  ]);
  const stats = statsSnap.exists ? statsSnap.data() || {} : {};
  const settings = settingsSnap.exists ? settingsSnap.data() || {} : {};
  let lastAtIso = null;
  const lastAt = stats.lastAt;
  if (lastAt && typeof lastAt.toDate === "function") {
    lastAtIso = lastAt.toDate().toISOString();
  }
  const display = buildOpsNewUsersDisplay({
    count: typeof stats.count === "number" ? stats.count : 0,
    lastAtIso,
    pushPaused: isOpsNewUserPushPaused(settings),
  });
  return { ok: true, ...display };
}

const setOpsNewUserPushPaused = onCall(
  { region: "us-central1", cors: true },
  setOpsNewUserPushPausedHandler,
);

const getOpsNewUserStats = onCall(
  { region: "us-central1", cors: true },
  getOpsNewUserStatsHandler,
);

module.exports = {
  setOpsNewUserPushPaused,
  getOpsNewUserStats,
  setOpsNewUserPushPausedHandler,
  getOpsNewUserStatsHandler,
  requireOwnerAdmin,
};
