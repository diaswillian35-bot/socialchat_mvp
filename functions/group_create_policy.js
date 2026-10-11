"use strict";

/**
 * Product cap. null means an owner may create any number of groups.
 * Set a positive integer only when a product limit is explicitly decided.
 */
const MAX_OWNED_GROUPS = null;

function evaluateGroupCreate({
  ownedCount,
  maxOwnedGroups,
  existingRequest,
}) {
  const previous = existingRequest && typeof existingRequest === "object"
    ? existingRequest
    : null;
  const previousGroupId = previous ? String(previous.groupId || "").trim() : "";
  if (previousGroupId) {
    return {
      action: "reuse",
      groupId: previousGroupId,
      inviteCode: String(previous.inviteCode || ""),
    };
  }
  const cap = maxOwnedGroups === undefined ? MAX_OWNED_GROUPS : maxOwnedGroups;
  const owned = Number.isFinite(ownedCount) ? ownedCount : 0;
  if (typeof cap === "number" && cap >= 0 && owned >= cap) {
    return { action: "deny", code: "owner_limit" };
  }
  return { action: "create" };
}

function createGroupFailureLog(stage, code) {
  return {
    tag: "create_group_failed",
    stage: String(stage || "unknown"),
    code: String(code || "internal"),
  };
}

module.exports = {
  MAX_OWNED_GROUPS,
  evaluateGroupCreate,
  createGroupFailureLog,
};
