/**
 * Aviso de denúncia ao admin (FCM).
 * Módulo separado de qualquer aviso de usuário novo.
 * Sem texto de mensagem e sem nome do denunciante.
 *
 * Destinatários:
 *   1. appConfig/opsSettings.adminUids
 *   2. admins/{uid} com isActive != false
 * Tokens: users/{uid}.fcmToken e users/{uid}/fcmTokens.
 */

const { safeModerationLog } = require("./safe_log");

async function collectAdminUids(db) {
  const settingsSnap = await db.doc("appConfig/opsSettings").get();
  const settings = settingsSnap && settingsSnap.exists ? settingsSnap.data() || {} : {};
  if (settings.enabled === false) {
    return { disabled: true, uids: [] };
  }
  const configured = Array.isArray(settings.adminUids)
    ? settings.adminUids.map((id) => String(id || "").trim()).filter(Boolean)
    : [];
  if (configured.length) return { disabled: false, uids: configured.slice(0, 25) };

  const admins = await db.collection("admins").limit(25).get();
  const uids = [];
  for (const doc of admins.docs) {
    if (doc.data() && doc.data().isActive === false) continue;
    uids.push(doc.id);
  }
  return { disabled: false, uids };
}

async function collectTokens(db, uids) {
  const tokens = [];
  for (const uid of uids) {
    const userSnap = await db.collection("users").doc(uid).get();
    const legacy = userSnap.exists
      ? String((userSnap.data() && userSnap.data().fcmToken) || "").trim()
      : "";
    if (legacy) tokens.push(legacy);
    const sub = await db.collection("users").doc(uid).collection("fcmTokens").get();
    for (const doc of sub.docs) {
      const token = String((doc.data() && doc.data().token) || doc.id || "").trim();
      if (token) tokens.push(token);
    }
  }
  return [...new Set(tokens)];
}

async function sendOpsNoticeIfReady(input) {
  const db = input.db;
  const found = await collectAdminUids(db);
  if (found.disabled) {
    safeModerationLog("report_notice", { decision: "skipped", reason: "disabled" });
    return { sent: false, reason: "disabled" };
  }
  if (!found.uids.length) {
    safeModerationLog("report_notice", { decision: "skipped", reason: "no_admins" });
    return { sent: false, reason: "no_admins" };
  }
  const tokens = await collectTokens(db, found.uids);
  if (!tokens.length) {
    safeModerationLog("report_notice", {
      decision: "skipped",
      reason: "no_tokens",
      attempts: found.uids.length,
    });
    return { sent: false, reason: "no_tokens" };
  }
  const data = {};
  const src = input.data || {};
  for (const key of Object.keys(src)) {
    if (src[key] == null) continue;
    data[key] = String(src[key]).slice(0, 120);
  }
  const messaging = input.messaging;
  if (!messaging || typeof messaging.sendEachForMulticast !== "function") {
    safeModerationLog("report_notice", { decision: "skipped", reason: "no_messaging" });
    return { sent: false, reason: "no_messaging" };
  }
  const response = await messaging.sendEachForMulticast({
    tokens,
    notification: {
      title: String(input.title || "Remdy").slice(0, 80),
      body: String(input.body || "").slice(0, 180),
    },
    data,
  });
  safeModerationLog("report_notice", {
    decision: "sent",
    attempts: tokens.length,
    reason: `ok:${response && response.successCount ? response.successCount : 0}`,
  });
  return {
    sent: true,
    successCount: response ? response.successCount : 0,
    failureCount: response ? response.failureCount : 0,
  };
}

module.exports = {
  sendOpsNoticeIfReady,
  collectAdminUids,
  collectTokens,
};
