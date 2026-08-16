/**
 * Unit tests — createEventComment / toggleEventLike / onEventUpdated guards.
 */
const assert = require("assert");
const h = require("../functions/event_interactions_helpers");

describe("event interactions unit (functions helpers)", function () {
  describe("eventAllowsLikes / Comments", () => {
    it("requires approved + active + not deleted/cancelled", () => {
      assert.strictEqual(
        h.eventAllowsLikes({
          isActive: true,
          status: "approved",
        }),
        true
      );
      assert.strictEqual(
        h.eventAllowsLikes({ isActive: true, status: "pending" }),
        false
      );
      assert.strictEqual(
        h.eventAllowsLikes({ isActive: false, status: "approved" }),
        false
      );
      assert.strictEqual(
        h.eventAllowsLikes({
          isActive: true,
          status: "approved",
          deleted: true,
        }),
        false
      );
      assert.strictEqual(
        h.eventAllowsLikes({ isActive: true, status: "cancelled" }),
        false
      );
      assert.strictEqual(
        h.eventAllowsComments({ isActive: true, status: "approved" }),
        true
      );
      assert.strictEqual(
        h.eventAllowsComments({ isActive: true, status: "draft" }),
        false
      );
    });
  });

  describe("toggleEventLike counter", () => {
    it("keeps likesCount >= 0 and idempotent toggle deltas", () => {
      assert.strictEqual(h.normalizeLikesCount(-3), 0);
      assert.strictEqual(h.normalizeLikesCount("x"), 0);
      assert.strictEqual(
        h.nextLikesCountAfterToggle({
          currentCount: 0,
          currentlyLiked: true,
        }),
        0
      );
      assert.strictEqual(
        h.nextLikesCountAfterToggle({
          currentCount: 2,
          currentlyLiked: false,
        }),
        3
      );
      assert.strictEqual(
        h.nextLikesCountAfterToggle({
          currentCount: 2,
          currentlyLiked: true,
        }),
        1
      );
    });

    it("repairs negative/NaN counter before apply", () => {
      assert.strictEqual(
        h.nextLikesCountAfterToggle({
          currentCount: -10,
          currentlyLiked: false,
        }),
        1
      );
    });

    it("is safe under serialized concurrent toggles (tx retry model)", () => {
      const sim = h.simulateConcurrentToggles(0, [], [
        "a",
        "b",
        "a", // double-tap unlike
        "c",
        "b",
        "a",
      ]);
      assert.strictEqual(sim.likesCount, 2);
      assert.deepStrictEqual(sim.liked, ["a", "c"]);
    });

    it("double-tap like then unlike ends at zero", () => {
      const sim = h.simulateConcurrentToggles(0, [], ["u1", "u1"]);
      assert.strictEqual(sim.likesCount, 0);
      assert.deepStrictEqual(sim.liked, []);
    });
  });

  describe("setEventLike / desiredLiked idempotency", () => {
    it("1) true twice → liked once, count +1", () => {
      const a = h.applyDesiredLike({
        currentCount: 0,
        currentlyLiked: false,
        desiredLiked: true,
      });
      assert.deepStrictEqual(a, { liked: true, likesCount: 1, changed: true });
      const b = h.applyDesiredLike({
        currentCount: a.likesCount,
        currentlyLiked: true,
        desiredLiked: true,
      });
      assert.deepStrictEqual(b, { liked: true, likesCount: 1, changed: false });
    });

    it("2) false twice → unliked once, count -1 only once", () => {
      const a = h.applyDesiredLike({
        currentCount: 3,
        currentlyLiked: true,
        desiredLiked: false,
      });
      assert.deepStrictEqual(a, { liked: false, likesCount: 2, changed: true });
      const b = h.applyDesiredLike({
        currentCount: a.likesCount,
        currentlyLiked: false,
        desiredLiked: false,
      });
      assert.deepStrictEqual(b, { liked: false, likesCount: 2, changed: false });
    });

    it("3) two concurrent true → single +1", () => {
      const sim = h.simulateConcurrentDesiredSets(0, [], [
        { uid: "u", desiredLiked: true },
        { uid: "u", desiredLiked: true },
      ]);
      assert.strictEqual(sim.likesCount, 1);
      assert.deepStrictEqual(sim.liked, ["u"]);
      assert.strictEqual(sim.results[0].changed, true);
      assert.strictEqual(sim.results[1].changed, false);
    });

    it("4) two concurrent false → single -1", () => {
      const sim = h.simulateConcurrentDesiredSets(4, ["u"], [
        { uid: "u", desiredLiked: false },
        { uid: "u", desiredLiked: false },
      ]);
      assert.strictEqual(sim.likesCount, 3);
      assert.deepStrictEqual(sim.liked, []);
      assert.strictEqual(sim.results[0].changed, true);
      assert.strictEqual(sim.results[1].changed, false);
    });

    it("5) retry after timeout (same desiredLiked) does not re-apply", () => {
      const sim = h.simulateConcurrentDesiredSets(0, [], [
        { uid: "u", desiredLiked: true },
        { uid: "u", desiredLiked: true },
      ]);
      assert.strictEqual(sim.likesCount, 1);
      assert.strictEqual(sim.results[1].changed, false);
      assert.strictEqual(sim.results[1].liked, true);
    });

    it("6) opposite sequence respects last action", () => {
      const sim = h.simulateConcurrentDesiredSets(0, [], [
        { uid: "u", desiredLiked: true },
        { uid: "u", desiredLiked: false },
        { uid: "u", desiredLiked: true },
      ]);
      assert.strictEqual(sim.likesCount, 1);
      assert.deepStrictEqual(sim.liked, ["u"]);
    });

    it("7) initial counter zero", () => {
      const r = h.applyDesiredLike({
        currentCount: 0,
        currentlyLiked: false,
        desiredLiked: true,
      });
      assert.strictEqual(r.likesCount, 1);
    });

    it("8) inconsistent/negative counter repaired", () => {
      const r = h.applyDesiredLike({
        currentCount: -5,
        currentlyLiked: false,
        desiredLiked: true,
      });
      assert.strictEqual(r.likesCount, 1);
      const u = h.applyDesiredLike({
        currentCount: -2,
        currentlyLiked: true,
        desiredLiked: false,
      });
      assert.strictEqual(u.likesCount, 0);
    });

    it("9) invalid eventId rejected by validator", () => {
      assert.strictEqual(h.isValidEventId(""), false);
      assert.strictEqual(h.isValidEventId("ab"), false);
      assert.strictEqual(h.isValidEventId("bad id!"), false);
      assert.strictEqual(h.isValidEventId("abcdef"), true);
    });

    it("10) event gate independent of ban (ban enforced in CF)", () => {
      assert.strictEqual(
        h.eventAllowsLikes({ isActive: true, status: "approved" }),
        true
      );
    });

    it("11-12) desiredLiked missing / invalid type", () => {
      assert.strictEqual(h.parseDesiredLiked(undefined).error, "missing");
      assert.strictEqual(h.parseDesiredLiked(null).error, "missing");
      assert.strictEqual(h.parseDesiredLiked("true").error, "invalid_type");
      assert.strictEqual(h.parseDesiredLiked(1).error, "invalid_type");
      assert.strictEqual(h.parseDesiredLiked(true).desiredLiked, true);
      assert.strictEqual(h.parseDesiredLiked(false).desiredLiked, false);
    });
  });

  describe("ids / sanitize", () => {
    it("validates eventId / commentId / requestId", () => {
      assert.strictEqual(h.isValidEventId("abcdef"), true);
      assert.strictEqual(h.isValidEventId(""), false);
      assert.strictEqual(h.isValidEventId("bad id"), false);
      assert.strictEqual(h.isValidClientId("c_12345678"), true);
      assert.strictEqual(h.isValidClientId("short"), false);
    });

    it("sanitizes comment text", () => {
      assert.strictEqual(h.sanitizeCommentText("  hi  ").text, "hi");
      assert.strictEqual(h.sanitizeCommentText("").error, "empty");
      assert.strictEqual(h.sanitizeCommentText(1).error, "invalid");
      assert.strictEqual(
        h.sanitizeCommentText("x".repeat(h.EVENT_COMMENT_MAX_LEN + 1)).error,
        "too_long"
      );
    });
  });

  describe("replies", () => {
    it("flattens reply-of-reply to root and fills server meta", () => {
      const meta = h.buildReplyMetaFromParent({
        replyToCommentId: "child",
        parent: {
          uid: "parentUid",
          name: "Ana",
          text: "hello world",
          replyToCommentId: "root",
        },
      });
      assert.strictEqual(meta.rootCommentId, "root");
      assert.strictEqual(meta.replyToCommentId, "root");
      assert.strictEqual(meta.replyToUid, "parentUid");
      assert.strictEqual(meta.replyToName, "Ana");
      assert.strictEqual(meta.replyToText, "hello world");
    });

    it("rejects deleted parent", () => {
      const meta = h.buildReplyMetaFromParent({
        replyToCommentId: "c1",
        parent: { isDeleted: true, uid: "x" },
      });
      assert.strictEqual(meta.error, "parent_deleted");
    });

    it("ignores client-provided reply identity (server uses parent)", () => {
      const meta = h.buildReplyMetaFromParent({
        replyToCommentId: "c1",
        parent: { uid: "real", name: "Real", text: "t" },
      });
      assert.strictEqual(meta.replyToUid, "real");
      assert.notStrictEqual(meta.replyToUid, "forged");
    });
  });

  describe("onEventUpdated likesCount-only", () => {
    it("detects likesCount-only update", () => {
      const before = {
        title: "E",
        status: "approved",
        isActive: true,
        likesCount: 1,
        hasPendingChanges: false,
      };
      const after = { ...before, likesCount: 2 };
      assert.strictEqual(h.onlyLikesCountChanged(before, after), true);
      assert.strictEqual(h.shouldNotifyEventUpdate(before, after), false);
    });

    it("does not skip when status changes", () => {
      const before = { status: "pending", likesCount: 0, isActive: false };
      const after = { status: "approved", likesCount: 0, isActive: true };
      assert.strictEqual(h.onlyLikesCountChanged(before, after), false);
      assert.strictEqual(h.shouldNotifyEventUpdate(before, after), true);
    });

    it("does not skip when hasPendingChanges flips", () => {
      const before = {
        status: "approved",
        likesCount: 3,
        hasPendingChanges: false,
      };
      const after = {
        status: "approved",
        likesCount: 3,
        hasPendingChanges: true,
      };
      assert.strictEqual(h.onlyLikesCountChanged(before, after), false);
    });
  });

  describe("push idempotency", () => {
    it("sends push only on created=true", () => {
      assert.strictEqual(
        h.shouldSendCommentPush({ created: true, alreadyCreated: false }),
        true
      );
      assert.strictEqual(
        h.shouldSendCommentPush({ created: false, alreadyCreated: true }),
        false
      );
    });

    it("does not notify actor; reply→parent, comment→organizer", () => {
      assert.deepStrictEqual(
        h.resolveCommentPushTargets({
          actorUid: "a",
          isReply: true,
          replyToUid: "b",
          organizerUid: "org",
        }),
        ["b"]
      );
      assert.deepStrictEqual(
        h.resolveCommentPushTargets({
          actorUid: "a",
          isReply: true,
          replyToUid: "a",
          organizerUid: "org",
        }),
        []
      );
      assert.deepStrictEqual(
        h.resolveCommentPushTargets({
          actorUid: "a",
          isReply: false,
          replyToUid: "",
          organizerUid: "org",
        }),
        ["org"]
      );
      assert.deepStrictEqual(
        h.resolveCommentPushTargets({
          actorUid: "org",
          isReply: false,
          replyToUid: "",
          organizerUid: "org",
        }),
        []
      );
    });
  });
});
