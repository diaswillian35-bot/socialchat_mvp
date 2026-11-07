"use strict";
// No platform-admin bypass. Roles are resolved exclusively from the group.
const uidList = (value) => Array.isArray(value)
  ? [...new Set(value.map((v) => String(v || "").trim()).filter(Boolean))] : [];
function roleOf(group, uid) {
  if (!uid) return "outsider";
  if (String(group.ownerId || "").trim() === uid) return "owner";
  if (uidList(group.admins).includes(uid)) return "admin";
  if (uidList(group.moderators).includes(uid) || uidList(group.mods).includes(uid)) return "moderator";
  return uidList(group.members).includes(uid) ? "member" : "outsider";
}
function permissionError(group, actorUid, targetUid, action) {
  const actor = roleOf(group, actorUid), target = roleOf(group, targetUid);
  if (!["promote", "demote", "remove", "ban"].includes(action)) return "group_role_not_allowed";
  if (target === "owner") return "group_owner_protected";
  if (actorUid === targetUid) return "group_role_not_allowed";
  if (actor === "owner") return null;
  if (target === "admin") return "group_admin_protected";
  if (action === "promote" || action === "demote") return "group_only_owner_roles";
  if (actor === "admin") return null;
  if (actor === "moderator" && target === "member") return null;
  return "group_role_not_allowed";
}
function accountDeletionGroupPatch(group, uid) {
  // Account deletion must remain possible; close owned groups, never transfer
  // ownership or remove the owner. Non-owners leave only their own membership.
  if (roleOf(group, uid) === "owner") return {
    deleted: true, isActive: false, deletedBy: uid,
    deletedReason: "owner_account_deleted",
  };
  const members = uidList(group.members).filter((v) => v !== uid);
  return { members, membersCount: members.length,
    admins: uidList(group.admins).filter((v) => v !== uid),
    moderators: uidList(group.moderators).filter((v) => v !== uid),
    mods: uidList(group.mods).filter((v) => v !== uid) };
}
module.exports = { uidList, roleOf, permissionError, accountDeletionGroupPatch };
