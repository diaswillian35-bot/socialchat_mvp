"use strict";

const { test } = require("node:test");
const assert = require("node:assert/strict");
const L = require("./place_discount_logic");

const canEdit = require("./place_submission_logic").canEditPlace;

const now = new Date("2026-11-13T18:00:00.000Z");
const until30 = "2026-12-12T23:59:59.000Z";
const owner = { uid: "owner1", isSuperAdmin: false };
const place = { ownerId: "owner1", discount: null };
const access = { ownerUid: "owner1" };

function setOwner(extra = {}) {
  return L.setDiscountDecision({
    uid: owner.uid,
    isSuperAdmin: false,
    placeData: { ...place, ...extra },
    accessData: access,
    exists: true,
    percent: 10,
    validUntilRaw: until30,
    enabled: true,
    now,
    canEdit,
  });
}

test("setPlaceDiscount: dono ok", () => {
  const d = setOwner();
  assert.equal(d.ok, true);
  assert.equal(d.patch.percent, 10);
  assert.equal(d.patch.enabled, true);
  assert.equal(d.patch.source, "owner");
  assert.equal(d.patch.coveredBy, "place");
  assert.equal(d.newPromotion, true);
});

test("setPlaceDiscount: admin ok, estranho recusado", () => {
  const admin = L.setDiscountDecision({
    uid: "admin1",
    isSuperAdmin: true,
    placeData: place,
    accessData: {},
    exists: true,
    percent: 15,
    validUntilRaw: until30,
    enabled: true,
    now,
    canEdit,
  });
  assert.equal(admin.ok, true);
  const no = L.setDiscountDecision({
    uid: "stranger",
    isSuperAdmin: false,
    placeData: place,
    accessData: {},
    exists: true,
    percent: 10,
    validUntilRaw: until30,
    enabled: true,
    now,
    canEdit,
  });
  assert.equal(no.error.code, "permission-denied");
  assert.equal(no.error.message, "Not the owner.");
});

test("setPlaceDiscount: percent inválido, data obrigatória, máx 90 dias", () => {
  const bad = L.setDiscountDecision({
    ...{ uid: "owner1", isSuperAdmin: false, placeData: place, accessData: access, exists: true, now, canEdit },
    percent: 12,
    validUntilRaw: until30,
    enabled: true,
  });
  assert.equal(bad.error.message, "Discount percent is invalid.");
  const noDate = L.setDiscountDecision({
    uid: "owner1", isSuperAdmin: false, placeData: place, accessData: access,
    exists: true, percent: 10, validUntilRaw: null, enabled: true, now, canEdit,
  });
  assert.equal(noDate.error.message, "Discount end date is required.");
  const tooLong = L.setDiscountDecision({
    uid: "owner1", isSuperAdmin: false, placeData: place, accessData: access,
    exists: true, percent: 10, validUntilRaw: "2027-03-01T00:00:00.000Z",
    enabled: true, now, canEdit,
  });
  assert.equal(tooLong.error.message, "Discount cannot last more than 90 days.");
});

test("setPlaceDiscount: ligar/desligar mantém promotionId se o restante é igual", () => {
  const first = setOwner();
  const current = {
    ...first.patch,
    promotionId: "abc123",
    validUntilIso: first.patch.validUntil.toISOString(),
  };
  const off = L.setDiscountDecision({
    uid: "owner1", isSuperAdmin: false,
    placeData: { ownerId: "owner1", discount: current },
    accessData: access, exists: true, percent: 10,
    validUntilRaw: until30, enabled: false, now, canEdit,
  });
  assert.equal(off.ok, true);
  assert.equal(off.patch.enabled, false);
  assert.equal(off.promotionId, "abc123");
});

test("setPartnership: só admin, coveredBy válido", () => {
  const denied = L.setPartnershipDecision({
    uid: "owner1", isSuperAdmin: false, placeData: place, accessData: access,
    exists: true, percent: 10, validUntilRaw: until30, enabled: true,
    coveredBy: "shared", now,
  });
  assert.equal(denied.error.message, "Not allowed.");
  const badCov = L.setPartnershipDecision({
    uid: "admin", isSuperAdmin: true, placeData: place, accessData: {},
    exists: true, percent: 10, validUntilRaw: until30, enabled: true,
    coveredBy: "other", now,
  });
  assert.equal(badCov.error.message, "Discount coverage is invalid.");
  const ok = L.setPartnershipDecision({
    uid: "admin", isSuperAdmin: true, placeData: place, accessData: {},
    exists: true, percent: 20, validUntilRaw: until30, enabled: true,
    coveredBy: "shared", now,
  });
  assert.equal(ok.ok, true);
  assert.equal(ok.patch.source, "partnership");
  assert.equal(ok.patch.coveredBy, "shared");
});

test("issueCode: dono logado, já usado, reutiliza código aberto, inativo", () => {
  const active = {
    ownerId: "owner1",
    discount: {
      enabled: true,
      percent: 10,
      validUntil: until30,
      promotionId: "promo1",
      source: "owner",
      coveredBy: "place",
    },
  };
  const needLogin = L.issueCodeDecision({
    uid: "", placeData: active, exists: true, now, existingOpen: null, alreadyRedeemed: false,
  });
  assert.equal(needLogin.error.message, "Login required.");
  const used = L.issueCodeDecision({
    uid: "u1", placeData: active, exists: true, now, existingOpen: null, alreadyRedeemed: true,
  });
  assert.equal(used.error.message, "Discount already used.");
  const expires = new Date(now.getTime() + 40000);
  const reuse = L.issueCodeDecision({
    uid: "u1", placeData: active, exists: true, now,
    existingOpen: { uid: "u1", promotionId: "promo1", usedAt: null, code: "REM-10-7K2Q", expiresAt: expires },
    alreadyRedeemed: false,
  });
  assert.equal(reuse.reuse, true);
  assert.equal(reuse.code, "REM-10-7K2Q");
  const fresh = L.issueCodeDecision({
    uid: "u1", placeData: active, exists: true, now, existingOpen: null, alreadyRedeemed: false,
  });
  assert.equal(fresh.ok, true);
  assert.equal(fresh.reuse, false);
  assert.equal(fresh.percent, 10);
  const off = L.issueCodeDecision({
    uid: "u1",
    placeData: { ...active, discount: { ...active.discount, enabled: false } },
    exists: true, now, existingOpen: null, alreadyRedeemed: false,
  });
  assert.equal(off.error.message, "Discount is not active.");
});

test("redeem: dono ok, estranho recusado, expirado, já usado, código inválido", () => {
  const placeData = {
    ownerId: "owner1",
    discount: {
      enabled: true, percent: 10, validUntil: until30, promotionId: "promo1",
    },
  };
  const issuance = {
    uid: "u1", promotionId: "promo1", percent: 10, code: "REM-10-7K2Q",
    usedAt: null, expiresAt: new Date(now.getTime() + 30000),
  };
  const ok = L.redeemDecision({
    uid: "owner1", isSuperAdmin: false, placeData, accessData: access,
    exists: true, issuance, alreadyRedeemed: false, now, canEdit,
  });
  assert.equal(ok.ok, true);
  assert.equal(ok.percent, 10);
  const admin = L.redeemDecision({
    uid: "admin", isSuperAdmin: true, placeData, accessData: {},
    exists: true, issuance, alreadyRedeemed: false, now, canEdit,
  });
  assert.equal(admin.ok, true);
  const stranger = L.redeemDecision({
    uid: "stranger", isSuperAdmin: false, placeData, accessData: {},
    exists: true, issuance, alreadyRedeemed: false, now, canEdit,
  });
  assert.equal(stranger.error.message, "Not the owner.");
  const expired = L.redeemDecision({
    uid: "owner1", isSuperAdmin: false, placeData, accessData: access,
    exists: true,
    issuance: { ...issuance, expiresAt: new Date(now.getTime() - 1000) },
    alreadyRedeemed: false, now, canEdit,
  });
  assert.equal(expired.error.message, "Discount code expired.");
  const used = L.redeemDecision({
    uid: "owner1", isSuperAdmin: false, placeData, accessData: access,
    exists: true, issuance: { ...issuance, usedAt: now }, alreadyRedeemed: false, now, canEdit,
  });
  assert.equal(used.error.message, "Discount already used.");
  const missing = L.redeemDecision({
    uid: "owner1", isSuperAdmin: false, placeData, accessData: access,
    exists: true, issuance: null, alreadyRedeemed: false, now, canEdit,
  });
  assert.equal(missing.error.message, "Discount code is invalid.");
});

test("format/normalize de código e QR", () => {
  assert.equal(L.formatCode(10, "7k2q"), "REM-10-7K2Q");
  assert.equal(L.normalizeCode(" rem-10-7k2q "), "REM-10-7K2Q");
  assert.equal(
    L.normalizeCode("RMD1:abcdef0123456789abcdef0123456789:REM-10-7K2Q"),
    "REM-10-7K2Q",
  );
});

test("httpsError mapeia as mensagens novas", () => {
  const { keyFromMessage } = require("./i18n/httpsError");
  assert.equal(keyFromMessage("Discount already used."), "fn_error_discount_used");
  assert.equal(keyFromMessage("Discount cannot last more than 90 days."), "fn_error_discount_date_max");
  assert.equal(keyFromMessage("Place not found."), "fn_error_place_not_found");
});
