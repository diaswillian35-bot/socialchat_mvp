/**
 * Helpers puros para interações de evento (likes/comments/triggers).
 * Usados por Cloud Functions e testes Node — sem Firebase Admin.
 */

const EVENT_COMMENT_MAX_LEN = 1000;
const EVENT_COMMENT_REPLY_PREVIEW_LEN = 280;

function eventOrganizerUid(data) {
  if (!data) return "";
  return (
    data.organizerId ||
    data.createdBy ||
    data.ownerId ||
    data.userId ||
    ""
  )
    .toString()
    .trim();
}

function eventAllowsComments(data) {
  if (!data) return false;
  if (data.deleted === true) return false;
  if (data.isActive !== true) return false;
  const status = (data.status || "").toString().trim().toLowerCase();
  if (status === "cancelled" || status === "canceled") return false;
  if (status !== "approved") return false;
  return true;
}

/** Curtidas: evento existente logicamente, aprovado, ativo, não cancelado. */
function eventAllowsLikes(data) {
  if (!data) return false;
  if (data.deleted === true) return false;
  if (data.isActive !== true) return false;
  const status = (data.status || "").toString().trim().toLowerCase();
  if (status === "cancelled" || status === "canceled") return false;
  if (status !== "approved") return false;
  return true;
}

function resolveRootCommentId(parent) {
  if (!parent) return "";
  const root = (parent.rootCommentId || "").toString().trim();
  if (root) return root;
  const replyTo = (parent.replyToCommentId || "").toString().trim();
  if (replyTo) return replyTo;
  return "";
}

function sanitizeCommentText(raw) {
  if (raw === undefined || raw === null) return { error: "invalid" };
  if (typeof raw !== "string") return { error: "invalid" };
  const text = raw.replace(/\u0000/g, "").trim();
  if (!text) return { error: "empty" };
  if (text.length > EVENT_COMMENT_MAX_LEN) return { error: "too_long" };
  return { text };
}

function isValidEventId(eventId) {
  const id = (eventId || "").toString().trim();
  if (!id || id.length < 6 || id.length > 128) return false;
  return /^[A-Za-z0-9_-]+$/.test(id);
}

function isValidClientId(id, { min = 8, max = 128 } = {}) {
  const v = (id || "").toString().trim();
  if (!v || v.length < min || v.length > max) return false;
  return /^[A-Za-z0-9_-]+$/.test(v);
}

function normalizeLikesCount(raw) {
  if (typeof raw === "number" && Number.isFinite(raw)) {
    return Math.max(0, Math.floor(raw));
  }
  return 0;
}

/**
 * Delta idempotente de contador a partir do estado do like doc.
 * Fonte de verdade do "liked": existência do doc likes/{uid}.
 * @deprecated Prefer applyDesiredLike (set semântico).
 */
function nextLikesCountAfterToggle({ currentCount, currentlyLiked }) {
  const base = normalizeLikesCount(currentCount);
  if (currentlyLiked) return Math.max(0, base - 1);
  return base + 1;
}

/** Valida desiredLiked: deve ser boolean explícito. */
function parseDesiredLiked(raw) {
  if (raw === undefined || raw === null) {
    return { error: "missing" };
  }
  if (typeof raw !== "boolean") {
    return { error: "invalid_type" };
  }
  return { desiredLiked: raw };
}

/**
 * setEventLike semântico: aplica desiredLiked sem inverter.
 * changed=false → sem write no contador/doc.
 */
function applyDesiredLike({ currentCount, currentlyLiked, desiredLiked }) {
  const base = normalizeLikesCount(currentCount);
  if (desiredLiked === true) {
    if (currentlyLiked) {
      return { liked: true, likesCount: base, changed: false };
    }
    return { liked: true, likesCount: base + 1, changed: true };
  }
  if (currentlyLiked) {
    return { liked: false, likesCount: Math.max(0, base - 1), changed: true };
  }
  return { liked: false, likesCount: base, changed: false };
}

/**
 * Simula sets concorrentes serializados (modelo de retry de transação).
 * Idempotência = estado likes/{uid} + desiredLiked (sem coleção de requests).
 * ops: [{ uid, desiredLiked }]
 */
function simulateConcurrentDesiredSets(initialCount, likedUids, ops) {
  let count = normalizeLikesCount(initialCount);
  const liked = new Set(likedUids);
  const results = [];
  for (const op of ops) {
    const uid = op.uid;
    const currentlyLiked = liked.has(uid);
    const next = applyDesiredLike({
      currentCount: count,
      currentlyLiked,
      desiredLiked: op.desiredLiked,
    });
    if (next.changed) {
      if (next.liked) liked.add(uid);
      else liked.delete(uid);
      count = next.likesCount;
    } else {
      count = next.likesCount;
    }
    results.push({
      uid,
      liked: next.liked,
      likesCount: count,
      changed: next.changed,
    });
  }
  return { likesCount: count, liked: [...liked].sort(), results };
}

/**
 * Simula N toggles concorrentes serializados (legado).
 */
function simulateConcurrentToggles(initialCount, likedUids, ops) {
  let count = normalizeLikesCount(initialCount);
  const liked = new Set(likedUids);
  const results = [];
  for (const uid of ops) {
    const currentlyLiked = liked.has(uid);
    if (currentlyLiked) {
      liked.delete(uid);
      count = nextLikesCountAfterToggle({
        currentCount: count,
        currentlyLiked: true,
      });
      results.push({ uid, liked: false, likesCount: count });
    } else {
      liked.add(uid);
      count = nextLikesCountAfterToggle({
        currentCount: count,
        currentlyLiked: false,
      });
      results.push({ uid, liked: true, likesCount: count });
    }
  }
  return { likesCount: count, liked: [...liked].sort(), results };
}

/**
 * true quando a única diferença relevante entre before/after é likesCount.
 * Evita side-effects de onEventUpdated (push de aprovação, fanout, etc.).
 */
function onlyLikesCountChanged(before, after) {
  if (!before || !after) return false;
  const keys = new Set([...Object.keys(before), ...Object.keys(after)]);
  for (const key of keys) {
    if (key === "likesCount") continue;
    const bv = before[key];
    const av = after[key];
    if (bv === av) continue;
    // Timestamps / objetos: comparação estável via JSON quando possível.
    try {
      if (JSON.stringify(bv) === JSON.stringify(av)) continue;
    } catch (_) {
      return false;
    }
    return false;
  }
  return true;
}

function shouldNotifyEventUpdate(before, after) {
  if (onlyLikesCountChanged(before, after)) return false;
  return true;
}

function buildReplyMetaFromParent({ replyToCommentId, parent }) {
  if (!replyToCommentId) {
    return {
      replyToCommentId: null,
      replyToUid: null,
      replyToName: null,
      replyToText: null,
      rootCommentId: null,
    };
  }
  if (!parent || parent.isDeleted === true) {
    return { error: parent?.isDeleted ? "parent_deleted" : "parent_missing" };
  }
  const replyToUid = (parent.uid || "").toString().trim() || null;
  const replyToName =
    (parent.name || parent.userName || "").toString().trim() || "User";
  const parentText = (parent.text || "").toString();
  const replyToText =
    parentText.length > EVENT_COMMENT_REPLY_PREVIEW_LEN
      ? parentText.slice(0, EVENT_COMMENT_REPLY_PREVIEW_LEN)
      : parentText;

  const resolvedRoot = resolveRootCommentId(parent);
  const rootCommentId = resolvedRoot || replyToCommentId;
  return {
    replyToCommentId: rootCommentId,
    replyToUid,
    replyToName,
    replyToText,
    rootCommentId,
  };
}

/** Push só quando created===true (retry/idempotência não notifica). */
function shouldSendCommentPush({ created, alreadyCreated }) {
  return created === true && alreadyCreated !== true;
}

function resolveCommentPushTargets({
  actorUid,
  isReply,
  replyToUid,
  organizerUid,
}) {
  const notifyUids = new Set();
  if (isReply && replyToUid && replyToUid !== actorUid) {
    notifyUids.add(replyToUid);
  } else if (!isReply && organizerUid && organizerUid !== actorUid) {
    notifyUids.add(organizerUid);
  }
  return [...notifyUids];
}

module.exports = {
  EVENT_COMMENT_MAX_LEN,
  EVENT_COMMENT_REPLY_PREVIEW_LEN,
  eventOrganizerUid,
  eventAllowsComments,
  eventAllowsLikes,
  resolveRootCommentId,
  sanitizeCommentText,
  isValidEventId,
  isValidClientId,
  normalizeLikesCount,
  nextLikesCountAfterToggle,
  parseDesiredLiked,
  applyDesiredLike,
  simulateConcurrentDesiredSets,
  simulateConcurrentToggles,
  onlyLikesCountChanged,
  shouldNotifyEventUpdate,
  buildReplyMetaFromParent,
  shouldSendCommentPush,
  resolveCommentPushTargets,
};
