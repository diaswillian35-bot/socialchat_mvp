const { t, langFromUser } = require("../i18n/serverTexts");
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

  const byLang = new Map();
  let tokenCount = 0;
  for (const uid of found.uids) {
    const userSnap = await db.collection("users").doc(uid).get();
    const lang = langFromUser(userSnap.exists ? userSnap.data() : null);
    const tokens = await collectTokens(db, [uid]);
    if (!tokens.length) continue;
    if (!byLang.has(lang)) byLang.set(lang, []);
    byLang.get(lang).push(...tokens);
    tokenCount += tokens.length;
  }
  if (tokenCount === 0) {
    safeModerationLog("report_notice", {
      decision: "skipped",
      reason: "no_tokens",
      attempts: found.uids.length,
    });
    return { sent: false, reason: "no_tokens" };
  }

  let successCount = 0;
  let failureCount = 0;
  const reason = input.reasonCode;
  const total = input.total;
  for (const [lang, list] of byLang) {
    const tokens = [...new Set(list)];
    const title = (reason != null && total != null)
      ? t("push_report_title", lang)
      : String(input.title || "Remdy");
    const body = (reason != null && total != null)
      ? t("push_report_body", lang, { reason, total })
      : String(input.body || "");
    const response = await messaging.sendEachForMulticast({
      tokens,
      notification: {
        title: title.slice(0, 80),
        body: body.slice(0, 180),
      },
      data,
    });
    successCount += response ? response.successCount : 0;
    failureCount += response ? response.failureCount : 0;
  }
  safeModerationLog("report_notice", {
    decision: "sent",
    attempts: tokenCount,
    reason: `ok:${successCount}`,
  });
  return {
    sent: true,
    successCount,
    failureCount,
  };
}

module.exports = {
  sendOpsNoticeIfReady,
  collectAdminUids,
  collectTokens,
};
