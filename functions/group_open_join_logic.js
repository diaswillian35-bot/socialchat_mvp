"use strict";

function normalizeJoinPolicy(raw) {
  const value = (raw || "open").toString().trim().toLowerCase();
  if (value === "approval" || value === "adminapproval") return "approval";
  if (
    value === "inviteonly" ||
    value === "invite_only" ||
    value === "invite-only"
  ) {
    return "inviteOnly";
  }
  return "open";
}

function timestampMillis(raw) {
  if (!raw) return null;
  if (typeof raw.toMillis === "function") return raw.toMillis();
  if (typeof raw.toDate === "function") return raw.toDate().getTime();
  if (raw instanceof Date) return raw.getTime();
  if (typeof raw === "number" || typeof raw === "string") {
    const millis = new Date(raw).getTime();
    return Number.isFinite(millis) ? millis : null;
  }
  return null;
}

/**
 * Premium estrito para entrada internacional.
 * isMaster é permanente. Se premiumUntil existe, ele é a autoridade:
 * null/expirado bloqueia mesmo que isPremium tenha ficado true por legado.
 */
function isPremiumActive(userData, nowMillis = Date.now()) {
  if (userData?.isMaster === true) return true;
  const hasUntil = Object.prototype.hasOwnProperty.call(
    userData || {},
    "premiumUntil",
  );
  if (hasUntil) {
    const millis = timestampMillis(userData.premiumUntil);
    return millis !== null && millis > nowMillis;
  }
  return userData?.isPremium === true;
}

function normalizedCountry(data) {
  return (data?.homeCountryCode || data?.countryCode || "")
    .toString()
    .trim()
    .toLowerCase();
}

function isInternational(groupData, userData) {
  if (groupData?.isPremiumGroup === true) return true;
  const groupCountry = normalizedCountry(groupData);
  const userCountry = normalizedCountry(userData);
  return Boolean(groupCountry && userCountry && groupCountry !== userCountry);
}

function validateOpenJoin({
  groupExists,
  groupData,
  userExists,
  userData,
  banExists,
  banData,
  uid,
  nowMillis = Date.now(),
}) {
  if (!userExists || !uid) {
    return { error: "failed-precondition", reason: "user-unavailable" };
  }
  if (
    userData?.isBanned === true ||
    userData?.accountDeleted === true ||
    userData?.isActive === false
  ) {
    return { error: "permission-denied", reason: "account-blocked" };
  }
  if (!groupExists || groupData?.deleted === true) {
    return { error: "not-found", reason: "group-unavailable" };
  }
  if (groupData?.isActive === false) {
    return { error: "failed-precondition", reason: "group-inactive" };
  }
  if (normalizeJoinPolicy(groupData?.joinPolicy) !== "open") {
    return { error: "failed-precondition", reason: "group-not-open" };
  }

  // Fail-closed: doc de ban existente só libera com isActive:false explícito.
  if (banExists && banData?.isActive !== false) {
    return { error: "permission-denied", reason: "banned" };
  }

  if (
    isInternational(groupData, userData) &&
    !isPremiumActive(userData, nowMillis)
  ) {
    return { error: "permission-denied", reason: "premium-required" };
  }

  const originalMembers = Array.isArray(groupData?.members)
    ? groupData.members
    : [];
  if (originalMembers.some((member) => member === uid)) {
    return {
      alreadyMember: true,
      joined: false,
      members: originalMembers,
      membersCount: originalMembers.length,
    };
  }

  const maxMembers = Number.isInteger(groupData?.maxMembers)
    ? groupData.maxMembers
    : 0;
  if (maxMembers > 0 && originalMembers.length >= maxMembers) {
    return { error: "resource-exhausted", reason: "group-full" };
  }

  // Preserva valores e ordem byte-for-byte; apenas acrescenta uid ao final.
  const members = [...originalMembers, uid];
  return {
    alreadyMember: false,
    joined: true,
    members,
    membersCount: members.length,
  };
}

module.exports = {
  isPremiumActive,
  normalizeJoinPolicy,
  validateOpenJoin,
};
