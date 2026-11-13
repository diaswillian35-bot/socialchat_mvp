"use strict";
// HttpsError com chave estável (i18nKey). A message original NÃO muda,
// para apps antigos que ainda comparam e.message continuarem a funcionar.
// O app novo traduz pela chave via AppTexts.

let HttpsError;
try {
  HttpsError = require("firebase-functions/v2/https").HttpsError;
} catch (_) {
  // Testes unitários deste módulo rodam sem node_modules.
  HttpsError = class HttpsError extends Error {
    constructor(code, message, details) {
      super(message);
      this.code = code;
      this.details = details;
    }
  };
}

const MESSAGE_TO_KEY = Object.freeze({
  "Authentication required.": "fn_error_auth_required",
  "Login required.": "fn_error_login_required",
  "Policy version is outdated.": "fn_error_policy_outdated",
  "Invalid date of birth.": "fn_error_invalid_dob",
  "Date of birth can only be corrected through support.": "fn_error_dob_support",
  "Remdy is only for adults.": "age_underage_blocked",
  "Account data cleaned but auth delete failed. Please retry.": "fn_error_account_auth_delete",
  "Could not delete account. Please retry.": "fn_error_account_delete",
  "Premium required for this international conversation.": "user_search_premium_required",
  "Premium required for international groups.": "group_premium_other_country",
  "Only text is allowed under the free reply allowance.": "fn_error_free_reply_text_only",
  "Message text is required.": "fn_error_message_required",
  "Free reply allowance exhausted for this conversation.": "fn_error_free_reply_exhausted",
  "Too many photos.": "fn_error_too_many_photos",
  "Rate limit exceeded.": "fn_error_rate_limit",
  "Too many search requests. Please wait a moment.": "fn_error_search_rate_limit",
  "Too many link preview requests.": "fn_error_link_preview_rate",
  "Message not found.": "fn_error_message_not_found",
  "Bio too long.": "group_create_bio_too_long",
  "Could not join group.": "fn_error_join_group",
  "Invalid invite code.": "group_invite_invalid",
  "Account is banned.": "fn_error_account_banned",
  "Account is disabled.": "fn_error_account_disabled",
  "Account is suspended.": "fn_error_account_suspended",
  "Group not found.": "fn_error_group_not_found",
  "Cannot join this group.": "group_cannot_join_banned",
  "Cannot ban the owner.": "fn_error_cannot_ban_owner",
  "Group owner limit reached.": "fn_error_group_owner_limit",
  "Could not create group.": "group_create_error",
  "Name is required.": "group_edit_name_required",
  "Name too long.": "group_create_name_too_long",
  "Not allowed.": "fn_error_not_allowed",
  "Event not found.": "fn_error_event_not_found",
  "Group unavailable.": "fn_error_group_unavailable",
  "Event unavailable.": "fn_error_event_unavailable",
  "User profile not found.": "fn_error_user_not_found",
  "User not found.": "fn_error_user_not_found",
  "Comment not found.": "fn_error_comment_not_found",
  "Comment is empty.": "event_comment_empty",
  "Comment is too long.": "event_comment_too_long",
  "Comment is no longer available.": "fn_error_comment_unavailable",
  "Objectionable content.": "fn_error_objectionable",
  "Temporarily silenced.": "chat_account_muted",
  "Group does not accept invite-only join.": "group_invite_wrong_policy",
  "Group does not accept join requests.": "group_join_requests_not_accepted",
  "Request is not pending.": "group_join_request_not_pending",
  "Could not allocate invite code.": "fn_error_invite_code",
  "Could not update group.": "group_edit_error",
  "Could not delete group.": "group_delete_error",
  "Could not leave group.": "fn_error_leave_group",
  "Could not create event.": "fn_error_create_event",
  "Could not update event.": "fn_error_update_event",
  "Could not create comment.": "fn_error_create_comment",
  "Event no longer accepts attendees.": "fn_error_event_no_attendees",
  "Adult age verification is required.": "fn_error_age_required",
  "Send failed.": "fn_error_send_failed",
  "Private messages blocked.": "fn_error_dm_blocked",
  "Not a group member.": "fn_error_not_group_member",
  "Not a member of this group.": "fn_error_not_group_member",
  "Banned from this group.": "fn_error_banned_from_group",
  "Banned from group.": "fn_error_banned_from_group",
  "Session expired.": "fn_error_session_expired",
  "Session revoked.": "fn_error_session_revoked",
  "Invalid session.": "fn_error_invalid_session",
  "Place not found.": "fn_error_place_not_found",
  "Invalid location.": "group_edit_invalid_location",
  "Invalid joinPolicy.": "group_edit_invalid_policy",
  "Place is not a city.": "group_create_city_invalid",
  "City/country mismatch.": "group_create_city_country",
  "Places lookup unavailable.": "group_create_places_unavailable",
  "Only owner can delete.": "fn_error_only_owner_delete",
  "Only owner can promote.": "fn_error_only_owner_promote",
  "Only owner can demote.": "fn_error_only_owner_demote",
  "Cannot demote the owner.": "fn_error_cannot_demote_owner",
  "Cannot remove the owner.": "fn_error_cannot_remove_owner",
  "Target is not a member.": "fn_error_target_not_member",
  "Could not ban member.": "group_ban_error",
  "Could not unban member.": "fn_error_unban",
  "Could not promote admin.": "fn_error_promote",
  "Could not demote admin.": "group_demote_error",
  "Could not remove member.": "fn_error_remove_member",
  "Could not approve request.": "group_join_approve_error",
  "Could not reject request.": "group_join_reject_error",
  "Cannot approve your own request.": "fn_error_cannot_approve_own",
  "Cannot reject your own request.": "fn_error_cannot_reject_own",
  "Not the owner.": "fn_error_not_owner",
  "Conversation not found.": "fn_error_conversation_not_found",
  "Not a participant.": "fn_error_not_participant",
  "Not a participant of this conversation.": "fn_error_not_participant",
  "Invite not found.": "group_invite_expired",
  "Invite code not found.": "group_invite_expired",
  "Cannot use own invite.": "fn_error_own_invite",
  "Only organizer can cancel.": "fn_error_only_organizer",
  "Only organizer can manage.": "fn_error_only_organizer_manage",
  "Cancelled event cannot be updated.": "fn_error_cancelled_event",
  "Cancelled event cannot be edited.": "fn_error_cancelled_event",
  "Event is cancelled.": "fn_error_event_cancelled",
  "Could not join event.": "fn_error_join_event",
  "Could not leave event.": "fn_error_leave_event",
  "Could not cancel event.": "fn_error_cancel_event",
  "Not allowed to delete this comment.": "fn_error_delete_comment_denied",
  "Not allowed to edit this event.": "fn_error_edit_event_denied",
  "App Check required.": "fn_error_app_check",
  "App Check required for share extension.": "fn_error_app_check",
  "Strong confirmation required.": "fn_error_strong_confirmation",
  "Discount percent is invalid.": "fn_error_discount_percent",
  "Discount end date is required.": "fn_error_discount_date_required",
  "Discount cannot last more than 90 days.": "fn_error_discount_date_max",
  "Discount end date is invalid.": "fn_error_discount_date_invalid",
  "Discount is not active.": "fn_error_discount_inactive",
  "Discount already used.": "fn_error_discount_used",
  "Discount code expired.": "fn_error_discount_expired",
  "Discount code is invalid.": "fn_error_discount_code_invalid",
  "Discount coverage is invalid.": "fn_error_discount_coverage",
  "Could not allocate discount code.": "fn_error_discount_allocate",
});

function looksMachineKey(message) {
  const s = String(message == null ? "" : message);
  if (!s || s.length > 80) return false;
  if (s.includes(" ")) return false;
  return /^[A-Za-z][A-Za-z0-9_.-]*$/.test(s);
}

function keyFromMessage(message) {
  const s = String(message == null ? "" : message).trim();
  if (!s) return null;
  if (MESSAGE_TO_KEY[s]) return MESSAGE_TO_KEY[s];
  if (looksMachineKey(s)) return null; // photo_required, REMI_*, room_full...
  const lower = s.toLowerCase();
  if (lower.startsWith("invalid ") || lower.startsWith("invalid")) return "fn_error_invalid_data";
  if (lower.endsWith(" required.") || lower.endsWith(" required")) return "fn_error_missing_data";
  if (lower.startsWith("could not ")) return "fn_error_generic";
  return "fn_error_generic";
}

function httpsError(code, message, details) {
  const key = typeof message === "string" ? keyFromMessage(message) : null;
  const base = details && typeof details === "object" && !Array.isArray(details)
    ? { ...details }
    : {};
  const i18nKey = base.i18nKey || base.localizationKey || key;
  if (i18nKey) base.i18nKey = i18nKey;
  const hasDetails = (details && typeof details === "object" && !Array.isArray(details)) || i18nKey;
  return hasDetails ? new HttpsError(code, message, base) : new HttpsError(code, message);
}

module.exports = {
  HttpsError,
  httpsError,
  keyFromMessage,
  MESSAGE_TO_KEY,
};
