/**
 * Pure helpers for DM unread onPrivateMessageCreated / sendDmMessage.
 * Anonymized Free/BR ↔ Master/CA fixtures — no PII.
 */
"use strict";

/** @param {unknown} unreadMap @param {string} uid */
function unreadFromMap(unreadMap, uid) {
  if (!unreadMap || typeof unreadMap !== "object") return 0;
  const value = unreadMap[uid];
  if (typeof value === "number" && Number.isFinite(value)) {
    return value > 0 ? value : 0;
  }
  if (typeof value === "string") {
    const n = Number.parseInt(value, 10);
    return Number.isFinite(n) && n > 0 ? n : 0;
  }
  return 0;
}

/**
 * @param {string[]} participants
 * @param {string} senderId
 */
function resolveTargetUids(participants, senderId) {
  const parts = Array.isArray(participants) ? participants : [];
  const sender = String(senderId || "").trim();
  return parts
    .map((uid) => String(uid || "").trim())
    .filter((uid) => uid && uid !== sender);
}

/**
 * Apply +1 to each target on a plain unread map (RMW / tests).
 * Preserves other participant keys. Handles absent / legacy missing keys.
 * @param {Record<string, unknown>|null|undefined} before
 * @param {string[]} targetUids
 * @param {string} [senderUid] if set, sender key forced to 0
 */
function applyUnreadIncrements(before, targetUids, senderUid) {
  const next = {};
  if (before && typeof before === "object" && !Array.isArray(before)) {
    for (const [k, v] of Object.entries(before)) {
      if (typeof v === "number" && Number.isFinite(v)) next[k] = v;
      else if (typeof v === "string") {
        const n = Number.parseInt(v, 10);
        next[k] = Number.isFinite(n) ? n : 0;
      } else next[k] = 0;
    }
  }
  for (const uid of targetUids) {
    if (!uid) continue;
    next[uid] = unreadFromMap(next, uid) + 1;
  }
  if (senderUid) next[senderUid] = 0;
  return next;
}

/**
 * @param {Array<Record<string, unknown>>} unreadMaps
 * @param {string} uid
 */
function badgeFromUnreadMaps(unreadMaps, uid) {
  let total = 0;
  for (const m of unreadMaps || []) {
    if (unreadFromMap(m, uid) > 0) total += 1;
  }
  return total;
}

/**
 * Parse message.serverUnreadApplied — bool (compat) or { v, recipientUid }.
 * @param {Record<string, unknown>|null|undefined} msg
 * @returns {{ applied: boolean, recipientUid: string|null, legacyBoolean: boolean, version: number|null }}
 */
function parseServerUnreadApplied(msg) {
  const raw = msg?.serverUnreadApplied;
  if (raw === true) {
    return {
      applied: true,
      recipientUid: null,
      legacyBoolean: true,
      version: null,
    };
  }
  if (raw && typeof raw === "object" && !Array.isArray(raw)) {
    const recipientUid = String(raw.recipientUid || "").trim();
    const version =
      typeof raw.v === "number"
        ? raw.v
        : typeof raw.version === "number"
          ? raw.version
          : 1;
    if (recipientUid) {
      return {
        applied: true,
        recipientUid,
        legacyBoolean: false,
        version,
      };
    }
  }
  return {
    applied: false,
    recipientUid: null,
    legacyBoolean: false,
    version: null,
  };
}

/** @deprecated use parseServerUnreadApplied */
function messageAlreadyAppliedServerUnread(msg) {
  return parseServerUnreadApplied(msg).applied;
}

/**
 * Build serverUnreadApplied payload written on the message by sendDmMessage.
 * @param {string} recipientUid
 */
function buildServerUnreadApplied(recipientUid) {
  return {
    v: 1,
    recipientUid: String(recipientUid || "").trim(),
  };
}

/**
 * Whether trigger should skip increment (callable already applied for recipient).
 * @param {{ applied: boolean, recipientUid: string|null }} parsed
 * @param {string[]} targetUids
 */
function shouldSkipTriggerUnreadIncrement(parsed, targetUids) {
  if (!parsed?.applied) return false;
  if (!parsed.recipientUid) return true; // legacy bool
  return (targetUids || []).includes(parsed.recipientUid);
}

/**
 * Sanitize error code for logs (no PII / tokens).
 * @param {unknown} err
 */
function sanitizeUnreadErrorCode(err) {
  let raw = String(
    (err && typeof err === "object" && (err.code || err.message)) ||
      err ||
      "unread_failed",
  );
  raw = raw.replace(/token[=:]\S+/gi, "token=redacted");
  raw = raw.replace(/Bearer\s+\S+/gi, "Bearer_redacted");
  return raw.replace(/[^\w./:-]+/g, "_").slice(0, 120);
}

/**
 * One message → exactly one unread bump for the recipient.
 * Models: callable apply, trigger skip, trigger retry (processed).
 */
function simulateOncePerMessageUnread({
  before,
  recipientUid,
  senderUid,
  callableApplied,
  triggerRetry,
}) {
  let unread = { ...(before || {}) };
  let increments = 0;
  if (callableApplied) {
    unread = applyUnreadIncrements(unread, [recipientUid], senderUid);
    increments += 1;
  }
  if (!callableApplied && !triggerRetry) {
    unread = applyUnreadIncrements(unread, [recipientUid], senderUid);
    increments += 1;
  }
  // triggerRetry with processed marker: no second increment
  return { unread, increments };
}

/**
 * Nested unread writes for onPrivateMessageCreated.
 * set(merge) with a dotted key stores a literal field "unread.<uid>"
 * that the chat screen never clears. FieldPath("unread", uid) is the map.
 * literal deletes remove that leftover field in the same update.
 * The sender is forced to 0 and is not incremented.
 */
/** Exact and space-prefixed leftovers from set(merge) dotted keys. */
function literalUnreadFieldNames(uid) {
  const id = String(uid || "").trim();
  if (!id) return [];
  return [`unread.${id}`, `unread. ${id}`];
}

function buildDmLiteralDeleteSteps(uids) {
  const steps = [];
  const seen = new Set();
  for (const raw of uids || []) {
    const uid = String(raw || "").trim();
    if (!uid || seen.has(uid)) continue;
    seen.add(uid);
    for (const literalKey of literalUnreadFieldNames(uid)) {
      steps.push({ op: "deleteLiteral", literalKey });
    }
  }
  return steps;
}

function buildDmUnreadUpdatePairs({ senderId, targetUids }) {
  const sender = String(senderId || "").trim();
  const steps = [];
  const seen = new Set();
  if (sender) {
    steps.push({ op: "zero", uid: sender });
    steps.push(...buildDmLiteralDeleteSteps([sender]));
    seen.add(sender);
  }
  for (const raw of targetUids || []) {
    const uid = String(raw || "").trim();
    if (!uid || seen.has(uid)) continue;
    seen.add(uid);
    steps.push({ op: "increment", uid });
    steps.push(...buildDmLiteralDeleteSteps([uid]));
  }
  return steps;
}

/**
 * A later read of 0 means the recipient already opened the chat.
 * Never increment again after the transaction commits.
 * Push only for the invocation that applied this message.
 */
function confirmDmUnreadAfterCommit({ mode }) {
  const normalized = String(mode || "");
  return {
    incrementAgain: false,
    sendPush:
      normalized === "trigger_applied" || normalized === "callable_applied",
  };
}

/** Second delivery of the same message must not build another +1. */
function commitDmUnreadOnce({ senderId, targetUids, alreadyProcessed }) {
  if (alreadyProcessed) return null;
  const sender = String(senderId || "").trim();
  if (!sender) return null;
  const steps = buildDmUnreadUpdatePairs({ senderId: sender, targetUids });
  return steps.length ? steps : null;
}

/**
 * Nested map used when a conversation document is created.
 * Keys are uid strings inside `unread`, never a top-level "unread.<uid>".
 */
function initialNestedUnread(uids) {
  const unread = {};
  for (const raw of uids || []) {
    const uid = String(raw || "").trim();
    if (!uid) continue;
    unread[uid] = 0;
  }
  return unread;
}

/**
 * Append FieldPath operations. `fieldPath("unread", uid)` is the nested map.
 * `fieldPath("unread.<uid>")` deletes only the legacy literal field.
 */
function appendDmUnreadArgs(args, steps, adapters) {
  if (!steps || !adapters) return args;
  const { fieldPath, increment, deleteSentinel } = adapters;
  for (const step of steps) {
    if (step.op === "zero") {
      args.push(fieldPath("unread", step.uid), 0);
    } else if (step.op === "increment") {
      args.push(fieldPath("unread", step.uid), increment(1));
    } else if (step.op === "deleteLiteral") {
      args.push(fieldPath(step.literalKey), deleteSentinel());
    }
  }
  return args;
}

function firestoreDmUnreadAdapters(adminSdk) {
  return {
    fieldPath: (...parts) => new adminSdk.firestore.FieldPath(...parts),
    increment: (n) => adminSdk.firestore.FieldValue.increment(n),
    deleteSentinel: () => adminSdk.firestore.FieldValue.delete(),
  };
}

const FIXTURES = {
  willian: "willian_free_br_uid",
  istela: "istela_master_ca_uid",
  participants: ["istela_master_ca_uid", "willian_free_br_uid"],
};

module.exports = {
  unreadFromMap,
  resolveTargetUids,
  applyUnreadIncrements,
  badgeFromUnreadMaps,
  parseServerUnreadApplied,
  messageAlreadyAppliedServerUnread,
  buildServerUnreadApplied,
  shouldSkipTriggerUnreadIncrement,
  sanitizeUnreadErrorCode,
  simulateOncePerMessageUnread,
  literalUnreadFieldNames,
  buildDmLiteralDeleteSteps,
  buildDmUnreadUpdatePairs,
  confirmDmUnreadAfterCommit,
  commitDmUnreadOnce,
  initialNestedUnread,
  appendDmUnreadArgs,
  firestoreDmUnreadAdapters,
  FIXTURES,
};
