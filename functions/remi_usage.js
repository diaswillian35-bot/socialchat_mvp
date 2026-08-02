/**
 * Remi — controle server-side de uso, validação, locks, idempotência e refund.
 * Coleção remiUsage/{uid} (+ requests/{requestId}): somente Admin SDK.
 *
 * Limites Free/Premium/Master: arquitetura preparada; valores atuais
 * NÃO devem ser alterados sem aprovação de produto (não publicar novos limites).
 */
const { HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

/**
 * Arquitetura de planos (preparada). Valores atuais = produção.
 * Futuro: trocar fonte (Remote Config) sem mudar o contrato resolveRemiPlan.
 */
const REMI_PLAN_LIMITS = Object.freeze({
  free: Object.freeze({ daily: 20, perMinute: 5 }),
  premium: Object.freeze({ daily: 100, perMinute: 5 }),
  master: Object.freeze({ daily: 200, perMinute: 5 }),
});

const REMI_LIMITS = {
  FREE_DAILY: REMI_PLAN_LIMITS.free.daily,
  PREMIUM_DAILY: REMI_PLAN_LIMITS.premium.daily,
  MASTER_DAILY: REMI_PLAN_LIMITS.master.daily,
  PER_MINUTE: REMI_PLAN_LIMITS.free.perMinute,
  MINUTE_WINDOW_MS: 60 * 1000,
  LOCK_TTL_MS: 2 * 60 * 1000,
  MAX_TEXT: 1500,
  MAX_HISTORY_ITEMS: 8,
  MAX_HISTORY_ITEM_TEXT: 1500,
  MAX_HISTORY_TOTAL: 6000,
  MAX_LANGUAGE: 80,
  MAX_GOAL: 120,
  MAX_LESSON: 120,
  /** requestId: UUID ou token estável do cliente */
  MIN_REQUEST_ID: 8,
  MAX_REQUEST_ID: 128,
  /** TTL planejado para docs de idempotência (limpeza futura via job). */
  IDEMPOTENCY_TTL_MS: 24 * 60 * 60 * 1000,
};

function maskUid(uid) {
  if (!uid || typeof uid !== "string") return "unknown";
  if (uid.length <= 8) return `${uid.slice(0, 2)}***`;
  return `${uid.slice(0, 4)}…${uid.slice(-4)}`;
}

function parsePremiumUntil(raw) {
  if (!raw) return null;
  if (raw.toDate && typeof raw.toDate === "function") {
    try {
      return raw.toDate();
    } catch (_) {
      return null;
    }
  }
  if (raw instanceof Date) return raw;
  if (typeof raw === "number") {
    const d = new Date(raw);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  return null;
}

function isAccountDisabledData(userData) {
  if (!userData) return false;
  if (
    Object.prototype.hasOwnProperty.call(userData, "isActive") &&
    userData.isActive === false
  ) {
    return true;
  }
  return (
    userData.isDisabled === true ||
    userData.disabled === true ||
    userData.deactivated === true
  );
}

function resolveRemiPlan(userData) {
  if (!userData) return "free";
  if (userData.isMaster === true) return "master";
  if (userData.isPremium === true) return "premium";
  const until = parsePremiumUntil(userData.premiumUntil);
  if (until && until.getTime() > Date.now()) return "premium";
  return "free";
}

function dailyLimitForPlan(plan) {
  const entry = REMI_PLAN_LIMITS[plan];
  if (entry) return entry.daily;
  return REMI_PLAN_LIMITS.free.daily;
}

function perMinuteLimitForPlan(plan) {
  const entry = REMI_PLAN_LIMITS[plan];
  if (entry) return entry.perMinute;
  return REMI_PLAN_LIMITS.free.perMinute;
}

function assertUserCanUseRemi(userData) {
  if (!userData) {
    throw new HttpsError("failed-precondition", "REMI_USER_NOT_FOUND");
  }
  if (userData.isBanned === true) {
    throw new HttpsError("permission-denied", "REMI_PERMISSION_DENIED");
  }
  if (userData.accountDeleted === true || userData.deleted === true) {
    throw new HttpsError("permission-denied", "REMI_PERMISSION_DENIED");
  }
  const status = (userData.status || "").toString().trim().toLowerCase();
  if (status === "deleted" || status === "banned") {
    throw new HttpsError("permission-denied", "REMI_PERMISSION_DENIED");
  }
  if (isAccountDisabledData(userData)) {
    throw new HttpsError("permission-denied", "REMI_PERMISSION_DENIED");
  }
}

function validateMessageText(raw) {
  if (raw != null && typeof raw !== "string") {
    throw new HttpsError("invalid-argument", "REMI_INVALID_MESSAGE");
  }
  const text = (raw ?? "").toString().trim();
  if (text.length < 1) {
    throw new HttpsError("invalid-argument", "REMI_INVALID_MESSAGE");
  }
  if (text.length > REMI_LIMITS.MAX_TEXT) {
    throw new HttpsError("invalid-argument", "REMI_MESSAGE_TOO_LONG");
  }
  return text;
}

function validateRequestId(raw) {
  if (raw == null || typeof raw !== "string") {
    throw new HttpsError("invalid-argument", "REMI_INVALID_REQUEST_ID");
  }
  const id = raw.trim();
  if (
    id.length < REMI_LIMITS.MIN_REQUEST_ID ||
    id.length > REMI_LIMITS.MAX_REQUEST_ID
  ) {
    throw new HttpsError("invalid-argument", "REMI_INVALID_REQUEST_ID");
  }
  if (!/^[A-Za-z0-9_-]+$/.test(id)) {
    throw new HttpsError("invalid-argument", "REMI_INVALID_REQUEST_ID");
  }
  return id;
}

function sanitizeMetaField(raw, maxLen, fallback) {
  const text = (raw ?? fallback ?? "").toString().trim();
  if (!text) return (fallback || "").toString().trim().slice(0, maxLen);
  if (text.length > maxLen) {
    return text.slice(0, maxLen);
  }
  return text;
}

function sanitizeLanguage(raw) {
  return sanitizeMetaField(raw, REMI_LIMITS.MAX_LANGUAGE, "English");
}

function sanitizeGoal(raw) {
  return sanitizeMetaField(raw, REMI_LIMITS.MAX_GOAL, "");
}

function sanitizeLesson(raw) {
  return sanitizeMetaField(raw, REMI_LIMITS.MAX_LESSON, "");
}

function sanitizeHistory(raw) {
  if (raw == null) return [];
  if (typeof raw === "string") {
    if (raw.trim() === "") return [];
    throw new HttpsError("invalid-argument", "REMI_INVALID_HISTORY");
  }
  if (!Array.isArray(raw)) {
    throw new HttpsError("invalid-argument", "REMI_INVALID_HISTORY");
  }
  if (raw.length > REMI_LIMITS.MAX_HISTORY_ITEMS) {
    throw new HttpsError("invalid-argument", "REMI_INVALID_HISTORY");
  }

  const items = [];
  let totalChars = 0;

  for (const item of raw) {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      throw new HttpsError("invalid-argument", "REMI_INVALID_HISTORY");
    }

    let role = (item.role || "").toString().trim().toLowerCase();
    if (role === "remi") role = "assistant";
    if (role !== "user" && role !== "assistant") {
      throw new HttpsError("invalid-argument", "REMI_INVALID_HISTORY");
    }

    const text = (item.text ?? "").toString().trim();
    if (!text) continue;

    if (text.length > REMI_LIMITS.MAX_HISTORY_ITEM_TEXT) {
      throw new HttpsError("invalid-argument", "REMI_MESSAGE_TOO_LONG");
    }

    totalChars += text.length;
    if (totalChars > REMI_LIMITS.MAX_HISTORY_TOTAL) {
      throw new HttpsError("invalid-argument", "REMI_INVALID_HISTORY");
    }

    items.push({ role, text });
  }

  if (items.length > REMI_LIMITS.MAX_HISTORY_ITEMS) {
    throw new HttpsError("invalid-argument", "REMI_INVALID_HISTORY");
  }

  return items;
}

function formatHistoryForPrompt(items) {
  return items
    .map((m) => {
      const label = m.role === "user" ? "User" : "Remi";
      return `${label}: ${m.text.replace(/\n/g, " ").trim()}`;
    })
    .join("\n");
}

/**
 * Monta bloco de memória sem repetir lastUserMessage/lastRemiReply
 * quando esses textos já estão no histórico enviado.
 */
function buildMemoryPromptText(memory, historyItems) {
  if (!memory || typeof memory !== "object") return "";

  const histTexts = new Set(
    (historyItems || []).map((h) => (h.text || "").toString().trim())
  );

  const lastUser = (memory.lastUserMessage || "").toString().trim();
  const lastReply = (memory.lastRemiReply || "").toString().trim();

  const lines = [
    "User memory:",
    `- Learning language: ${memory.learningLanguage || ""}`,
    `- Level: ${memory.level || ""}`,
    `- Total Remi messages: ${memory.totalMessages || 0}`,
    `- Conversation style: ${memory.conversationStyle || ""}`,
    `- Important facts: ${(memory.importantFacts || []).join(", ")}`,
  ];

  if (lastUser && !histTexts.has(lastUser)) {
    lines.push(`- Last user message: ${lastUser}`);
  }
  if (lastReply && !histTexts.has(lastReply)) {
    lines.push(`- Last Remi reply: ${lastReply}`);
  }

  return lines.join("\n");
}

function utcDateKey(now = new Date()) {
  return now.toISOString().slice(0, 10);
}

function readUsageCounters(data, nowMs) {
  const nowDate = utcDateKey(new Date(nowMs));

  let dailyDate = (data.dailyDate || "").toString();
  let dailyCount = Number(data.dailyCount) || 0;
  if (dailyDate !== nowDate) {
    dailyDate = nowDate;
    dailyCount = 0;
  }

  let minuteWindowStartMs = 0;
  if (data.minuteWindowStart && data.minuteWindowStart.toMillis) {
    minuteWindowStartMs = data.minuteWindowStart.toMillis();
  }
  let minuteCount = Number(data.minuteCount) || 0;
  if (
    !minuteWindowStartMs ||
    nowMs - minuteWindowStartMs > REMI_LIMITS.MINUTE_WINDOW_MS
  ) {
    minuteWindowStartMs = nowMs;
    minuteCount = 0;
  }

  return { dailyDate, dailyCount, minuteWindowStartMs, minuteCount };
}

function assertWithinLimits(plan, dailyCount, minuteCount) {
  const dailyLimit = dailyLimitForPlan(plan);
  const minuteLimit = perMinuteLimitForPlan(plan);
  if (dailyCount >= dailyLimit) {
    const code =
      plan === "free" ? "REMI_DAILY_LIMIT_FREE" : "REMI_DAILY_LIMIT_PREMIUM";
    throw new HttpsError("resource-exhausted", code);
  }
  if (minuteCount >= minuteLimit) {
    throw new HttpsError("resource-exhausted", "REMI_MINUTE_LIMIT");
  }
}

function isLockActive(data, nowMs) {
  if (data.requestInProgress !== true) return false;
  const expiresMs =
    data.requestLockExpiresAt && data.requestLockExpiresAt.toMillis
      ? data.requestLockExpiresAt.toMillis()
      : 0;
  if (!expiresMs || expiresMs <= nowMs) return false;
  return true;
}

function remiIdempotencyRef(db, uid, requestId) {
  return db
    .collection("remiUsage")
    .doc(uid)
    .collection("requests")
    .doc(requestId);
}

/**
 * Pure helper — decide se/refund e novos contadores (sem Firestore).
 * Protege saldo negativo e refund duplicado.
 */
function computeQuotaRefund(data, requestId, nowMs) {
  if (!requestId || data.lastQuotaRequestId !== requestId) {
    return { apply: false, reason: "not_owner" };
  }
  if (data.lastQuotaRefunded === true) {
    return { apply: false, reason: "already_refunded" };
  }

  const nowDate = utcDateKey(new Date(nowMs));
  let dailyDate = (data.dailyDate || "").toString();
  let dailyCount = Number(data.dailyCount) || 0;

  if (dailyDate === nowDate) {
    dailyCount = Math.max(0, dailyCount - 1);
  } else {
    dailyDate = nowDate;
    dailyCount = Number.isFinite(dailyCount) ? Math.max(0, dailyCount) : 0;
  }

  let minuteWindowStartMs = 0;
  if (data.minuteWindowStart && data.minuteWindowStart.toMillis) {
    minuteWindowStartMs = data.minuteWindowStart.toMillis();
  }
  let minuteCount = Number(data.minuteCount) || 0;
  if (
    minuteWindowStartMs &&
    nowMs - minuteWindowStartMs <= REMI_LIMITS.MINUTE_WINDOW_MS
  ) {
    minuteCount = Math.max(0, minuteCount - 1);
  } else {
    minuteWindowStartMs = nowMs;
    minuteCount = 0;
  }

  return {
    apply: true,
    reason: "refunded",
    dailyDate,
    dailyCount,
    minuteWindowStartMs,
    minuteCount,
  };
}

async function acquireRemiLock(db, uid, plan) {
  const ref = db.collection("remiUsage").doc(uid);
  const nowMs = Date.now();

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() || {} : {};

    if (isLockActive(data, nowMs)) {
      throw new HttpsError("failed-precondition", "REMI_REQUEST_IN_PROGRESS");
    }

    const counters = readUsageCounters(data, nowMs);
    assertWithinLimits(plan, counters.dailyCount, counters.minuteCount);

    tx.set(
      ref,
      {
        dailyDate: counters.dailyDate,
        dailyCount: counters.dailyCount,
        minuteWindowStart: admin.firestore.Timestamp.fromMillis(
          counters.minuteWindowStartMs
        ),
        minuteCount: counters.minuteCount,
        requestInProgress: true,
        requestLockExpiresAt: admin.firestore.Timestamp.fromMillis(
          nowMs + REMI_LIMITS.LOCK_TTL_MS
        ),
        lastRequestAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        planSnapshot: plan,
      },
      { merge: true }
    );

    return { plan, ...counters };
  });
}

/**
 * Reserva cota antes da chamada Gemini, vinculada ao requestId.
 */
async function consumeRemiQuota(db, uid, plan, requestId) {
  const ref = db.collection("remiUsage").doc(uid);
  const nowMs = Date.now();

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() || {} : {};
    const counters = readUsageCounters(data, nowMs);
    assertWithinLimits(plan, counters.dailyCount, counters.minuteCount);

    tx.set(
      ref,
      {
        dailyDate: counters.dailyDate,
        dailyCount: counters.dailyCount + 1,
        minuteWindowStart: admin.firestore.Timestamp.fromMillis(
          counters.minuteWindowStartMs
        ),
        minuteCount: counters.minuteCount + 1,
        lastQuotaRequestId: requestId,
        lastQuotaRefunded: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return {
      dailyCount: counters.dailyCount + 1,
      minuteCount: counters.minuteCount + 1,
    };
  });
}

/**
 * Refund atômico se Gemini/rede/Function falhou sem entregar resposta válida.
 */
async function refundRemiQuota(db, uid, requestId) {
  const ref = db.collection("remiUsage").doc(uid);
  const nowMs = Date.now();

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() || {} : {};
    const result = computeQuotaRefund(data, requestId, nowMs);

    if (!result.apply) {
      return { refunded: false, reason: result.reason };
    }

    tx.set(
      ref,
      {
        dailyDate: result.dailyDate,
        dailyCount: result.dailyCount,
        minuteWindowStart: admin.firestore.Timestamp.fromMillis(
          result.minuteWindowStartMs
        ),
        minuteCount: result.minuteCount,
        lastQuotaRefunded: true,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    return { refunded: true, reason: "refunded" };
  });
}

async function getIdempotentResult(db, uid, requestId) {
  const ref = remiIdempotencyRef(db, uid, requestId);
  const snap = await ref.get();
  if (!snap.exists) return null;
  const data = snap.data() || {};
  if (data.status === "done" && typeof data.reply === "string" && data.reply) {
    return { status: "done", reply: data.reply };
  }
  if (data.status === "pending") {
    const expiresMs =
      data.expiresAt && data.expiresAt.toMillis
        ? data.expiresAt.toMillis()
        : 0;
    if (expiresMs && expiresMs > Date.now()) {
      return { status: "pending" };
    }
  }
  if (data.status === "failed") {
    return { status: "failed" };
  }
  return null;
}

async function beginIdempotentRequest(db, uid, requestId) {
  const ref = remiIdempotencyRef(db, uid, requestId);
  const nowMs = Date.now();
  const expiresAt = admin.firestore.Timestamp.fromMillis(
    nowMs + REMI_LIMITS.IDEMPOTENCY_TTL_MS
  );

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) {
      const data = snap.data() || {};
      if (
        data.status === "done" &&
        typeof data.reply === "string" &&
        data.reply
      ) {
        return { hit: true, reply: data.reply };
      }
      if (data.status === "pending") {
        const exp =
          data.expiresAt && data.expiresAt.toMillis
            ? data.expiresAt.toMillis()
            : 0;
        if (exp && exp > nowMs && data.lockUntilMs && data.lockUntilMs > nowMs) {
          throw new HttpsError(
            "failed-precondition",
            "REMI_REQUEST_IN_PROGRESS"
          );
        }
      }
    }

    tx.set(
      ref,
      {
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt,
        lockUntilMs: nowMs + REMI_LIMITS.LOCK_TTL_MS,
      },
      { merge: true }
    );

    return { hit: false };
  });
}

async function completeIdempotentRequest(db, uid, requestId, reply) {
  const ref = remiIdempotencyRef(db, uid, requestId);
  const nowMs = Date.now();
  await ref.set(
    {
      status: "done",
      reply: (reply || "").toString(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(
        nowMs + REMI_LIMITS.IDEMPOTENCY_TTL_MS
      ),
      lockUntilMs: admin.firestore.FieldValue.delete(),
    },
    { merge: true }
  );
}

async function failIdempotentRequest(db, uid, requestId) {
  const ref = remiIdempotencyRef(db, uid, requestId);
  const nowMs = Date.now();
  try {
    await ref.set(
      {
        status: "failed",
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        expiresAt: admin.firestore.Timestamp.fromMillis(
          nowMs + REMI_LIMITS.IDEMPOTENCY_TTL_MS
        ),
        lockUntilMs: admin.firestore.FieldValue.delete(),
      },
      { merge: true }
    );
  } catch (e) {
    console.error(
      "remi_idempotency_fail_write",
      maskUid(uid),
      e.message || e
    );
  }
}

async function releaseRemiLock(db, uid) {
  const ref = db.collection("remiUsage").doc(uid);
  try {
    await ref.set(
      {
        requestInProgress: false,
        requestLockExpiresAt: admin.firestore.FieldValue.delete(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
  } catch (e) {
    console.error("remi_lock_release_failed", maskUid(uid), e.message || e);
  }
}

/**
 * App Check soft: só enforça se REMI_ENFORCE_APP_CHECK=true.
 * Manter desligado até validar tokens Android/iPhone.
 */
function assertAppCheckIfEnforced(request) {
  if (process.env.REMI_ENFORCE_APP_CHECK !== "true") return;
  if (!request.app) {
    throw new HttpsError("failed-precondition", "REMI_APP_CHECK_REQUIRED");
  }
}

/**
 * Log seguro: só duração, modelo, status, tokens aproximados, categoria.
 * Nunca mensagem, reply, nomes, e-mails, telefones, tokens ou segredos.
 */
function remiSafeLog(event, fields) {
  const safe = {
    event,
    uid: fields.uid ? maskUid(fields.uid) : undefined,
    durationMs: fields.durationMs,
    model: fields.model,
    status: fields.status,
    approxInputTokens: fields.approxInputTokens,
    approxOutputTokens: fields.approxOutputTokens,
    errorCategory: fields.errorCategory,
    plan: fields.plan,
    idempotentHit: fields.idempotentHit,
  };
  Object.keys(safe).forEach((k) => {
    if (safe[k] === undefined) delete safe[k];
  });
  if (fields.level === "error") {
    console.error(event, safe);
  } else {
    console.log(event, safe);
  }
}

module.exports = {
  REMI_LIMITS,
  REMI_PLAN_LIMITS,
  maskUid,
  parsePremiumUntil,
  isAccountDisabledData,
  resolveRemiPlan,
  dailyLimitForPlan,
  perMinuteLimitForPlan,
  assertUserCanUseRemi,
  validateMessageText,
  validateRequestId,
  sanitizeMetaField,
  sanitizeLanguage,
  sanitizeGoal,
  sanitizeLesson,
  sanitizeHistory,
  formatHistoryForPrompt,
  buildMemoryPromptText,
  acquireRemiLock,
  consumeRemiQuota,
  refundRemiQuota,
  computeQuotaRefund,
  getIdempotentResult,
  beginIdempotentRequest,
  completeIdempotentRequest,
  failIdempotentRequest,
  releaseRemiLock,
  assertAppCheckIfEnforced,
  remiSafeLog,
  // test helpers
  readUsageCounters,
  assertWithinLimits,
  isLockActive,
};
