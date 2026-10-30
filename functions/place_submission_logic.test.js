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
