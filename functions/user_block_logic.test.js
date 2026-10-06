const test = require("node:test");
const assert = require("node:assert/strict");
const {
  blockedUidSet,
  isEitherBlockedFromUserSnaps,
  MAX_BLOCKED_UIDS,
} = require("./user_block_logic");

test("absent or empty blocked allows send both ways", () => {
  assert.equal(
    isEitherBlockedFromUserSnaps({}, {}, "a", "b"),
    false,
  );
  assert.equal(
    isEitherBlockedFromUserSnaps({ blocked: [] }, { blocked: [] }, "a", "b"),
    false,
  );
  assert.equal(
    isEitherBlockedFromUserSnaps({ blocked: "nope" }, null, "a", "b"),
    false,
  );
});

test("A blocks B denies A→B and B→A without naming who", () => {
  const a = { blocked: ["b"] };
  const b = {};
  assert.equal(isEitherBlockedFromUserSnaps(a, b, "a", "b"), true);
  assert.equal(isEitherBlockedFromUserSnaps(b, a, "b", "a"), true);
});

test("B blocks A also denies both directions", () => {
  const a = {};
  const b = { blocked: ["a"] };
  assert.equal(isEitherBlockedFromUserSnaps(a, b, "a", "b"), true);
  assert.equal(isEitherBlockedFromUserSnaps(b, a, "b", "a"), true);
});

test("unrelated blocked uid does not deny the pair", () => {
  assert.equal(
    isEitherBlockedFromUserSnaps({ blocked: ["z"] }, { blocked: ["y"] }, "a", "b"),
    false,
  );
});

test("normalizes non-string entries and caps set size", () => {
  const set = blockedUidSet(["  x ", "", 1, null, "x"]);
  assert.equal(set.has("x"), true);
  assert.equal(set.has("1"), true);
  const huge = [];
  for (let i = 0; i < MAX_BLOCKED_UIDS + 40; i += 1) huge.push(`u${i}`);
  assert.equal(blockedUidSet(huge).size, MAX_BLOCKED_UIDS);
});

test("sendDmMessage core uses canonical array, not blocked subcollection", () => {
  const fs = require("fs");
  const src = fs.readFileSync(require.resolve("./send_dm_message_core.js"), "utf8");
  assert.equal(src.includes('.collection("blocked")'), false);
  assert.equal(src.includes("isEitherBlockedFromUserSnaps"), true);
  assert.equal(src.includes("Not allowed."), true);
});

test("does not treat subcollection-shaped maps as a block list", () => {
  assert.equal(
    isEitherBlockedFromUserSnaps({ blocked: { b: true } }, {}, "a", "b"),
    false,
  );
});
