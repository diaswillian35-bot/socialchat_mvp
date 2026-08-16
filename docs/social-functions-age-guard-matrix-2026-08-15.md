# Social Functions age-guard matrix — 2026-08-15

Generated from `functions/social_function_policy.js`. The static audit fails if an exported Function is missing.

## adult

- `abortIncompleteEvent` — User-initiated social operation; verified adult required.
- `applyInviteCode` — User-initiated social operation; verified adult required.
- `approveGroupJoinRequest` — User-initiated social operation; verified adult required.
- `archiveEvent` — User-initiated social operation; verified adult required.
- `askRemi` — User-initiated social operation; verified adult required.
- `banGroupMember` — User-initiated social operation; verified adult required.
- `cancelEvent` — User-initiated social operation; verified adult required.
- `claimInvitePremiumReward` — User-initiated social operation; verified adult required.
- `createEvent` — User-initiated social operation; verified adult required.
- `createEventComment` — User-initiated social operation; verified adult required.
- `createGroup` — User-initiated social operation; verified adult required.
- `deleteEventComment` — User-initiated social operation; verified adult required.
- `deleteEventPermanently` — User-initiated social operation; verified adult required.
- `deleteGroup` — User-initiated social operation; verified adult required.
- `demoteGroupAdmin` — User-initiated social operation; verified adult required.
- `duplicateEvent` — User-initiated social operation; verified adult required.
- `exportEventParticipants` — User-initiated social operation; verified adult required.
- `fetchLinkPreview` — User-initiated social operation; verified adult required.
- `forwardMessage` — User-initiated social operation; verified adult required.
- `issueShareExtensionSession` — User-initiated social operation; verified adult required.
- `joinEvent` — User-initiated social operation; verified adult required.
- `joinGroupByInviteCode` — User-initiated social operation; verified adult required.
- `joinOpenGroup` — User-initiated social operation; verified adult required.
- `leaveEvent` — User-initiated social operation; verified adult required.
- `leaveGroup` — User-initiated social operation; verified adult required.
- `listShareDestinations` — User-initiated social operation; verified adult required.
- `markGroupAsRead` — User-initiated social operation; verified adult required.
- `promoteGroupAdmin` — User-initiated social operation; verified adult required.
- `registerEventView` — User-initiated social operation; verified adult required.
- `rejectGroupJoinRequest` — User-initiated social operation; verified adult required.
- `removeGroupMember` — User-initiated social operation; verified adult required.
- `restoreEvent` — User-initiated social operation; verified adult required.
- `searchUsers` — User-initiated social operation; verified adult required.
- `sendDmMessage` — User-initiated social operation; verified adult required.
- `sendShareMessage` — User-initiated social operation; verified adult required.
- `toggleEventCommentLike` — User-initiated social operation; verified adult required.
- `toggleEventLike` — User-initiated social operation; verified adult required.
- `transferGroupOwnership` — User-initiated social operation; verified adult required.
- `unbanGroupMember` — User-initiated social operation; verified adult required.
- `updateEvent` — User-initiated social operation; verified adult required.
- `updateGroupSettings` — User-initiated social operation; verified adult required.

## essential

- `confirmAdultAge` — Required to complete age verification.
- `deleteMyAccount` — Account deletion must remain available.
- `revokeShareExtensionSessions` — Logout/security token revocation.
- `syncRevenueCatEntitlement` — Preserves purchases; does not expose social content.

## admin

- `approveEventPendingChanges` — Portal event moderation.
- `reconcilePresenceCountersNow` — Explicit portal/platform admin maintenance.
- `rejectEventPendingChanges` — Portal event moderation.

## service

- `revenueCatWebhook` — Secret-authenticated purchase webhook.

## maintenance

- `onPresenceConnectionWritten` — Automatic presence aggregation/cleanup.
- `purgeExpiredShareExtensionData` — Scheduled security cleanup.
- `reconcilePresenceCounters` — Scheduled presence reconciliation.

## trigger

- `onEventUpdated` — Automatic moderation/push; recipients are age-filtered.
- `onGroupJoinRequestCreated` — Automatic push; recipients are age-filtered.
- `onGroupMessageCreated` — Automatic unread/push; recipients are age-filtered.
- `onPrivateMessageCreated` — Automatic unread/push; recipients are age-filtered.


