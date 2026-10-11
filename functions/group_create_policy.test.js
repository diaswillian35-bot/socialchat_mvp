const test = require("node:test");
const assert = require("node:assert/strict");
const {
  MAX_OWNED_GROUPS,
  evaluateGroupCreate,
  createGroupFailureLog,
} = require("./group_create_policy");

test("there is no one-group product cap", () => {
  assert.equal(MAX_OWNED_GROUPS, null);
});

test("the first group is created", () => {
  assert.deepEqual(
    evaluateGroupCreate({
      ownedCount: 0,
      maxOwnedGroups: null,
      existingRequest: null,
    }),
    { action: "create" },
  );
});

test("a second and later group are created for the same owner", () => {
  for (const ownedCount of [1, 2, 3, 8]) {
    assert.equal(
      evaluateGroupCreate({
        ownedCount,
        maxOwnedGroups: null,
        existingRequest: null,
      }).action,
      "create",
    );
  }
});

test("the same request reuses the first group and does not create another", () => {
  assert.deepEqual(
    evaluateGroupCreate({
      ownedCount: 1,
      maxOwnedGroups: null,
      existingRequest: { groupId: "group-1", inviteCode: "AB234K" },
    }),
    { action: "reuse", groupId: "group-1", inviteCode: "AB234K" },
  );
});

test("failure logs name the stage and code without personal data", () => {
  const row = createGroupFailureLog("places", "invalid-argument");
  assert.deepEqual(row, {
    tag: "create_group_failed",
    stage: "places",
    code: "invalid-argument",
  });
  assert.equal(Object.hasOwn(row, "uid"), false);
  assert.equal(Object.hasOwn(row, "name"), false);
});

test("an explicit cap can deny, and the default cap does not", () => {
  assert.equal(
    evaluateGroupCreate({
      ownedCount: 1,
      maxOwnedGroups: 1,
      existingRequest: null,
    }).action,
    "deny",
  );
  assert.equal(
    evaluateGroupCreate({
      ownedCount: 1,
      existingRequest: null,
    }).action,
    "create",
  );
});
