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
  const anonymous = !!(data && data.anonymous === true);
  return { ok: true, placeId, stars, comment, anonymous };
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

const ANONYMOUS_NAME = "Anônimo";

function safeHttpsUrl(value) {
  const text = String(value == null ? "" : value).trim().slice(0, 500);
  return /^https:\/\/[^\s"'<>]+$/.test(text) ? text : null;
}

/// Identidade pública do autor. Anônimo: sem nome real e sem foto.
function publicAuthor(user, token, anonymous) {
  if (anonymous) return { authorDisplayName: ANONYMOUS_NAME, authorPhotoUrl: null };
  const u = user || {};
  const t = token || {};
  const name = String(u.displayName || u.name || t.name || "Visitante").trim().split(/\s+/)[0].slice(0, 60) || "Visitante";
  const photo = safeHttpsUrl(u.photoUrl || u.avatarUrl || t.picture);
  return { authorDisplayName: name, authorPhotoUrl: photo };
}

/// Linha pública de uma avaliação (nunca expõe uid). Anônimo é mascarado
/// também na leitura, mesmo que algum dado antigo tenha nome/foto.
function publicReviewRow(row) {
  const anonymous = row.anonymous === true;
  return {
    publicId: String(row.publicId || "").slice(0, 120),
    authorDisplayName: anonymous ? ANONYMOUS_NAME : String(row.authorDisplayName || "Visitante").slice(0, 60),
    authorPhotoUrl: anonymous ? null : safeHttpsUrl(row.authorPhotoUrl),
    anonymous,
    stars: Number(row.stars) || 0,
    comment: String(row.comment || "").slice(0, 1500),
    status: row.status,
    ownerReply: row.ownerReply && typeof row.ownerReply === "object" ? {
      text: String(row.ownerReply.text || "").slice(0, 800),
      createdAtIso: String(row.ownerReply.createdAtIso || "").slice(0, 40),
    } : null,
    createdAtIso: String(row.createdAtIso || "").slice(0, 40),
    editedAtIso: row.editedAtIso ? String(row.editedAtIso).slice(0, 40) : null,
  };
}

/// Resumo agregado do local: média, total e contagem por estrela (1..5),
/// lido de place.rating.stars (mantido pela moderação).
function ratingSummaryOf(place) {
  const rating = place && place.rating && typeof place.rating === "object" ? place.rating : {};
  const raw = rating.stars && typeof rating.stars === "object" ? rating.stars : {};
  const ratingCounts = {};
  for (const key of ["1", "2", "3", "4", "5"]) ratingCounts[key] = Math.max(0, Math.floor(Number(raw[key]) || 0));
  return {
    average: Math.max(0, Math.min(5, Number(rating.average) || 0)),
    count: Math.max(0, Math.floor(Number(rating.count) || 0)),
    ratingCounts,
  };
}

/// Patch do dono/gestor: só a resposta. Nunca altera estrelas, texto,
/// autor ou status da avaliação.
function ownerReplyPatch(existingReply, text, nowIso) {
  return {
    ownerReply: {
      text,
      authorRole: "owner",
      createdAtIso: (existingReply && existingReply.createdAtIso) || nowIso,
      updatedAtIso: nowIso,
    },
  };
}

module.exports = {
  ANONYMOUS_NAME,
  publicAuthor,
  publicReviewRow,
  ratingSummaryOf,
  ownerReplyPatch,
  safeHttpsUrl,
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
