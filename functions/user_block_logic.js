/**
 * Canonical user-block list: users/{uid}.blocked (array).
 * Matches the Flutter BlockService / BlockVisibility writers.
 * Does not read users/{uid}/blocked/{id} (legacy unused subcollection).
 */
const MAX_BLOCKED_UIDS = 500;

function blockedUidSet(raw) {
  const out = new Set();
  if (!Array.isArray(raw)) return out;
  for (const item of raw) {
    const id = String(item == null ? "" : item).trim();
    if (!id) continue;
    out.add(id);
    if (out.size >= MAX_BLOCKED_UIDS) break;
  }
  return out;
}

/**
 * True if sender blocked recipient or recipient blocked sender.
 * Missing / empty / non-array blocked fields are treated as not blocked.
 */
function isEitherBlockedFromUserSnaps(
  senderData,
  recipientData,
  senderUid,
  recipientUid,
) {
  const from = String(senderUid || "").trim();
  const to = String(recipientUid || "").trim();
  if (!from || !to || from === to) return false;
  const senderBlocked = blockedUidSet(senderData && senderData.blocked);
  const recipientBlocked = blockedUidSet(recipientData && recipientData.blocked);
  return senderBlocked.has(to) || recipientBlocked.has(from);
}

module.exports = {
  MAX_BLOCKED_UIDS,
  blockedUidSet,
  isEitherBlockedFromUserSnaps,
};
