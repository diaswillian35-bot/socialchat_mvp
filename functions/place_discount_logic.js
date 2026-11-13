"use strict";

const PERCENTS = Object.freeze([5, 7, 10, 15, 20]);
const COVERED_BY = Object.freeze(["place", "remdy", "shared"]);
const MAX_DAYS = 90;
const CODE_TTL_MS = 60 * 1000;
const CONDITION = "show_app";
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function isValidPercent(value) {
  return PERCENTS.includes(Number(value));
}

function isValidCoveredBy(value) {
  return COVERED_BY.includes(String(value || ""));
}

/** Interpreta validUntil (ISO, Date, Timestamp-like, epoch ms). */
function parseValidUntil(raw) {
  if (raw == null || raw === "") return null;
  if (raw instanceof Date && !Number.isNaN(raw.getTime())) return raw;
  if (typeof raw === "object" && typeof raw.toDate === "function") {
    const d = raw.toDate();
    return d instanceof Date && !Number.isNaN(d.getTime()) ? d : null;
  }
  if (typeof raw === "object" && typeof raw._seconds === "number") {
    return new Date(raw._seconds * 1000);
  }
  if (typeof raw === "number" && Number.isFinite(raw)) {
    const d = new Date(raw);
    return Number.isNaN(d.getTime()) ? null : d;
  }
  const s = String(raw).trim();
  if (!s) return null;
  const d = new Date(s);
  return Number.isNaN(d.getTime()) ? null : d;
}

/** Fim do dia UTC da data civil (YYYY-MM-DD ou ISO). */
function endOfUtcDay(date) {
  return new Date(Date.UTC(
    date.getUTCFullYear(),
    date.getUTCMonth(),
    date.getUTCDate(),
    23, 59, 59, 999,
  ));
}

function daysFromNow(end, now) {
  const ms = end.getTime() - now.getTime();
  return ms / (24 * 60 * 60 * 1000);
}

function publicDiscount(current, now) {
  if (!current || typeof current !== "object") return null;
  const percent = Number(current.percent);
  const validUntil = parseValidUntil(current.validUntil || current.validUntilIso);
  const enabled = current.enabled === true;
  if (!isValidPercent(percent) || !validUntil) return null;
  const active = enabled && validUntil.getTime() >= now.getTime();
  return {
    enabled,
    active,
    percent,
    validUntil,
    validUntilIso: validUntil.toISOString(),
    condition: CONDITION,
    source: current.source === "partnership" ? "partnership" : "owner",
    coveredBy: isValidCoveredBy(current.coveredBy) ? current.coveredBy : "place",
    promotionId: String(current.promotionId || ""),
  };
}

function samePromo(a, b) {
  if (!a || !b) return false;
  return Number(a.percent) === Number(b.percent) &&
    parseValidUntil(a.validUntil)?.getTime() === parseValidUntil(b.validUntil)?.getTime() &&
    String(a.source || "owner") === String(b.source || "owner") &&
    String(a.coveredBy || "place") === String(b.coveredBy || "place");
}

function setDiscountDecision({
  uid,
  isSuperAdmin,
  placeData,
  accessData,
  exists,
  percent,
  validUntilRaw,
  enabled,
  now,
  canEdit,
}) {
  if (!exists) {
    return { error: { code: "not-found", message: "Place not found." } };
  }
  const place = placeData || {};
  if (place.deleted === true) {
    return { error: { code: "not-found", message: "Place not found." } };
  }
  if (!canEdit({ uid, isSuperAdmin, placeData, accessData })) {
    return { error: { code: "permission-denied", message: "Not the owner." } };
  }
  const current = publicDiscount(place.discount, now) || place.discount || null;
  const wantEnabled = enabled !== false;

  let percentVal = percent == null || percent === "" ? (current && current.percent) : percent;
  if (!isValidPercent(percentVal)) {
    return { error: { code: "invalid-argument", message: "Discount percent is invalid." } };
  }
  percentVal = Number(percentVal);

  let until = parseValidUntil(validUntilRaw);
  if (!until && current) until = parseValidUntil(current.validUntil || current.validUntilIso);
  if (!until) {
    return { error: { code: "invalid-argument", message: "Discount end date is required." } };
  }
  until = endOfUtcDay(until);
  if (Number.isNaN(until.getTime())) {
    return { error: { code: "invalid-argument", message: "Discount end date is invalid." } };
  }
  if (wantEnabled) {
    if (until.getTime() < now.getTime()) {
      return { error: { code: "invalid-argument", message: "Discount end date is invalid." } };
    }
    if (daysFromNow(until, now) > MAX_DAYS + (1 / 24)) {
      return { error: { code: "invalid-argument", message: "Discount cannot last more than 90 days." } };
    }
  }

  const next = {
    enabled: wantEnabled,
    percent: percentVal,
    validUntil: until,
    source: "owner",
    coveredBy: "place",
    condition: CONDITION,
  };
  const keepId = current && current.promotionId && samePromo(
    { ...next, source: current.source, coveredBy: current.coveredBy },
    current,
  );
  // Troca de parceria → selo do dono é promoção nova.
  const promotionId = keepId && current.source === "owner" ? current.promotionId : null;
  return {
    ok: true,
    patch: next,
    promotionId,
    newPromotion: !promotionId,
  };
}

function setPartnershipDecision({
  uid,
  isSuperAdmin,
  placeData,
  accessData,
  exists,
  percent,
  validUntilRaw,
  enabled,
  coveredBy,
  now,
}) {
  if (!exists) {
    return { error: { code: "not-found", message: "Place not found." } };
  }
  const place = placeData || {};
  if (place.deleted === true) {
    return { error: { code: "not-found", message: "Place not found." } };
  }
  if (!isSuperAdmin) {
    return { error: { code: "permission-denied", message: "Not allowed." } };
  }
  if (!isValidCoveredBy(coveredBy)) {
    return { error: { code: "invalid-argument", message: "Discount coverage is invalid." } };
  }
  const current = publicDiscount(place.discount, now) || place.discount || null;
  const wantEnabled = enabled !== false;
  let percentVal = percent == null || percent === "" ? (current && current.percent) : percent;
  if (!isValidPercent(percentVal)) {
    return { error: { code: "invalid-argument", message: "Discount percent is invalid." } };
  }
  percentVal = Number(percentVal);
  let until = parseValidUntil(validUntilRaw);
  if (!until && current) until = parseValidUntil(current.validUntil || current.validUntilIso);
  if (!until) {
    return { error: { code: "invalid-argument", message: "Discount end date is required." } };
  }
  until = endOfUtcDay(until);
  if (wantEnabled) {
    if (until.getTime() < now.getTime()) {
      return { error: { code: "invalid-argument", message: "Discount end date is invalid." } };
    }
    if (daysFromNow(until, now) > MAX_DAYS + (1 / 24)) {
      return { error: { code: "invalid-argument", message: "Discount cannot last more than 90 days." } };
    }
  }
  const next = {
    enabled: wantEnabled,
    percent: percentVal,
    validUntil: until,
    source: "partnership",
    coveredBy,
    condition: CONDITION,
  };
  const keepId = current && current.promotionId && samePromo(next, current);
  return {
    ok: true,
    patch: next,
    promotionId: keepId ? current.promotionId : null,
    newPromotion: !keepId,
  };
}

function issueCodeDecision({
  uid,
  placeData,
  exists,
  now,
  existingOpen,
  alreadyRedeemed,
}) {
  if (!uid) {
    return { error: { code: "unauthenticated", message: "Login required." } };
  }
  if (!exists) {
    return { error: { code: "not-found", message: "Place not found." } };
  }
  const place = placeData || {};
  if (place.deleted === true) {
    return { error: { code: "not-found", message: "Place not found." } };
  }
  const discount = publicDiscount(place.discount, now);
  if (!discount || !discount.active || !discount.promotionId) {
    return { error: { code: "failed-precondition", message: "Discount is not active." } };
  }
  if (alreadyRedeemed) {
    return { error: { code: "failed-precondition", message: "Discount already used." } };
  }
  if (existingOpen && existingOpen.uid === uid &&
      existingOpen.promotionId === discount.promotionId &&
      existingOpen.usedAt == null &&
      parseValidUntil(existingOpen.expiresAt)?.getTime() > now.getTime()) {
    return {
      ok: true,
      reuse: true,
      code: existingOpen.code,
      expiresAt: parseValidUntil(existingOpen.expiresAt),
      promotionId: discount.promotionId,
      percent: discount.percent,
    };
  }
  const expiresAt = new Date(now.getTime() + CODE_TTL_MS);
  return {
    ok: true,
    reuse: false,
    expiresAt,
    promotionId: discount.promotionId,
    percent: discount.percent,
  };
}

function formatCode(percent, randomChars) {
  const p = String(Number(percent));
  return `REM-${p}-${String(randomChars).toUpperCase()}`;
}

function normalizeCode(raw) {
  if (raw == null) return "";
  let s = String(raw).trim().toUpperCase();
  // Aceita payload do QR: RMD1:{placeId}:{code}
  const m = s.match(/RMD1:[A-F0-9]+:(REM-\d{1,2}-[A-Z0-9]+)/);
  if (m) return m[1];
  s = s.replace(/\s+/g, "");
  return s;
}

function redeemDecision({
  uid,
  isSuperAdmin,
  placeData,
  accessData,
  exists,
  issuance,
  alreadyRedeemed,
  now,
  canEdit,
}) {
  if (!exists) {
    return { error: { code: "not-found", message: "Place not found." } };
  }
  const place = placeData || {};
  if (place.deleted === true) {
    return { error: { code: "not-found", message: "Place not found." } };
  }
  if (!canEdit({ uid, isSuperAdmin, placeData, accessData })) {
    return { error: { code: "permission-denied", message: "Not the owner." } };
  }
  if (!issuance) {
    return { error: { code: "not-found", message: "Discount code is invalid." } };
  }
  if (issuance.usedAt != null) {
    return { error: { code: "failed-precondition", message: "Discount already used." } };
  }
  const exp = parseValidUntil(issuance.expiresAt);
  if (!exp || exp.getTime() < now.getTime()) {
    return { error: { code: "failed-precondition", message: "Discount code expired." } };
  }
  if (alreadyRedeemed) {
    return { error: { code: "failed-precondition", message: "Discount already used." } };
  }
  const discount = publicDiscount(place.discount, now);
  if (!discount || issuance.promotionId !== discount.promotionId) {
    return { error: { code: "failed-precondition", message: "Discount is not active." } };
  }
  return {
    ok: true,
    uid: issuance.uid,
    promotionId: issuance.promotionId,
    percent: Number(issuance.percent || discount.percent),
    code: issuance.code,
  };
}

module.exports = {
  PERCENTS,
  COVERED_BY,
  MAX_DAYS,
  CODE_TTL_MS,
  CONDITION,
  CODE_ALPHABET,
  isValidPercent,
  isValidCoveredBy,
  parseValidUntil,
  endOfUtcDay,
  publicDiscount,
  setDiscountDecision,
  setPartnershipDecision,
  issueCodeDecision,
  redeemDecision,
  formatCode,
  normalizeCode,
};
