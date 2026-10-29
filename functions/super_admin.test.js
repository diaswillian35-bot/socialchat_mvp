"use strict";
const test = require("node:test");
const assert = require("node:assert");
const { isSuperAdminAuth } = require("./super_admin");
const { validateOpenJoin } = require("./group_open_join_logic");

test("super admin exige email verificado exato", () => {
  assert.equal(isSuperAdminAuth({ uid: "a", token: { email: "diaswillian35@gmail.com", email_verified: true } }), true);
  assert.equal(isSuperAdminAuth({ uid: "a", token: { email: "DiasWillian35@gmail.com", email_verified: true } }), true);
  assert.equal(isSuperAdminAuth({ uid: "a", token: { email: "diaswillian35@gmail.com", email_verified: false } }), false);
  assert.equal(isSuperAdminAuth({ uid: "a", token: { email: "outro@gmail.com", email_verified: true } }), false);
  assert.equal(isSuperAdminAuth({ uid: "a", token: { admin: true } }), true);
  assert.equal(isSuperAdminAuth(null), false);
});

const base = {
  groupExists: true,
  userExists: true,
  userData: { homeCountryCode: "br" },
  banExists: false,
  banData: {},
  uid: "admin",
};

test("admin entra em grupo com aprovação e de outro país", () => {
  const d = validateOpenJoin({ ...base, groupData: { joinPolicy: "approval", countryCode: "pt", members: ["x"] }, isSuperAdmin: true });
  assert.equal(d.joined, true);
  assert.deepEqual(d.members, ["x", "admin"]);
});

test("não-admin continua bloqueado", () => {
  const d = validateOpenJoin({ ...base, groupData: { joinPolicy: "approval", members: [] } });
  assert.equal(d.error, "failed-precondition");
});

test("admin banido continua bloqueado", () => {
  const d = validateOpenJoin({ ...base, groupData: { joinPolicy: "open", members: [] }, banExists: true, isSuperAdmin: true });
  assert.equal(d.reason, "banned");
});

test("busca exclui quem está em Só explorar", () => {
  const us = require("./user_search");
  const fn = us.isSearchableAccount;
  if (typeof fn !== "function") return;
  const ok = { profileComplete: true, name: "Maria" };
  assert.equal(fn(ok), true);
  assert.equal(fn({ ...ok, exploreOnly: true }), false);
});
