const test = require("node:test");
const assert = require("node:assert/strict");
const logic = require("./place_actions_logic");

test("review accepts one canonical place/user payload and sanitizes html", () => {
  assert.deepEqual(logic.parseReviewInput({ placeId: "plc_123", stars: 5, comment: "<b>Ótimo</b>\u0000" }), {
    ok: true, placeId: "plc_123", stars: 5, comment: "Ótimo",
  });
  assert.equal(logic.parseReviewInput({ placeId: "x", stars: 6 }).ok, false);
});

test("only owner or manager can reply", () => {
  assert.equal(logic.canManage({ ownerUid: "a", managerUids: ["b"] }, "a"), true);
  assert.equal(logic.canManage({ ownerUid: "a", managerUids: ["b"] }, "b"), true);
  assert.equal(logic.canManage({ ownerUid: "a", managerUids: ["b"] }, "c"), false);
});

test("claim id is stable per account and place", () => {
  assert.equal(logic.claimId("plc_123", "uid.1"), "clm_plc_123_uid1");
  assert.equal(logic.parseClaimInput({ placeId: "plc_123", phone: "123" }).ok, false);
});

test("only public active places receive reviews", () => {
  assert.equal(logic.canReceiveReviews({ active: true, deleted: false, moderationStatus: "published" }), true);
  assert.equal(logic.canReceiveReviews({ active: true, moderationStatus: "pending" }), false);
});

test("editing an approved review removes its old contribution while pending", () => {
  const result = logic.ratingAfterPendingEdit({ ratingSum: 9, rating: { average: 4.5, count: 2, stars: { "1": 0, "2": 0, "3": 0, "4": 1, "5": 1 } } }, { stars: 4, status: "approved" });
  assert.equal(result.ratingSum, 5);
  assert.equal(result.rating.count, 1);
  assert.equal(result.rating.average, 5);
  assert.equal(result.rating.stars["4"], 0);
  assert.equal(logic.ratingAfterPendingEdit({}, { stars: 4, status: "pending" }), null);
});
