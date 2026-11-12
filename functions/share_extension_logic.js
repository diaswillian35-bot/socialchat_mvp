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
  const status = userData && userData.moderation && userData.moderation.status;
  if (status === "suspended_pending_review" || status === "banned") {
    return "suspended";
  }
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

// Espelho de RemdyLaunchAccess.peopleCountryCodes (BR, CA e PT
// entre si). Premium continua a poder enviar para qualquer país.
const PEOPLE_COUNTRY_CODES = Object.freeze(["br", "ca", "pt"]);
const SHARE_PEOPLE_CAP = 50;

function pairKey(a, b) {
  return [String(a), String(b)].sort().join("_");
}

function canSendInternational(senderData, recipientData) {
  if (isPremiumUser(senderData)) return true;
  const a = countryOf(senderData);
  const b = countryOf(recipientData);
  if (!a || !b) return false;
  if (PEOPLE_COUNTRY_CODES.includes(a) && PEOPLE_COUNTRY_CODES.includes(b)) {
    return true;
  }
  return a === b;
}

function isHiddenOrBanned(userData = {}) {
  if (accountBlocked(userData)) return true;
  if (userData.hiddenFromLists === true) return true;
  if (userData.isBanned === true) return true;
  if (userData.status === "banned") return true;
  return false;
}

/**
 * Pessoa visível na lista da Share Extension.
 * Contactos (DM já existente) podem ser exploreOnly; os outros não.
 */
function shouldIncludeSharePerson({
  uid,
  otherUid,
  otherData = {},
  isContact = false,
  blocked = false,
}) {
  const id = String(otherUid || "").trim();
  if (!id || id === uid) return false;
  if (blocked) return false;
  if (isHiddenOrBanned(otherData)) return false;
  if (otherData.exploreOnly === true && !isContact) return false;
  return true;
}

function collectGroupMemberUids(groups, uid) {
  const out = [];
  const seen = new Set();
  for (const g of groups || []) {
    const data = g && g.data ? g.data : g || {};
    const raw = [
      ...(Array.isArray(data.members) ? data.members : []),
      data.ownerId,
      ...(Array.isArray(data.admins) ? data.admins : []),
    ];
    for (const m of raw) {
      const id = String(m == null ? "" : m).trim();
      if (!id || id === uid || seen.has(id)) continue;
      seen.add(id);
      out.push(id);
    }
  }
  return out;
}

/**
 * DMs existentes primeiro, depois membros de grupos, depois busca.
 * Dedup por otherUid (ou destinationId).
 */
function mergeSharePeople({
  conversations = [],
  groupMembers = [],
  searchHits = [],
  cap = SHARE_PEOPLE_CAP,
} = {}) {
  const seen = new Set();
  const out = [];
  const take = (list) => {
    for (const item of list || []) {
      if (out.length >= cap) return;
      const key = String((item && (item.otherUid || item.destinationId)) || "").trim();
      if (!key || seen.has(key)) continue;
      seen.add(key);
      out.push(item);
    }
  };
  take(conversations);
  take(groupMembers);
  take(searchHits);
  return out;
}

function tsMs(raw) {
  if (raw == null) return 0;
  if (typeof raw.toMillis === "function") return raw.toMillis();
  if (typeof raw === "number" && Number.isFinite(raw)) return raw;
  if (raw._seconds != null) return Number(raw._seconds) * 1000;
  return 0;
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
  PEOPLE_COUNTRY_CODES,
  SHARE_PEOPLE_CAP,
  pairKey,
  isHiddenOrBanned,
  shouldIncludeSharePerson,
  collectGroupMemberUids,
  mergeSharePeople,
  tsMs,
  containsPhone,
  normalizeShareText,
  publicDisplayName,
  publicPhotoUrl,
  publicLocationShort,
  evaluateRateLimit,
  idempotencyDocId,
};
