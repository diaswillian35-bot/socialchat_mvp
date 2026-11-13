"use strict";
const test = require("node:test");
const assert = require("node:assert");
const L = require("./place_submission_logic");

const base = { name: "Bar do Zé", category: "bar", cityName: "Toronto",
  countryCode: "ca", latitude: 43.6, longitude: -79.3 };

test("criação válida nasce sem fotos e com cardápio por link", () => {
  const r = L.parsePlaceInput({ ...base, menuUrl: "https://x.com/m.pdf" },
    { creating: true });
  assert.equal(r.error, undefined);
  assert.equal(r.fields.countryCode, "CA");
  assert.deepEqual(r.fields.menu,
    { enabled: true, photoUrls: [], pdfUrl: "https://x.com/m.pdf" });
});

test("categoria, cidade e link inválidos", () => {
  assert.equal(L.parsePlaceInput({ ...base, category: "loja" },
    { creating: true }).error, "category");
  assert.equal(L.parsePlaceInput({ ...base, cityName: "" },
    { creating: true }).error, "city");
  assert.equal(L.parsePlaceInput({ ...base, menuUrl: "http://x" },
    { creating: true }).error, "menu_url");
});

test("fotos só do próprio caminho do Storage", () => {
  const ok = "https://firebasestorage.googleapis.com/v0/b/x/o/" +
    encodeURIComponent("places/p1/photos/a.jpg") + "?alt=media";
  const bad = "https://firebasestorage.googleapis.com/v0/b/x/o/" +
    encodeURIComponent("places/p2/photos/a.jpg");
  const r = L.parsePlaceInput({ photoUrls: [ok] }, { placeId: "p1" });
  assert.deepEqual(r.fields.photoUrls, [ok]);
  assert.equal(r.fields.coverUrl, ok);
  assert.equal(L.parsePlaceInput({ photoUrls: [bad] },
    { placeId: "p1" }).error, "photos");
});

test("só dono ou admin editam", () => {
  assert.equal(L.canEditPlace({ uid: "u", placeData: { ownerId: "u" } }), true);
  assert.equal(L.canEditPlace({ uid: "x", placeData: { ownerId: "u" } }), false);
  assert.equal(L.canEditPlace({ uid: "x", isSuperAdmin: true }), true);
  assert.equal(L.canEditPlace({ uid: "u", accessData: { ownerUid: "u" } }), true);
});

test("moderação", () => {
  assert.equal(L.moderationPatch("approve").moderationStatus, "published");
  assert.equal(L.moderationPatch("reject").active, false);
  assert.equal(L.moderationPatch("x"), null);
});

test("só delivery: coordenadas opcionais, cidade obrigatória", () => {
  const noGeo = { ...base, latitude: null, longitude: null };
  assert.equal(L.parsePlaceInput(noGeo, { creating: true }).error, "location");
  const r = L.parsePlaceInput(
    { ...noGeo, deliveryOnly: true, deliveryArea: "Downtown Toronto" },
    { creating: true });
  assert.equal(r.error, undefined);
  assert.equal(r.fields.deliveryOnly, true);
  assert.equal(r.fields.latitude, null);
  assert.equal(r.fields.deliveryArea, "Downtown Toronto");
  assert.equal(L.parsePlaceInput(
    { ...noGeo, deliveryOnly: true, cityName: "" },
    { creating: true }).error, "city");
  assert.equal(L.parsePlaceInput({ ...base, deliveryOnly: "sim" },
    { creating: true }).error, "delivery_only");
  const normal = L.parsePlaceInput({ ...base, deliveryArea: "x" },
    { creating: true });
  assert.equal(normal.fields.deliveryOnly, false);
  assert.equal(normal.fields.deliveryArea, "");
  const s = L.placeSummary("p1", { deliveryOnly: true, latitude: null });
  assert.equal(s.deliveryOnly, true);
  assert.equal(s.latitude, null);
});

// ---------- horário estruturado + fuso ----------
const BASE = {
  name: "John Burger", category: "restaurant", cityName: "Toronto",
  stateName: "Ontario", countryCode: "CA", deliveryOnly: true,
};
const JB_HOURS = {
  v: 1,
  days: { 4: [{ o: "15:00", c: "21:00" }], 5: [{ o: "15:00", c: "21:00" }],
    6: [{ o: "15:00", c: "21:00" }] },
};

test("app antigo (só hoursNote): compatível, sem hours, fuso derivado", () => {
  const r = L.parsePlaceInput({ ...BASE, hoursNote: "08:00-20:00" },
    { creating: false, placeId: "p1" });
  assert.equal(r.error, undefined);
  assert.equal(r.fields.hoursNote, "08:00-20:00");
  assert.equal("hours" in r.fields, false);
  assert.equal(r.fields.timeZone, "America/Toronto");
});

test("hours v1 válido é normalizado para 7 dias", () => {
  const r = L.parsePlaceInput({ ...BASE, hours: JB_HOURS, timeZone: "America/Toronto" },
    { creating: false, placeId: "p1" });
  assert.equal(r.error, undefined);
  assert.deepEqual(r.fields.hours.days["4"], [{ o: "15:00", c: "21:00" }]);
  assert.deepEqual(r.fields.hours.days["1"], []);
  assert.equal(Object.keys(r.fields.hours.days).length, 7);
  assert.equal(r.fields.timeZone, "America/Toronto");
  // passa da meia-noite é permitido
  assert.ok(L.parseHours({ v: 1, days: { 5: [{ o: "18:00", c: "02:00" }] } }));
});

test("hours inválido -> error hours", () => {
  const bad = [
    { v: 2, days: {} },
    { v: 1, days: { 8: [] } },
    { v: 1, days: { 1: [{ o: "10:00", c: "10:00" }] } },
    { v: 1, days: { 1: [{ o: "24:00", c: "10:00" }] } },
    { v: 1, days: { 1: [{ o: "9:00", c: "10:00" }] } },
    { v: 1, days: { 1: [{ o: "09:00", c: "10:00" }, { o: "11:00", c: "12:00" },
      { o: "13:00", c: "14:00" }] } },
    { v: 1, days: { 1: "09:00-10:00" } },
    "08:00-20:00",
  ];
  for (const hours of bad) {
    const r = L.parsePlaceInput({ ...BASE, hours }, { creating: false, placeId: "p1" });
    assert.equal(r.error, "hours", JSON.stringify(hours));
  }
});

test("timeZone: IANA válido aceito; inválido cai no derivado", () => {
  assert.equal(L.isValidTimeZone("Europe/Lisbon"), true);
  assert.equal(L.isValidTimeZone("Mars/Base"), false);
  assert.equal(L.isValidTimeZone("UTC+3"), false);
  const r = L.parsePlaceInput({ ...BASE, timeZone: "Mars/Base" },
    { creating: false, placeId: "p1" });
  assert.equal(r.fields.timeZone, "America/Toronto");
  assert.equal(L.deriveTimeZone("BR", "Amazonas"), "America/Manaus");
  assert.equal(L.deriveTimeZone("BR", "Paraná"), "America/Sao_Paulo");
  assert.equal(L.deriveTimeZone("PT", "Açores"), "Atlantic/Azores");
  assert.equal(L.deriveTimeZone("CA", "BC"), "America/Vancouver");
  assert.equal(L.deriveTimeZone("US", "NY"), "");
});

test("placeSummary devolve hours e timeZone", () => {
  const s = L.placeSummary("p1", { ...BASE, hours: JB_HOURS, timeZone: "America/Toronto" });
  assert.deepEqual(s.hours.days["5"], [{ o: "15:00", c: "21:00" }]);
  assert.equal(s.timeZone, "America/Toronto");
  const old = L.placeSummary("p2", { ...BASE, hoursNote: "x" });
  assert.equal(old.hours, null);
  assert.equal(old.timeZone, "America/Toronto");
});


test("deletePlaceDecision: dono ok, admin ok, estranho recusado, idempotente", () => {
  const owner = L.deletePlaceDecision({
    uid: "u1",
    placeData: { ownerId: "u1", deleted: false, active: true },
    exists: true,
  });
  assert.equal(owner.ok, true);
  assert.equal(owner.alreadyDeleted, false);
  assert.deepEqual(owner.patch, { deleted: true, active: false, deletedBy: "u1" });

  const viaAccess = L.deletePlaceDecision({
    uid: "u2",
    placeData: { ownerId: "other", active: true },
    accessData: { ownerUid: "u2" },
    exists: true,
  });
  assert.equal(viaAccess.ok, true);
  assert.equal(viaAccess.patch.deletedBy, "u2");

  const admin = L.deletePlaceDecision({
    uid: "admin",
    isSuperAdmin: true,
    placeData: { ownerId: "u1", active: true },
    exists: true,
  });
  assert.equal(admin.ok, true);
  assert.equal(admin.patch.deletedBy, "admin");

  const stranger = L.deletePlaceDecision({
    uid: "x",
    placeData: { ownerId: "u1" },
    exists: true,
  });
  assert.equal(stranger.error.code, "permission-denied");
  assert.equal(stranger.error.message, "Not the owner.");

  const missing = L.deletePlaceDecision({ uid: "u1", exists: false });
  assert.equal(missing.error.code, "not-found");
  assert.equal(missing.error.message, "Place not found.");

  const again = L.deletePlaceDecision({
    uid: "u1",
    placeData: { ownerId: "u1", deleted: true },
    exists: true,
  });
  assert.equal(again.ok, true);
  assert.equal(again.alreadyDeleted, true);
  assert.equal(again.patch, undefined);
});
