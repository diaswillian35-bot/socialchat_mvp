/**
 * Pure push-delivery helpers (no firebase-admin).
 * Used by functions/index.js and unit tests.
 */

/** Permanent FCM registration failures — safe to delete token docs. */
const PERMANENT_INVALID_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

/** Transient / infra — never delete tokens for these. */
const TRANSIENT_CODES = new Set([
  "messaging/server-unavailable",
  "messaging/internal-error",
  "messaging/unknown-error",
  "messaging/message-rate-exceeded",
  "messaging/device-message-rate-exceeded",
  "messaging/topics-message-rate-exceeded",
  "messaging/third-party-auth-error", // APNs/FCM auth misconfig — not a dead token
  "messaging/mismatched-credential",
  "messaging/invalid-apns-credentials",
  "messaging/invalid-argument", // often payload; do not wipe tokens
]);

function sanitizeMessagingErrorCode(code) {
  const c = (code == null ? "" : String(code)).trim();
  if (!c) return "unknown";
  return c.length > 120 ? c.slice(0, 120) : c;
}

function isPermanentInvalidRegistrationCode(code) {
  return PERMANENT_INVALID_CODES.has(sanitizeMessagingErrorCode(code));
}

function isTransientMessagingCode(code) {
  return TRANSIENT_CODES.has(sanitizeMessagingErrorCode(code));
}

/**
 * Normalize platform label from fcmTokens doc / unknown.
 * @param {string|null|undefined} platform
 * @returns {'ios'|'android'|'unknown'}
 */
function normalizePlatform(platform) {
  const p = (platform == null ? "" : String(platform)).trim().toLowerCase();
  if (p === "ios" || p === "iphone" || p === "ipad") return "ios";
  if (p === "android") return "android";
  return "unknown";
}

/**
 * Build platform map from token entries.
 * @param {Array<{token:string, platform?:string}>} entries
 * @returns {Map<string, string>}
 */
function platformMapFromEntries(entries) {
  const map = new Map();
  for (const e of entries || []) {
    const token = (e && e.token ? String(e.token) : "").trim();
    if (!token) continue;
    // Prefer first known platform; don't overwrite ios/android with unknown.
    const next = normalizePlatform(e.platform);
    const prev = map.get(token);
    if (!prev || (prev === "unknown" && next !== "unknown")) {
      map.set(token, next);
    }
  }
  return map;
}

/**
 * Summarize multicast results by platform (no tokens in output).
 * @param {string[]} tokens ordered list passed to sendEachForMulticast
 * @param {{success:boolean, error?:{code?:string}}[]} responses
 * @param {Map<string,string>|Record<string,string>} platformByToken
 */
function summarizePushResultsByPlatform(tokens, responses, platformByToken) {
  const lookup = (t) => {
    if (!platformByToken) return "unknown";
    if (typeof platformByToken.get === "function") {
      return normalizePlatform(platformByToken.get(t) || "unknown");
    }
    return normalizePlatform(platformByToken[t] || "unknown");
  };

  const empty = () => ({
    success: 0,
    fail: 0,
    codes: /** @type {string[]} */ ([]),
  });
  const by = {
    ios: empty(),
    android: empty(),
    unknown: empty(),
  };

  const list = Array.isArray(tokens) ? tokens : [];
  const resps = Array.isArray(responses) ? responses : [];
  for (let i = 0; i < list.length; i++) {
    const token = (list[i] || "").toString().trim();
    const r = resps[i] || { success: false };
    const plat = lookup(token);
    const bucket = by[plat] || by.unknown;
    if (r.success) {
      bucket.success += 1;
    } else {
      bucket.fail += 1;
      bucket.codes.push(
        sanitizeMessagingErrorCode(r.error && r.error.code),
      );
    }
  }

  return {
    ios: by.ios,
    android: by.android,
    unknown: by.unknown,
    successTotal: by.ios.success + by.android.success + by.unknown.success,
    failTotal: by.ios.fail + by.android.fail + by.unknown.fail,
  };
}

/**
 * Tokens that are safe to delete after a multicast response.
 * Only permanent invalid-registration codes.
 */
function collectPermanentInvalidTokens(tokens, responses) {
  const invalid = [];
  const list = Array.isArray(tokens) ? tokens : [];
  const resps = Array.isArray(responses) ? responses : [];
  for (let i = 0; i < list.length; i++) {
    const r = resps[i];
    if (!r || r.success) continue;
    const code = r.error && r.error.code;
    if (!isPermanentInvalidRegistrationCode(code)) continue;
    if (isTransientMessagingCode(code)) continue; // belt-and-suspenders
    const token = (list[i] || "").toString().trim();
    if (token) invalid.push(token);
  }
  return [...new Set(invalid)];
}

/**
 * Whether legacy users.fcmToken should be cleared for this user.
 * Only when legacy exactly matches a permanently invalid token.
 */
function shouldClearLegacyFcmToken(legacyToken, invalidTokens) {
  const legacy = (legacyToken == null ? "" : String(legacyToken)).trim();
  if (!legacy) return false;
  const set = new Set(
    (invalidTokens || []).map((t) => String(t || "").trim()).filter(Boolean),
  );
  return set.has(legacy);
}

/**
 * Badge sent with a DM/group alert.
 *
 * Do not scan every conversation and group before FCM. That scan blocked
 * APNs/FCM until it finished, and on a large group it could run until the
 * function timed out — later members then got no push. The app reconciles
 * the exact icon count from Firestore when it resumes.
 * @returns {number}
 */
function badgeForImmediateMessagePush() {
  return 1;
}

const ANDROID_HIGH_IMPORTANCE_CHANNEL_ID = "high_importance_channel";

/**
 * Android delivery for a visible chat/group alert (background and killed).
 * Message priority `high` wakes Doze. Notification priority `high` plus the
 * app channel keep the banner from landing on the low-importance fallback.
 * @param {string} [imageUrl]
 */
function buildAndroidMessageConfig(imageUrl) {
  const image = (imageUrl || "").toString().trim();
  const notification = {
    sound: "default",
    channelId: ANDROID_HIGH_IMPORTANCE_CHANNEL_ID,
    priority: "high",
  };
  if (image.startsWith("https://") || image.startsWith("http://")) {
    notification.imageUrl = image;
  }
  return {
    priority: "high",
    notification,
  };
}

/**
 * APNs alert for a visible chat/group notification.
 * Priority 10 + push-type alert is immediate delivery. Priority 5 is the
 * background/power-saving path and is not used here.
 * @param {string} title
 * @param {string} body
 * @param {string} [imageUrl]
 * @param {number} [badge]
 */
function buildApnsMessageConfig(title, body, imageUrl, badge) {
  const image = (imageUrl || "").toString().trim();
  const hasImage = image.startsWith("https://") || image.startsWith("http://");
  const badgeCount =
    typeof badge === "number" && Number.isFinite(badge) && badge >= 0
      ? Math.floor(badge)
      : badgeForImmediateMessagePush();
  const config = {
    headers: {
      "apns-priority": "10",
      "apns-push-type": "alert",
    },
    payload: {
      aps: {
        alert: { title, body },
        sound: "default",
        badge: badgeCount,
      },
    },
  };
  if (hasImage) {
    config.payload.aps["mutable-content"] = 1;
    config.fcmOptions = { imageUrl: image };
  }
  return config;
}

/**
 * Format a one-line sanitized summary for Cloud Logging.
 */
function formatPushPlatformLog(summary) {
  const s = summary || {};
  const part = (name, b) => {
    const block = b || { success: 0, fail: 0, codes: [] };
    const codes = Array.isArray(block.codes) ? block.codes : [];
    return `${name}:{ok:${block.success||0},fail:${block.fail||0},codes:${JSON.stringify(codes)}}`;
  };
  return [
    part("ios", s.ios),
    part("android", s.android),
    part("unknown", s.unknown),
    `total:{ok:${s.successTotal || 0},fail:${s.failTotal || 0}}`,
  ].join(" ");
}

module.exports = {
  PERMANENT_INVALID_CODES,
  TRANSIENT_CODES,
  sanitizeMessagingErrorCode,
  isPermanentInvalidRegistrationCode,
  isTransientMessagingCode,
  normalizePlatform,
  platformMapFromEntries,
  summarizePushResultsByPlatform,
  collectPermanentInvalidTokens,
  shouldClearLegacyFcmToken,
  formatPushPlatformLog,
  badgeForImmediateMessagePush,
  ANDROID_HIGH_IMPORTANCE_CHANNEL_ID,
  buildAndroidMessageConfig,
  buildApnsMessageConfig,
};
