const test = require("node:test");
const assert = require("node:assert/strict");
const logic = require("./place_actions_logic");

test("review accepts one canonical place/user payload and sanitizes html", () => {
  assert.deepEqual(logic.parseReviewInput({ placeId: "plc_123", stars: 5, comment: "<b>Ótimo</b>\u0000" }), {
    ok: true, placeId: "plc_123", stars: 5, comment: "Ótimo", anonymous: false,
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

test("place report accepts business reasons and is idempotent per account", () => {
  const parsed = logic.parsePlaceReportInput({
    placeId: "plc_123",
    reason: "incorrect_information",
    details: "O horário está incorreto",
  });
  assert.equal(parsed.ok, true);
  assert.equal(
    logic.placeReportId("plc_123", "uid.1"),
    logic.placeReportId("plc_123", "uid.1"),
  );
});

test("place report rejects social-comment reasons and requires other details", () => {
  assert.equal(logic.parsePlaceReportInput({
    placeId: "plc_123", reason: "harassment", details: "x",
  }).ok, false);
  assert.equal(logic.parsePlaceReportInput({
    placeId: "plc_123", reason: "other", details: "x",
  }).code, "details");
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

test("review accepts the anonymous option", () => {
  assert.equal(logic.parseReviewInput({ placeId: "plc_123", stars: 4, anonymous: true }).anonymous, true);
  assert.equal(logic.parseReviewInput({ placeId: "plc_123", stars: 4, anonymous: "yes" }).anonymous, false);
});

test("anonymous author hides name and photo on write and read", () => {
  const user = { displayName: "Maria Souza", photoUrl: "https://cdn.example/m.jpg" };
  assert.deepEqual(logic.publicAuthor(user, {}, true), { authorDisplayName: "Anônimo", authorPhotoUrl: null });
  assert.deepEqual(logic.publicAuthor(user, {}, false), { authorDisplayName: "Maria", authorPhotoUrl: "https://cdn.example/m.jpg" });
  assert.equal(logic.publicAuthor({ photoUrl: "javascript:alert(1)" }, {}, false).authorPhotoUrl, null);
  const row = logic.publicReviewRow({ anonymous: true, authorDisplayName: "Maria", authorPhotoUrl: "https://x/y.jpg", authorUid: "u1", stars: 5, status: "approved" });
  assert.equal(row.authorDisplayName, "Anônimo");
  assert.equal(row.authorPhotoUrl, null);
  assert.equal("authorUid" in row, false);
});

test("rating summary exposes per-star counts", () => {
  const s = logic.ratingSummaryOf({ rating: { average: 4.3, count: 3, stars: { "5": 2, "3": 1 } } });
  assert.deepEqual(s, { average: 4.3, count: 3, ratingCounts: { "1": 0, "2": 0, "3": 1, "4": 0, "5": 2 } });
  assert.deepEqual(logic.ratingSummaryOf({}).ratingCounts, { "1": 0, "2": 0, "3": 0, "4": 0, "5": 0 });
});

test("owner reply patch only touches ownerReply", () => {
  const patch = logic.ownerReplyPatch(null, "Obrigado!", "2026-10-16T00:00:00.000Z");
  assert.deepEqual(Object.keys(patch), ["ownerReply"]);
});
