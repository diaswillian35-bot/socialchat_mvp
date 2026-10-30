"use strict";

/**
 * Cota de caracteres em DM entre países, configurável sem deploy:
 * documento Firestore appConfig/dmQuota { enabled: boolean, limit: number }.
 * Ausente ou enabled !== true → DESLIGADA (lançamento: tudo liberado).
 */
const DM_QUOTA_CONFIG_PATH = "appConfig/dmQuota";

function parseDmQuotaConfig(data) {
  const enabled = Boolean(data && data.enabled === true);
  const limit = data && Number.isFinite(data.limit) && data.limit > 0
    ? Math.floor(data.limit)
    : 1500;
  return { enabled, limit };
}

async function readDmQuotaConfig(db) {
  try {
    const snap = await db.doc(DM_QUOTA_CONFIG_PATH).get();
    return parseDmQuotaConfig(snap.exists ? snap.data() : null);
  } catch (_) {
    return parseDmQuotaConfig(null);
  }
}

module.exports = { DM_QUOTA_CONFIG_PATH, parseDmQuotaConfig, readDmQuotaConfig };
