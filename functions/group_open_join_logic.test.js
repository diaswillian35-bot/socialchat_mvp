"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  isPremiumActive,
  validateOpenJoin,
} = require("./group_open_join_logic");

const owner = "owner";
const uid = "joiner";
const now = Date.parse("2026-07-26T12:00:00Z");

function valid(overrides = {}) {
  return validateOpenJoin({
    groupExists: overrides.groupExists ?? true,
    groupData: {
      members: [owner],
      membersCount: 1,
      joinPolicy: "open",
      countryCode: "br",
      isActive: true,
      deleted: false,
      ...overrides.groupData,
    },
    userExists: overrides.userExists ?? true,
    userData: {
      homeCountryCode: "br",
      isPremium: false,
      premiumUntil: null,
      ...overrides.userData,
    },
    banExists: overrides.banExists ?? false,
    banData: overrides.banData || {},
    uid: overrides.uid || uid,
    nowMillis: overrides.nowMillis || now,
  });
}

test("preserva membros e ordem exatamente; acrescenta uid uma vez", () => {
  const original = [owner, "", "legacy", 42];
  const result = valid({
    groupData: { members: original, membersCount: original.length },
  });
  assert.equal(result.joined, true);
  assert.deepEqual(result.members, [owner, "", "legacy", 42, uid]);
  assert.deepEqual(original, [owner, "", "legacy", 42]);
  assert.equal(result.membersCount, result.members.length);
  assert.equal(result.members.filter((value) => value === uid).length, 1);
});

test("já membro é idempotente e não altera lista/count", () => {
  const original = [owner, uid];
  const result = valid({
    groupData: { members: original, membersCount: 2 },
  });
  assert.equal(result.alreadyMember, true);
  assert.equal(result.joined, false);
  assert.strictEqual(result.members, original);
  assert.equal(result.membersCount, 2);
});

test("dois joins serializados produzem lista e count consistentes", () => {
  const first = valid();
  const second = validateOpenJoin({
    groupExists: true,
    groupData: {
      members: first.members,
      membersCount: first.membersCount,
      joinPolicy: "open",
      countryCode: "br",
      isActive: true,
      deleted: false,
    },
    userExists: true,
    userData: { homeCountryCode: "br" },
    banExists: false,
    banData: {},
    uid: "joiner2",
    nowMillis: now,
  });
  assert.deepEqual(second.members, [owner, uid, "joiner2"]);
  assert.equal(second.membersCount, 3);
});

test("rejeita grupo inexistente, apagado, inativo, fechado e cheio", () => {
  assert.equal(valid({ groupExists: false }).error, "not-found");
  assert.equal(valid({ groupData: { deleted: true } }).error, "not-found");
  assert.equal(
    valid({ groupData: { isActive: false } }).reason,
    "group-inactive",
  );
  assert.equal(
    valid({ groupData: { joinPolicy: "approval" } }).reason,
    "group-not-open",
  );
  assert.equal(valid({ groupData: { maxMembers: 1 } }).reason, "group-full");
});

test("ban check fail-closed", () => {
  assert.equal(valid({ banExists: true, banData: {} }).reason, "banned");
  assert.equal(
    valid({ banExists: true, banData: { isActive: null } }).reason,
    "banned",
  );
  assert.equal(
    valid({ banExists: true, banData: { isActive: true } }).reason,
    "banned",
  );
  assert.equal(
    valid({ banExists: true, banData: { isActive: false } }).joined,
    true,
  );
});

test("Free, premium null e premium expirado bloqueiam internacional", () => {
  const intl = { countryCode: "ca" };
  assert.equal(valid({ groupData: intl }).reason, "premium-required");
  assert.equal(
    valid({
      groupData: intl,
      userData: { isPremium: true, premiumUntil: null },
    }).reason,
    "premium-required",
  );
  assert.equal(
    valid({
      groupData: intl,
      userData: {
        isPremium: true,
        premiumUntil: new Date(now - 1000),
      },
    }).reason,
    "premium-required",
  );
});

test("premium futuro, master e Premium legado liberam internacional", () => {
  const intl = { countryCode: "ca" };
  assert.equal(
    valid({
      groupData: intl,
      userData: { premiumUntil: new Date(now + 1000) },
    }).joined,
    true,
  );
  assert.equal(
    valid({
      groupData: intl,
      userData: { isMaster: true, premiumUntil: null },
    }).joined,
    true,
  );
  assert.equal(
    validateOpenJoin({
      groupExists: true,
      groupData: {
        members: [owner],
        joinPolicy: "open",
        countryCode: "ca",
      },
      userExists: true,
      userData: { homeCountryCode: "br", isPremium: true },
      banExists: false,
      uid,
      nowMillis: now,
    }).joined,
    true,
  );
});

test("isPremiumActive é null-safe", () => {
  assert.equal(isPremiumActive({ premiumUntil: null }, now), false);
  assert.equal(isPremiumActive({ premiumUntil: "invalid" }, now), false);
});
