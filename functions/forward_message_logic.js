/**
 * Forward message — pure helpers (testable).
 */

const MAX_DESTINATIONS = 5;
const MAX_TEXT_CHARS = 4000;
const MAX_AUDIO_DURATION_MS = 15 * 60 * 1000;
const IDEMPOTENCY_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const RATE = Object.freeze({
  forwardPerUid: { max: 40, windowMs: 60 * 60 * 1000 },
});

const ALLOWED_TYPES = new Set(["text", "image", "audio"]);

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

function pairKey(a, b) {
  return [String(a), String(b)].sort().join("_");
}

function isHttpsUrl(u) {
  const s = String(u || "").trim();
  if (!s.startsWith("https://")) return false;
  try {
    const parsed = new URL(s);
    return parsed.protocol === "https:";
  } catch (_) {
    return false;
  }
}

/** Reuse only remote HTTPS media — never file:// or local paths. */
function isReusableMediaUrl(u) {
  if (!isHttpsUrl(u)) return false;
  const host = new URL(String(u).trim()).hostname.toLowerCase();
  return (
    host.includes("firebasestorage.googleapis.com") ||
    host.includes("storage.googleapis.com") ||
    host.endsWith(".appspot.com")
  );
}

function sanitizeLinkPreview(raw) {
  if (!raw || typeof raw !== "object") return null;
  const url = String(raw.url || "").trim();
  if (!isHttpsUrl(url)) return null;
  const imageUrl = String(raw.imageUrl || "").trim();
  const out = {
    title: String(raw.title || "").trim().slice(0, 200),
    description: String(raw.description || "").trim().slice(0, 500),
    domain: String(raw.domain || "").trim().slice(0, 120),
    url: url.slice(0, 500),
  };
  if (imageUrl && isHttpsUrl(imageUrl)) {
    out.imageUrl = imageUrl.slice(0, 500);
  }
  return out;
}

function normalizeDestinations(raw) {
  if (!Array.isArray(raw)) return { ok: false, error: "bad_destinations" };
  if (raw.length === 0) return { ok: false, error: "empty_destinations" };
  if (raw.length > MAX_DESTINATIONS) {
    return { ok: false, error: "too_many_destinations" };
  }
  const seen = new Set();
  const list = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") {
      return { ok: false, error: "bad_destinations" };
    }
    const kind = String(item.kind || "").trim();
    if (kind === "dm") {
      const conversationId = String(item.conversationId || "").trim();
      const otherUid = String(item.otherUid || "").trim();
      if (!conversationId && !otherUid) {
        return { ok: false, error: "bad_destinations" };
      }
      const key = conversationId
        ? `dm:${conversationId}`
        : `dm_uid:${otherUid}`;
      if (seen.has(key)) continue;
      seen.add(key);
      list.push({ kind: "dm", conversationId, otherUid });
    } else if (kind === "group") {
      const groupId = String(item.groupId || "").trim();
      if (!groupId) return { ok: false, error: "bad_destinations" };
      const key = `group:${groupId}`;
      if (seen.has(key)) continue;
      seen.add(key);
      list.push({ kind: "group", groupId });
    } else {
      return { ok: false, error: "bad_destinations" };
    }
  }
  if (list.length === 0) return { ok: false, error: "empty_destinations" };
  return { ok: true, destinations: list };
}

function extractForwardableContent(msg = {}) {
  if (!msg || typeof msg !== "object") {
    return { ok: false, error: "missing" };
  }
  if (msg.deleted === true) return { ok: false, error: "deleted" };
  const type = String(msg.type || "text").trim().toLowerCase();
  if (!ALLOWED_TYPES.has(type)) return { ok: false, error: "bad_type" };

  if (type === "text") {
    const text = String(msg.text || "").trim();
    if (!text) return { ok: false, error: "empty_text" };
    if (text.length > MAX_TEXT_CHARS) return { ok: false, error: "too_long" };
    const preview = sanitizeLinkPreview(msg.linkPreview);
    return { ok: true, type: "text", text, linkPreview: preview };
  }
  if (type === "image") {
    const imageUrl = String(msg.imageUrl || "").trim();
    if (!isReusableMediaUrl(imageUrl)) return { ok: false, error: "bad_media" };
    return { ok: true, type: "image", imageUrl };
  }
  // audio
  const audioUrl = String(msg.audioUrl || "").trim();
  if (!isReusableMediaUrl(audioUrl)) return { ok: false, error: "bad_media" };
  const durationMs = Number(msg.durationMs);
  if (!Number.isFinite(durationMs) || durationMs <= 0) {
    return { ok: false, error: "bad_audio_duration" };
  }
  if (durationMs > MAX_AUDIO_DURATION_MS) {
    return { ok: false, error: "audio_too_long" };
  }
  return { ok: true, type: "audio", audioUrl, durationMs: Math.round(durationMs) };
}

function callerCanReadMessage(msg, uid, { hiddenField = "hiddenFor" } = {}) {
  if (!msg) return false;
  if (msg.deleted === true) return false;
  const hidden = Array.isArray(msg[hiddenField])
    ? msg[hiddenField].map(String)
    : [];
  if (hidden.includes(uid)) return false;
  // Group uses deletedFor
  const deletedFor = Array.isArray(msg.deletedFor)
    ? msg.deletedFor.map(String)
    : [];
  if (deletedFor.includes(uid)) return false;
  return true;
}

function isParticipating(groupData, uid) {
  const members = Array.isArray(groupData.members)
    ? groupData.members.map(String)
    : [];
  if (members.includes(uid)) return true;
  if (String(groupData.ownerId || "") === uid) return true;
  const admins = Array.isArray(groupData.admins)
    ? groupData.admins.map(String)
    : [];
  return admins.includes(uid);
}

function idempotencyDocId(uid, intentId) {
  const safe = String(intentId || "")
    .replace(/[^A-Za-z0-9_-]/g, "")
    .slice(0, 128);
  return `fwd_${uid}_${safe || "empty"}`;
}

module.exports = {
  MAX_DESTINATIONS,
  MAX_TEXT_CHARS,
  IDEMPOTENCY_TTL_MS,
  RATE,
  ALLOWED_TYPES,
  evaluateRateLimit,
  accountBlocked,
  isPremiumUser,
  countryOf,
  canSendInternational,
  pairKey,
  isHttpsUrl,
  isReusableMediaUrl,
  sanitizeLinkPreview,
  normalizeDestinations,
  extractForwardableContent,
  callerCanReadMessage,
  isParticipating,
  idempotencyDocId,
};
