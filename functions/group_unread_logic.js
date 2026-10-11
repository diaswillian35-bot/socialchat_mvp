"use strict";

function asCount(value) {
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
 * Nested `unread` plus leftover top-level fields named "unread.<uid>"
 * created by set(merge) with a dotted key.
 */
function readGroupUnreadState(groupData) {
  const data = groupData && typeof groupData === "object" ? groupData : {};
  const nested = {};
  const raw = data.unread;
  if (raw && typeof raw === "object" && !Array.isArray(raw)) {
    for (const [key, value] of Object.entries(raw)) {
      nested[key] = asCount(value);
    }
  }
  const literalKeys = [];
  for (const key of Object.keys(data)) {
    if (!key.startsWith("unread.")) continue;
    literalKeys.push(key);
    const uid = key.slice("unread.".length).trim();
    if (!uid) continue;
    if (Object.prototype.hasOwnProperty.call(nested, uid)) continue;
    nested[uid] = asCount(data[key]);
  }
  return { nested, literalKeys };
}

/**
 * One new message from someone else.
 * Already-processed deliveries return null so a function retry does not +1.
 * The sender is forced to 0 and is not incremented.
 * @returns {{unread: Record<string, number>, literalKeys: string[], targets: string[]}|null}
 */
function applyGroupMessageUnread({
  groupData,
  senderId,
  memberUids,
  bannedUids,
  alreadyProcessed,
}) {
  if (alreadyProcessed) return null;
  const sender = String(senderId || "").trim();
  if (!sender) return null;
  const { nested, literalKeys } = readGroupUnreadState(groupData);
  const banned = new Set((bannedUids || []).map((uid) => String(uid || "").trim()));
  const targets = [];
  nested[sender] = 0;
  for (const raw of memberUids || []) {
    const uid = String(raw || "").trim();
    if (!uid || uid === sender || banned.has(uid)) continue;
    nested[uid] = asCount(nested[uid]) + 1;
    targets.push(uid);
  }
  return { unread: nested, literalKeys, targets };
}

module.exports = {
  asCount,
  readGroupUnreadState,
  applyGroupMessageUnread,
};
