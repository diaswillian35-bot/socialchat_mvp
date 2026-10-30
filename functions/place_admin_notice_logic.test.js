"use strict";
const test = require("node:test");
const assert = require("node:assert");
const L = require("./place_admin_notice_logic");

test("avisa só quando entra em pending", () => {
  assert.equal(L.shouldNotify(null, { moderationStatus: "pending" }), true);
  assert.equal(L.shouldNotify({ moderationStatus: "rejected" }, { moderationStatus: "pending" }), true);
  assert.equal(L.shouldNotify({ moderationStatus: "pending" }, { moderationStatus: "pending" }), false);
  assert.equal(L.shouldNotify(null, { moderationStatus: "published" }), false);
  assert.equal(L.shouldNotify(null, { moderationStatus: "pending", deleted: true }), false);
  assert.equal(L.shouldNotify({ moderationStatus: "pending" }, null), false);
});

test("admins ativos com Locais", () => {
  const uids = L.adminUidsFrom([
    { id: "a", data: { isOwner: true } },
    { id: "b", data: { permissions: { places: true } } },
    { id: "c", data: { permissions: { events: true } } },
    { id: "d", data: { isOwner: true, isActive: false } },
    { id: "e", data: {} },
    { id: "a", data: { isOwner: true } },
  ]);
  assert.deepEqual(uids, ["a", "b"]);
});

test("texto nos 5 idiomas, sem dados privados", () => {
  for (const l of ["br", "pt", "en", "es", "fr"]) {
    const m = L.formatNotice(l, { name: "Bar X", cityName: "Toronto", countryCode: "ca", phone: "999" });
    assert.ok(m.title.length > 0);
    assert.ok(m.body.includes("Bar X") && m.body.includes("Toronto · CA"));
    assert.ok(!m.body.includes("999"));
  }
  assert.deepEqual(L.pushData("p1", { countryCode: "br" }),
    { type: "place_pending_admin", placeId: "p1", countryCode: "BR" });
});
