"use strict";

const entries = {
  confirmAdultAge: ["essential", "Required to complete age verification."],
  deleteMyAccount: ["essential", "Account deletion must remain available."],
  revokeShareExtensionSessions: ["essential", "Logout/security token revocation."],
  syncRevenueCatEntitlement: ["essential", "Preserves purchases; does not expose social content."],
  revenueCatWebhook: ["service", "Secret-authenticated purchase webhook."],
  reconcilePresenceCountersNow: ["admin", "Explicit portal/platform admin maintenance."],
  approveEventPendingChanges: ["admin", "Portal event moderation."],
  rejectEventPendingChanges: ["admin", "Portal event moderation."],
  purgeExpiredShareExtensionData: ["maintenance", "Scheduled security cleanup."],
  onPresenceConnectionWritten: ["maintenance", "Automatic presence aggregation/cleanup."],
  reconcilePresenceCounters: ["maintenance", "Scheduled presence reconciliation."],
  onGroupMessageCreated: ["trigger", "Automatic unread/push; recipients are age-filtered."],
  onPrivateMessageCreated: ["trigger", "Automatic unread/push; recipients are age-filtered."],
  onGroupJoinRequestCreated: ["trigger", "Automatic push; recipients are age-filtered."],
  onEventUpdated: ["trigger", "Automatic moderation/push; recipients are age-filtered."],
};

for (const name of [
  "forwardMessage", "sendDmMessage", "issueShareExtensionSession",
  "listShareDestinations", "sendShareMessage", "claimInvitePremiumReward",
  "applyInviteCode", "searchUsers", "fetchLinkPreview", "askRemi",
  "joinOpenGroup", "joinGroupByInviteCode", "banGroupMember",
  "unbanGroupMember", "promoteGroupAdmin", "demoteGroupAdmin",
  "removeGroupMember", "transferGroupOwnership", "leaveGroup",
  "deleteGroup", "updateGroupSettings", "createGroup",
  "approveGroupJoinRequest", "rejectGroupJoinRequest", "markGroupAsRead",
  "joinEvent", "leaveEvent", "createEventComment",
  "exportEventParticipants", "toggleEventLike", "toggleEventCommentLike",
  "deleteEventComment", "createEvent", "abortIncompleteEvent",
  "updateEvent", "registerEventView", "cancelEvent", "archiveEvent",
  "restoreEvent", "duplicateEvent", "deleteEventPermanently",
]) {
  entries[name] = ["adult", "User-initiated social operation; verified adult required."];
}

module.exports = { entries };
