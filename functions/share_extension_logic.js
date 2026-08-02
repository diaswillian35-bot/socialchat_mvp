/**
 * Share Extension session — pure helpers (testable).
 *
 * TTL: 7 days. Justification: share-from-Safari is sporadic; forcing
 * re-open of Remdy every few hours breaks WhatsApp-like UX. Token is
 * opaque, scoped to share.list|share.send only, hashed at rest, and
 * revoked on logout / ban / account delete. Host renews on foreground
 * when remaining TTL < 50%.
 */

const crypto = require("crypto");

const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const IDEMPOTENCY_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const MAX_SESSIONS_PER_UID = 5;
const MAX_TEXT_CHARS = 800;
const MAX_HTTPS_LINKS = 5;
const SCOPES = Object.freeze(["share.list", "share.send"]);

const RATE = Object.freeze({
  listPerUid: { max: 60, windowMs: 60 * 60 * 1000 },
  sendPerUid: { max: 40, windowMs: 60 * 60 * 1000 },
  sendPerDest: { max: 20, windowMs: 60 * 60 * 1000 },
  issuePerUid: { max: 30, windowMs: 60 * 60 * 1000 },
});

function hashToken(token) {
  return crypto.createHash("sha256").update(String(token), "utf8").digest("hex");
}

function generateOpaqueToken() {
  return crypto.randomBytes(32).toString("base64url");
}

function generateSessionId() {
  return crypto.randomBytes(16).toString("hex");
}

function scopesOk(scopes) {
  if (!Array.isArray(scopes)) return false;
  return SCOPES.every((s) => scopes.includes(s));
}

function isExpired(expiresAtMs, nowMs = Date.now()) {
  return !Number.isFinite(expiresAtMs) || expiresAtMs <= nowMs;
}

function shouldRenew(expiresAtMs, nowMs = Date.now()) {
  if (isExpired(expiresAtMs, nowMs)) return true;
  const remaining = expiresAtMs - nowMs;
  return remaining < SESSION_TTL_MS * 0.5;
}

function accountBlocked(userData = {}) {
  if (userData.isBanned === true) return "banned";
  if (userData.shadowBan === true) return "shadow_ban";
  if (
    userData.accountDeleted === true ||
    userData.deleted === true ||
    userData.isDeleted === true
  ) {
    return "deleted";
  }
  return null;
}

function isPremiumUser(userData = {}) {
  if (userData.isMaster === true) return true;
  const until = userData.premiumUntil;
  if (until != null) {
    let ms = null;
    if (typeof until.toMillis === "function") ms = until.toMillis();
    else if (typeof until === "number") ms = until;
    else if (until._seconds != null) ms = until._seconds * 1000;
    if (ms != null && ms > Date.now()) return true;
  }
  if (userData.premiumUntil == null && userData.isPremium === true) return true;
  return false;
}

function countryOf(userData = {}) {
  const raw = userData.homeCountryCode || userData.countryCode || "";
  return String(raw).trim().toLowerCase();
}

function canSendInternational(senderData, recipientData) {
  if (isPremiumUser(senderData)) return true;
  const a = countryOf(senderData);
  const b = countryOf(recipientData);
  if (!a || !b) return true;
  return a === b;
}

function containsPhone(text) {
  const s = String(text || "");
  if (/\+\s?\d{1,3}/.test(s)) return true;
  if (/\d[\d\s().-]{7,}\d/.test(s)) return true;
  return false;
}

function normalizeShareText(raw) {
  const text = String(raw || "").trim();
  if (!text) return { ok: false, error: "empty" };
  if (text.length > MAX_TEXT_CHARS) return { ok: false, error: "too_long" };
  if (containsPhone(text)) return { ok: false, error: "phone" };

  // Reject dangerous schemes even when not matched as http(s) URLs.
  if (/\b(?:javascript|file|content|data|blob):/i.test(text)) {
    return { ok: false, error: "bad_scheme" };
  }

  const urlRe = /\bhttps?:\/\/[^\s<>"']+/gi;
  const matches = text.match(urlRe) || [];
  if (matches.length > MAX_HTTPS_LINKS) {
    return { ok: false, error: "too_many_links" };
  }
  for (const m of matches) {
    let u;
    try {
      u = new URL(m.replace(/[),.;]+$/g, ""));
    } catch (_) {
      return { ok: false, error: "bad_url" };
    }
    const proto = u.protocol.toLowerCase();
    if (proto === "http:") return { ok: false, error: "insecure_http" };
    if (proto !== "https:") return { ok: false, error: "bad_scheme" };
    if (u.hostname === "localhost" || u.hostname.endsWith(".local")) {
      return { ok: false, error: "bad_scheme" };
    }
  }
  return { ok: true, text };
}

function publicDisplayName(pub = {}, fallback = "") {
  const n =
    pub.displayName || pub.name || pub.username || fallback || "Remdy user";
  return String(n).trim().slice(0, 80);
}

function publicPhotoUrl(pub = {}) {
  const u = pub.photoUrl || pub.photoURL || pub.photo || "";
  const s = String(u).trim();
  if (!s.startsWith("https://")) return "";
  return s.slice(0, 500);
}

function publicLocationShort(pub = {}) {
  const city = pub.city || pub.homeCity || "";
  const country = pub.homeCountryCode || pub.countryCode || "";
  const parts = [city, country].map((x) => String(x || "").trim()).filter(Boolean);
  return parts.join(", ").slice(0, 80);
}

function evaluateRateLimit(docData, nowMs, max, windowMs) {
  const start =
    docData && Number.isFinite(docData.windowStartMs)
      ? docData.windowStartMs
      : nowMs;
  const count =
    docData && Number.isFinite(docData.count) ? docData.count : 0;
  if (nowMs - start >= windowMs) {
    return { allowed: true, windowStartMs: nowMs, count: 1 };
  }
  if (count >= max) {
    return { allowed: false, windowStartMs: start, count };
  }
  return { allowed: true, windowStartMs: start, count: count + 1 };
}

function idempotencyDocId(uid, intentId) {
  const safe = String(intentId || "")
    .replace(/[^A-Za-z0-9_-]/g, "")
    .slice(0, 128);
  return `${uid}_${safe || "empty"}`;
}

module.exports = {
  SESSION_TTL_MS,
  IDEMPOTENCY_TTL_MS,
  MAX_SESSIONS_PER_UID,
  MAX_TEXT_CHARS,
  MAX_HTTPS_LINKS,
  SCOPES,
  RATE,
  hashToken,
  generateOpaqueToken,
  generateSessionId,
  scopesOk,
  isExpired,
  shouldRenew,
  accountBlocked,
  isPremiumUser,
  countryOf,
  canSendInternational,
  containsPhone,
  normalizeShareText,
  publicDisplayName,
  publicPhotoUrl,
  publicLocationShort,
  evaluateRateLimit,
  idempotencyDocId,
};
