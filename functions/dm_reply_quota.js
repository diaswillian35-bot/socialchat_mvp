/**
 * Franquia de resposta Free em DM internacional iniciada/permitida por Premium.
 *
 * Contagem canônica: Unicode scalar values (code points).
 * - JS: iterate codePointAt
 * - Dart: String.runes.length
 * NÃO usar String.length (UTF-16) nem size() de Rules (UTF-8 bytes).
 *
 * Fonte de verdade: conversations/{cid}.replyQuota (somente Admin SDK).
 * Envios Free sob franquia: Callable sendDmMessage (não confiar no cliente).
 */

const REPLY_QUOTA_LIMIT = 300;
const REPLY_QUOTA_VERSION = 1;
const MAX_TEXT_CODE_POINTS = 800;
const MIN_REQUEST_ID = 8;
const MAX_REQUEST_ID = 128;
const IDEMPOTENCY_TTL_MS = 7 * 24 * 60 * 60 * 1000;

function countCodePoints(text) {
  const s = text == null ? "" : String(text);
  let n = 0;
  for (let i = 0; i < s.length; ) {
    const cp = s.codePointAt(i);
    n += 1;
    i += cp > 0xffff ? 2 : 1;
  }
  return n;
}

function isPremiumUser(userData = {}, nowMs = Date.now()) {
  if (userData.isMaster === true) return true;
  const until = userData.premiumUntil;
  if (until != null) {
    let ms = null;
    if (typeof until.toMillis === "function") ms = until.toMillis();
    else if (typeof until === "number") ms = until;
    else if (until._seconds != null) ms = until._seconds * 1000;
    if (ms != null && ms > nowMs) return true;
  }
  if (userData.premiumUntil == null && userData.isPremium === true) return true;
  return false;
}

function countryOf(userData = {}) {
  const raw = userData.homeCountryCode || userData.countryCode || "";
  return String(raw).trim().toLowerCase();
}

function isInternational(senderData, recipientData) {
  const a = countryOf(senderData);
  const b = countryOf(recipientData);
  if (!a || !b) return false;
  return a !== b;
}

/** Mesmo país (ou país ausente) → escrita cliente livre; sem franquia. */
function canSendViaClientWrite(senderData, recipientData, nowMs = Date.now()) {
  if (isPremiumUser(senderData, nowMs)) return true;
  return !isInternational(senderData, recipientData);
}

/**
 * Free internacional sob franquia somente se:
 * - já existe replyQuota server-side para este Free, OU
 * - o outro participante está Premium agora (conv intl só é criada por Premium nas Rules).
 * Free↔Free internacional sem quota → sem franquia (nega).
 */
function isPremiumInitiatedReplyFranchise({
  senderUid,
  senderData,
  recipientData,
  existingQuota,
  nowMs = Date.now(),
}) {
  if (isPremiumUser(senderData, nowMs)) return false;
  if (!isInternational(senderData, recipientData)) return false;
  const quota = readReplyQuota(existingQuota);
  if (quota && quota.enabled && quota.freeUid === senderUid) return true;
  return isPremiumUser(recipientData, nowMs);
}

/**
 * Free internacional com franquia Premium→Free → Callable.
 * Premium / Free mesmo país → false (Firestore cliente).
 */
function requiresReplyQuotaCallable(
  senderData,
  recipientData,
  existingQuota,
  senderUid,
  nowMs = Date.now(),
) {
  return isPremiumInitiatedReplyFranchise({
    senderUid: senderUid || "",
    senderData,
    recipientData,
    existingQuota,
    nowMs,
  });
}

function readReplyQuota(raw) {
  if (!raw || typeof raw !== "object") return null;
  const freeUid = String(raw.freeUid || "").trim();
  if (!freeUid) return null;
  const limit = Number.isFinite(raw.limit) ? Math.floor(raw.limit) : REPLY_QUOTA_LIMIT;
  const used = Number.isFinite(raw.used) ? Math.max(0, Math.floor(raw.used)) : 0;
  return {
    version: Number.isFinite(raw.version) ? raw.version : REPLY_QUOTA_VERSION,
    enabled: raw.enabled !== false,
    freeUid,
    initiatorUid: String(raw.initiatorUid || "").trim(),
    limit: Math.max(0, limit),
    used,
  };
}

function remainingQuota(quota) {
  if (!quota || !quota.enabled) return 0;
  return Math.max(0, quota.limit - quota.used);
}

/**
 * Simula commits serializados (como a transação Firestore).
 * Dois "reads" concorrentes em used=299: só o primeiro commit sobrevive.
 */
function commitSerializedFreeTexts({
  senderUid,
  senderData,
  recipientData,
  initialUsed,
  texts,
  initiatorUid = "",
}) {
  let used = initialUsed;
  const outcomes = [];
  for (const text of texts) {
    const authz = authorizeFreeTextSend({
      senderUid,
      senderData,
      recipientData,
      existingQuota: {
        freeUid: senderUid,
        used,
        limit: REPLY_QUOTA_LIMIT,
        enabled: true,
        initiatorUid,
      },
      text,
      messageType: "text",
    });
    outcomes.push(authz);
    if (authz.ok && authz.mode === "quota") {
      used = authz.quotaAfter.used;
    }
  }
  return { used, outcomes };
}

/**
 * Autorização server-side para um envio Free sob franquia.
 * Não confia em used/limit enviados pelo cliente.
 */
function authorizeFreeTextSend({
  senderUid,
  senderData,
  recipientData,
  existingQuota,
  text,
  messageType = "text",
  recipientUid = "",
  nowMs = Date.now(),
}) {
  if (isPremiumUser(senderData, nowMs)) {
    return { ok: true, mode: "unlimited_premium", consume: 0 };
  }

  if (!isInternational(senderData, recipientData)) {
    return { ok: true, mode: "same_country_free", consume: 0 };
  }

  if (
    !isPremiumInitiatedReplyFranchise({
      senderUid,
      senderData,
      recipientData,
      existingQuota,
      nowMs,
    })
  ) {
    return {
      ok: false,
      code: "premium-required",
      message: "Premium required for this international conversation.",
    };
  }

  // Free internacional: somente texto.
  const type = String(messageType || "text").trim();
  if (type !== "text") {
    return {
      ok: false,
      code: "media-not-allowed",
      message: "Only text is allowed under the free reply allowance.",
    };
  }

  const points = countCodePoints(text);
  if (points <= 0) {
    return { ok: false, code: "empty-text", message: "Message text is required." };
  }
  if (points > MAX_TEXT_CODE_POINTS) {
    return {
      ok: false,
      code: "text-too-long",
      message: `Text exceeds ${MAX_TEXT_CODE_POINTS} characters.`,
    };
  }

  let quota = readReplyQuota(existingQuota);
  if (!quota || !quota.enabled || quota.freeUid !== senderUid) {
    const peerUid = String(recipientUid || "").trim();
    quota = {
      version: REPLY_QUOTA_VERSION,
      enabled: true,
      freeUid: senderUid,
      initiatorUid: isPremiumUser(recipientData, nowMs) ? peerUid : "",
      limit: REPLY_QUOTA_LIMIT,
      used: 0,
    };
  }

  const remaining = remainingQuota(quota);
  if (points > remaining) {
    return {
      ok: false,
      code: "quota-exceeded",
      message: "Free reply allowance exhausted for this conversation.",
      quota: {
        used: quota.used,
        limit: quota.limit,
        remaining,
      },
      consume: 0,
      wouldConsume: points,
    };
  }

  return {
    ok: true,
    mode: "quota",
    consume: points,
    quotaBefore: quota,
    quotaAfter: {
      ...quota,
      used: quota.used + points,
      limit: quota.limit,
      freeUid: senderUid,
      enabled: true,
      version: REPLY_QUOTA_VERSION,
    },
  };
}

function validateRequestId(requestId) {
  const id = String(requestId || "").trim();
  if (id.length < MIN_REQUEST_ID || id.length > MAX_REQUEST_ID) {
    return { ok: false, error: "bad_request_id" };
  }
  if (!/^[A-Za-z0-9._:-]+$/.test(id)) {
    return { ok: false, error: "bad_request_id" };
  }
  return { ok: true, requestId: id };
}

function firstPublicName(fullName, fallback = "esta pessoa") {
  const raw = String(fullName || "").trim();
  if (!raw) return fallback;
  const first = raw.split(/\s+/)[0];
  return first || fallback;
}

module.exports = {
  REPLY_QUOTA_LIMIT,
  REPLY_QUOTA_VERSION,
  MAX_TEXT_CODE_POINTS,
  IDEMPOTENCY_TTL_MS,
  countCodePoints,
  isPremiumUser,
  countryOf,
  isInternational,
  canSendViaClientWrite,
  isPremiumInitiatedReplyFranchise,
  requiresReplyQuotaCallable,
  readReplyQuota,
  remainingQuota,
  authorizeFreeTextSend,
  commitSerializedFreeTexts,
  validateRequestId,
  firstPublicName,
};
