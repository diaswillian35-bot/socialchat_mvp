/**
 * Pure Node tests for event interaction helpers (no emulator).
 * Run: node --test event_interactions_helpers.test.js
 */
const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const h = require("./event_interactions_helpers");

describe("event_interactions_helpers (functions)", () => {
  it("onlyLikesCountChanged skips side effects", () => {
    const before = { a: 1, likesCount: 0, status: "approved" };
    const after = { a: 1, likesCount: 4, status: "approved" };
    assert.equal(h.onlyLikesCountChanged(before, after), true);
    assert.equal(h.shouldNotifyEventUpdate(before, after), false);
  });

  it("concurrent desiredLiked sets are idempotent without request store", () => {
    const sim = h.simulateConcurrentDesiredSets(0, [], [
      { uid: "u", desiredLiked: true },
      { uid: "u", desiredLiked: true },
      { uid: "u", desiredLiked: true },
    ]);
    assert.equal(sim.likesCount, 1);
    assert.equal(sim.results.filter((r) => r.changed).length, 1);
  });

  it("writeCost: changed=false means zero counter writes", () => {
    const first = h.applyDesiredLike({
      currentCount: 0,
      currentlyLiked: false,
      desiredLiked: true,
    });
    assert.equal(first.changed, true);
    const retry = h.applyDesiredLike({
      currentCount: first.likesCount,
      currentlyLiked: true,
      desiredLiked: true,
    });
    assert.equal(retry.changed, false);
    assert.equal(retry.likesCount, 1);
  });

  it("parseDesiredLiked rejects missing/invalid", () => {
    assert.equal(h.parseDesiredLiked(undefined).error, "missing");
    assert.equal(h.parseDesiredLiked("yes").error, "invalid_type");
  });

  it("push idempotent gate", () => {
    assert.equal(
      h.shouldSendCommentPush({ created: false, alreadyCreated: true }),
      false
    );
  });
});
