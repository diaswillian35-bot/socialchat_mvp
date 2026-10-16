"use strict";

const MAX_COMMENT = 1500;
const MAX_REPLY = 800;
const MAX_NOTE = 500;

function cleanText(value, max) {
  return String(value == null ? "" : value)
    .replace(/\u0000/g, "")
    .replace(/<[^>]*>/g, "")
    .trim()
    .slice(0, max);
}

function parseReviewInput(data) {
  const placeId = cleanText(data && data.placeId, 80);
  const stars = Number(data && data.stars);
  const comment = cleanText(data && data.comment, MAX_COMMENT);
  if (!/^[A-Za-z0-9_-]{3,80}$/.test(placeId)) return { ok: false, code: "place" };
  if (![1, 2, 3, 4, 5].includes(stars)) return { ok: false, code: "stars" };
  return { ok: true, placeId, stars, comment };
}

function parseReplyInput(data) {
  const placeId = cleanText(data && data.placeId, 80);
  const reviewId = cleanText(data && data.reviewId, 120);
  const text = cleanText(data && data.text, MAX_REPLY);
  if (!/^[A-Za-z0-9_-]{3,80}$/.test(placeId) || !reviewId) return { ok: false, code: "target" };
  if (!text) return { ok: false, code: "empty" };
  return { ok: true, placeId, reviewId, text };
}

function parseClaimInput(data) {
  const placeId = cleanText(data && data.placeId, 80);
  const role = data && data.role === "manager" ? "manager" : "owner";
  const phone = cleanText(data && data.phone, 40);
  const note = cleanText(data && data.note, MAX_NOTE);
  if (!/^[A-Za-z0-9_-]{3,80}$/.test(placeId)) return { ok: false, code: "place" };
  if (phone.length < 6) return { ok: false, code: "phone" };
  return { ok: true, placeId, role, phone, note };
}

function canReceiveReviews(place) {
  return !!place && place.active === true && place.deleted !== true && place.moderationStatus === "published";
}

function canManage(access, uid) {
  if (!access || !uid) return false;
  return access.ownerUid === uid || (Array.isArray(access.managerUids) && access.managerUids.includes(uid));
}

function claimId(placeId, uid) {
  return `clm_${placeId}_${uid}`.replace(/[^A-Za-z0-9_-]/g, "").slice(0, 120);
}

function ratingAfterPendingEdit(place, existing) {
  const counted = existing && (existing.status === "approved" || existing.status === "published");
  if (!counted) return null;
  const rating = place && place.rating && typeof place.rating === "object" ? place.rating : {};
  const count = Math.max(0, Number(rating.count || 0) - 1);
  const sum = Math.max(0, Number(place.ratingSum || 0) - Number(existing.stars || 0));
  const stars = { "1": 0, "2": 0, "3": 0, "4": 0, "5": 0, ...(rating.stars || {}) };
  const key = String(existing.stars);
  if (Object.prototype.hasOwnProperty.call(stars, key)) stars[key] = Math.max(0, Number(stars[key] || 0) - 1);
  return { rating: { ...rating, average: count ? Math.round((sum / count) * 10) / 10 : 0, count, stars }, ratingSum: sum };
}

module.exports = {
  MAX_COMMENT,
  MAX_REPLY,
  cleanText,
  parseReviewInput,
  parseReplyInput,
  parseClaimInput,
  canReceiveReviews,
  canManage,
  claimId,
  ratingAfterPendingEdit,
};
