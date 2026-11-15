"use strict";

const admin = require("firebase-admin");
const {
  shouldNotifyOnFirstAdultVerify,
  resolveOpsAdminUid,
  readHomeCountry,
  shouldSendOpsPush,
  buildOpsNewUserPayload,
  buildOpsInboxDoc,
  buildOpsPushCopy,
  assertOpsPayloadSafe,
  OPS_STATS_COLLECTION,
  OPS_STATS_DOC,
  OPS_SETTINGS_COLLECTION,
  OPS_SETTINGS_DOC,
  OPS_LEDGER_COLLECTION,
  OPS_FALLBACK_NAME,
  OPS_STATUS_AWAITING_PROFILE,
  readDisplayName,
  isProfileReadyForOpsNotice,
  isOpsNoticeAlreadySent,
} = require("./ops_new_user_notify_logic");

/**
 * After first adult verification: notify ONLY the ops admin (Willian).
 * Idempotent on opsNewUserNotices/{newUid}.
 * Counter always increments on first ledger create (even if push paused).
 * Push/sound skipped when adminOpsSettings/newUserNotify.pushPaused === true.
 */
async function notifyOpsAdminOfNewVerifiedUser({
  newUid,
  userData,
  priorStatus,
  newlyAdultVerified,
  envUid = process.env.OPS_ADMIN_UID || "",
  firestore = null,
  messaging = null,
} = {}) {
  if (!shouldNotifyOnFirstAdultVerify(priorStatus, newlyAdultVerified)) {
    return { skipped: true, reason: "not_first_adult_verify" };
  }
  const uid = (newUid || "").toString().trim();
  if (!uid) return { skipped: true, reason: "missing_uid" };

  const db = firestore || admin.firestore();
  const ledgerRef = db.collection(OPS_LEDGER_COLLECTION).doc(uid);
  const statsRef = db.collection(OPS_STATS_COLLECTION).doc(OPS_STATS_DOC);
  const settingsRef = db.collection(OPS_SETTINGS_COLLECTION).doc(OPS_SETTINGS_DOC);
  const country = readHomeCountry(userData);

  let created = false;
  let pushPaused = false;
  try {
    const txResult = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ledgerRef);
      if (snap.exists) {
        return { created: false };
      }
      const settingsSnap = await tx.get(settingsRef);
      const settings = settingsSnap.exists ? settingsSnap.data() || {} : {};
      const paused = shouldSendOpsPush(settings) !== true;

      tx.create(ledgerRef, {
        newUid: uid,
        country: country || null,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        status: OPS_STATUS_AWAITING_PROFILE,
        pushPausedAtCreate: paused,
      });
      // Canonical counter — independent of FCM delivery / pause.
      tx.set(
        statsRef,
        {
          count: admin.firestore.FieldValue.increment(1),
          lastAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return { created: true, pushPaused: paused };
    });
    created = txResult.created === true;
    pushPaused = txResult.pushPaused === true;
  } catch (e) {
    if (e && (e.code === 6 || e.code === "already-exists")) {
      return { skipped: true, reason: "duplicate" };
    }
    console.warn(
      JSON.stringify({
        action: "ops_new_user_ledger_failed",
        newUid: uid,
        message: (e && e.message) || "unknown",
      }),
    );
    return { skipped: true, reason: "ledger_error" };
  }

  if (!created) {
    return { skipped: true, reason: "duplicate" };
  }

  // Opção aprovada: aviso só quando houver nome E homeCountryCode.
  // No cadastro por e-mail o perfil ainda não existe aqui; o gatilho
  // onUserProfileReadyNotifyOps envia depois, uma única vez.
  if (!isProfileReadyForOpsNotice(userData)) {
    return { skipped: false, counted: true, reason: "awaiting_profile" };
  }
  const notice = await sendOpsNoticeIfReady({
    newUid: uid,
    userData,
    firestore: db,
    messaging,
    envUid,
  });
  return { skipped: false, counted: true, notice };
}

/**
 * Envia o aviso "Novo usuário Remdy" (caixa de avisos + push) uma única vez,
 * quando users/{uid} tem nome E homeCountryCode. Registros antigos contam
 * como já enviados (isOpsNoticeAlreadySent).
 */
async function sendOpsNoticeIfReady({
  newUid,
  userData,
  envUid = process.env.OPS_ADMIN_UID || "",
  firestore = null,
  messaging = null,
} = {}) {
  const uid = (newUid || "").toString().trim();
  if (!uid) return { skipped: true, reason: "missing_uid" };
  if (!isProfileReadyForOpsNotice(userData)) {
    return { skipped: true, reason: "profile_not_ready" };
  }
  const db = firestore || admin.firestore();
  const ledgerRef = db.collection(OPS_LEDGER_COLLECTION).doc(uid);

  // Leitura simples antes de qualquer transação.
  const pre = await ledgerRef.get();
  if (!pre.exists) return { skipped: true, reason: "no_ledger" };
  if (isOpsNoticeAlreadySent(pre.data())) {
    return { skipped: true, reason: "already_sent" };
  }

  const claimed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ledgerRef);
    if (!snap.exists || isOpsNoticeAlreadySent(snap.data())) return false;
    tx.update(ledgerRef, {
      status: "sending",
      noticeSentAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (!claimed) return { skipped: true, reason: "already_sent" };

  const country = readHomeCountry(userData);
  const adminsSnap = await db.collection("admins").get();
  const adminDocs = adminsSnap.docs.map((d) => ({
    uid: d.id,
    id: d.id,
    data: d.data() || {},
  }));
  const adminUid = resolveOpsAdminUid({ adminDocs, envUid });
  if (!adminUid) {
    await ledgerRef.set(
      {
        status: "counted_no_admin",
        error: "no_ops_admin",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { skipped: true, reason: "no_ops_admin" };
  }

  let payload = buildOpsNewUserPayload({
    newUid: uid,
    country,
    countryName: userData && userData.country,
    displayName: readDisplayName(userData),
    createdAtIso: new Date().toISOString(),
  });
  if (!assertOpsPayloadSafe(payload).ok) {
    payload = { ...payload, displayName: OPS_FALLBACK_NAME };
  }
  const safe = assertOpsPayloadSafe(payload);
  if (!safe.ok) {
    await ledgerRef.set(
      {
        status: "counted_unsafe_payload",
        error: safe.reason,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { skipped: true, reason: safe.reason };
  }

  const settingsSnap = await db
    .collection(OPS_SETTINGS_COLLECTION)
    .doc(OPS_SETTINGS_DOC)
    .get();
  const settings = settingsSnap.exists ? settingsSnap.data() || {} : {};
  const pushPaused = shouldSendOpsPush(settings) !== true;

  // Caixa de avisos sempre (mesmo com push pausado).
  const inbox = buildOpsInboxDoc(payload);
  await db
    .collection("users")
    .doc(adminUid)
    .collection("systemInbox")
    .add({
      ...inbox,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  let pushResult = { sent: 0, skipped: false, reason: null };
  if (pushPaused) {
    pushResult = { sent: 0, skipped: true, reason: "push_paused" };
  } else {
    try {
      const tokens = await collectOpsTokens(db, adminUid);
      if (tokens.length > 0) {
        const copy = buildOpsPushCopy(payload);
        const msg = messaging || admin.messaging();
        const resp = await msg.sendEachForMulticast({
          tokens,
          notification: { title: copy.title, body: copy.body },
          data: copy.data,
        });
        pushResult = {
          sent: resp.successCount || 0,
          failure: resp.failureCount || 0,
          skipped: false,
        };
      } else {
        pushResult = { sent: 0, skipped: true, reason: "no_tokens" };
      }
    } catch (e) {
      console.warn(
        JSON.stringify({
          action: "ops_new_user_push_failed",
          adminUid,
          message: (e && e.message) || "unknown",
        }),
      );
      pushResult = { sent: 0, skipped: true, reason: "push_error" };
    }
  }

  await ledgerRef.set(
    {
      status: "sent",
      adminUid,
      country,
      push: pushResult,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  return { skipped: false, adminUid, country, push: pushResult };
}

async function collectOpsTokens(db, uid) {
  const tokens = new Set();
  const userSnap = await db.collection("users").doc(uid).get();
  const main = ((userSnap.data() || {}).fcmToken || "").toString().trim();
  if (main) tokens.add(main);
  const sub = await db.collection("users").doc(uid).collection("fcmTokens").get();
  for (const d of sub.docs) {
    const t = ((d.data() || {}).token || d.id || "").toString().trim();
    if (t) tokens.add(t);
  }
  return [...tokens];
}

module.exports = {
  notifyOpsAdminOfNewVerifiedUser,
  sendOpsNoticeIfReady,
  collectOpsTokens,
};
