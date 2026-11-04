/**
 * appConfig/moderation — lido pelas functions antes de qualquer ação.
 * enabled === false desliga sem deploy. Documento ausente = ligado, com defaults.
 */

const { DEFAULT_BLOCKED_DOMAINS } = require("./text_filter");

const CACHE_MS = 15000;
let cache = null;
let cacheAt = 0;

function normalizeConfig(data) {
  const d = data || {};
  const enabled = d.enabled === false ? false : true;
  const threshold = Number(d.autoActionThreshold);
  const strikes = Number(d.strikeThreshold);
  const daily = Number(d.reportDailyLimit);
  return {
    enabled,
    adultBlockAt: String(d.adultBlockAt || "LIKELY"),
    racyBlockAt: String(d.racyBlockAt || "VERY_LIKELY"),
    racyReviewAt: String(d.racyReviewAt || "LIKELY"),
    autoActionThreshold: Number.isFinite(threshold) && threshold > 0 ? threshold : 3,
    strikeThreshold: Number.isFinite(strikes) && strikes > 0 ? strikes : 3,
    reportDailyLimit: Number.isFinite(daily) && daily > 0 ? daily : 20,
    blockedDomains: Array.isArray(d.blockedDomains) && d.blockedDomains.length
      ? d.blockedDomains
      : DEFAULT_BLOCKED_DOMAINS.slice(),
  };
}

function resetModerationConfigCache() {
  cache = null;
  cacheAt = 0;
}

async function loadModerationConfig(db) {
  const now = Date.now();
  if (cache && now - cacheAt < CACHE_MS) return cache;
  try {
    const snap = await db.doc("appConfig/moderation").get();
    cache = normalizeConfig(snap && snap.exists ? snap.data() : null);
  } catch (_) {
    cache = normalizeConfig(null);
  }
  cacheAt = now;
  return cache;
}

module.exports = {
  normalizeConfig,
  loadModerationConfig,
  resetModerationConfigCache,
};
