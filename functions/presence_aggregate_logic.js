/** Lógica pura — sem deps Firebase (testável no mocha local). */

/** Alinhado a OnlineStatus.onlineWindow + clockSkewTolerance (90s + 45s). */
const ONLINE_WINDOW_MS = (90 + 45) * 1000;

function toMillis(value) {
  if (!value) return null;
  if (typeof value.toMillis === "function") return value.toMillis();
  if (typeof value === "number") return value;
  return null;
}

/**
 * @param {{ data: () => object }[]} sessionDocs
 * @param {number} nowMs
 */
function computeAggregateFromSessions(sessionDocs, nowMs) {
  let anyOnline = false;
  let latestSeenMs = null;

  for (const doc of sessionDocs) {
    const d = doc.data() || {};
    if (d.isOnline !== true) continue;
    const ls = toMillis(d.lastSeenAt);
    if (ls == null) continue;
    const age = nowMs - ls;
    if (age < 0 || age <= ONLINE_WINDOW_MS) {
      anyOnline = true;
      if (latestSeenMs == null || ls > latestSeenMs) latestSeenMs = ls;
    }
  }

  return { anyOnline, latestSeenMs };
}

module.exports = {
  ONLINE_WINDOW_MS,
  computeAggregateFromSessions,
  toMillis,
};
