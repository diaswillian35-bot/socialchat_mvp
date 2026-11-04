/**
 * Decisão pura do processamento de denúncias.
 * Sem texto de mensagem, sem nome de denunciante.
 */

const CSAM_CODES = new Set([
  "child_sexual_exploitation_or_abuse",
  "csam",
]);

function isSystemReporter(fromUid) {
  return String(fromUid || "").trim() === "system";
}

function isCsamReport(data) {
  const d = data || {};
  const code = String(d.reasonCode || "").trim();
  const reason = String(d.reason || "").trim();
  if (CSAM_CODES.has(code) || CSAM_CODES.has(reason)) return true;
  return d.requiresChildSafetyReview === true && CSAM_CODES.has(code);
}

function dayKey(nowMs) {
  return new Date(nowMs).toISOString().slice(0, 10);
}

function rateLimitDocId(fromUid, nowMs) {
  return `${String(fromUid || "").trim()}_${dayKey(nowMs)}`;
}

/**
 * @param {object} input
 * @param {object} input.report
 * @param {number} input.dailyCount count AFTER counting this report
 * @param {number} input.distinctReporters distinct human reporters in 30 days
 * @param {number} input.strikes automatic strikes
 * @param {object} input.config
 */
function decideReportAction(input) {
  const report = input.report || {};
  const config = input.config || {};
  const limit = Number.isFinite(config.reportDailyLimit)
    ? config.reportDailyLimit
    : 20;
  const threshold = Number.isFinite(config.autoActionThreshold)
    ? config.autoActionThreshold
    : 3;
  const strikeThreshold = Number.isFinite(config.strikeThreshold)
    ? config.strikeThreshold
    : 3;
  const fromUid = String(report.fromUid || "").trim();
  const system = isSystemReporter(fromUid);
  const csam = isCsamReport(report);

  if (!system && (input.dailyCount || 0) > limit) {
    return {
      ignore: true,
      notify: false,
      suspend: false,
      priority: csam ? "critical" : "normal",
      csam,
      body: "",
    };
  }

  const distinct = Math.max(0, Number(input.distinctReporters) || 0);
  const strikes = Math.max(0, Number(input.strikes) || 0);
  const userCsam = csam && !system;
  // Uma denúncia CSAM de usuário não suspende sozinha.
  // Ela entra na contagem de denunciantes distintos e de strikes.
  const suspend =
    Boolean(input.reportedUid) &&
    ((csam && system) || distinct >= threshold || strikes >= strikeThreshold);
  const reasonCode = String(report.reasonCode || report.reason || "other")
    .replace(/[^\w.-]/g, "")
    .slice(0, 80) || "other";
  const total = distinct;
  return {
    ignore: false,
    notify: true,
    suspend,
    priority: csam ? "critical" : "normal",
    csam,
    userCsam,
    systemCsam: csam && system,
    reasonCode,
    body: `Nova denúncia · motivo: ${reasonCode} · total: ${total}`,
  };
}

module.exports = {
  isCsamReport,
  isSystemReporter,
  dayKey,
  rateLimitDocId,
  decideReportAction,
};
