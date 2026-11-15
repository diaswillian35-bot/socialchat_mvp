"use strict";

/**
 * Pure helpers for Admin "Novos usuários" screen authorization (testable).
 */
function canViewOpsNewUsersScreen(profile) {
  if (!profile || typeof profile !== "object") return false;
  if (profile.isActive === false) return false;
  return profile.isOwner === true;
}

module.exports = { canViewOpsNewUsersScreen };
