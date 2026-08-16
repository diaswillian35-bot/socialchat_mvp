/**
 * Rules: conversations/{cid}.replyQuota — deny client create/edit/delete.
 *
 * Static checks always run. Emulator cases require Java + Firestore emulator:
 *   RUN_FIRESTORE_EMULATOR=1 firebase emulators:exec --only firestore \
 *     "npx mocha dm_reply_quota_rules.test.js"
 */
const assert = require("assert");
const fs = require("fs");
const path = require("path");

const RULES_PATH = path.resolve(__dirname, "..", "firestore.rules");

describe("replyQuota rules — static", () => {
  const rules = fs.readFileSync(RULES_PATH, "utf8");

  it("forbids replyQuota on conversation create", () => {
    assert.ok(
      rules.includes("!('replyQuota' in request.resource.data)"),
      "create must include !('replyQuota' in request.resource.data)",
    );
  });

  it("forbids replyQuota in conversation update affectedKeys", () => {
    assert.ok(
      rules.includes(
        "!('replyQuota' in request.resource.data.diff(resource.data).affectedKeys())",
      ),
    );
  });

  it("hasOnly allowlist excludes replyQuota", () => {
    const start = rules.indexOf("match /conversations/{cid}");
    assert.ok(start >= 0);
    const slice = rules.slice(start, start + 2500);
    assert.ok(slice.includes("hasOnly(["), "hasOnly missing under conversations");
    assert.ok(
      slice.includes("'lastMessage'") && slice.includes("'typing'"),
      "expected conversation update allowlist",
    );
    // replyQuota must not appear inside the hasOnly allowlist block
    const hasOnlyIdx = slice.indexOf("hasOnly([");
    const hasOnlyEnd = slice.indexOf("]);", hasOnlyIdx);
    const allowlist = slice.slice(hasOnlyIdx, hasOnlyEnd);
    assert.ok(!allowlist.includes("replyQuota"));
  });

  it("dmSendIdempotency is deny-all", () => {
    assert.match(
      rules,
      /match \/dmSendIdempotency\/\{id\}[\s\S]*?allow read, write: if false;/,
    );
  });
});

let rulesUnitTesting = null;
try {
  rulesUnitTesting = require("@firebase/rules-unit-testing");
} catch (_) {
  rulesUnitTesting = null;
}

const RUN_EMULATOR =
  process.env.RUN_FIRESTORE_EMULATOR === "1" ||
  !!process.env.FIRESTORE_EMULATOR_HOST;

(RUN_EMULATOR && rulesUnitTesting ? describe : describe.skip)(
  "conversations.replyQuota client denial (emulator)",
  function () {
    this.timeout(60000);
    const { initializeTestEnvironment, assertFails, assertSucceeds } =
      rulesUnitTesting;
    let testEnv;

    before(async () => {
      const rules = fs.readFileSync(RULES_PATH, "utf8");
      testEnv = await initializeTestEnvironment({
        projectId: "remdy-reply-quota-rules",
        firestore: { rules, host: "127.0.0.1", port: 8080 },
      });
    });

    after(async () => {
      if (testEnv) await testEnv.cleanup();
    });

    beforeEach(async () => {
      await testEnv.clearFirestore();
    });

    function authed(uid) {
      return testEnv.authenticatedContext(uid).firestore();
    }

    async function seedConversation(withQuota) {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await db.doc("users/free1").set({
          uid: "free1",
          homeCountryCode: "br",
          isPremium: false,
          ageVerificationStatus: "verified",
        });
        await db.doc("users/prem1").set({
          uid: "prem1",
          homeCountryCode: "us",
          isPremium: true,
          ageVerificationStatus: "verified",
        });
        const payload = {
          participants: ["free1", "prem1"],
          pairKey: "free1_prem1",
          lastMessage: "hi",
          unread: { free1: 0, prem1: 0 },
        };
        if (withQuota) {
          payload.replyQuota = {
            version: 1,
            enabled: true,
            freeUid: "free1",
            initiatorUid: "prem1",
            limit: 300,
            used: 10,
          };
        }
        await db.doc("conversations/c1").set(payload);
      });
    }

    it("rejects create with replyQuota forged", async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc("users/free1").set({
          uid: "free1",
          homeCountryCode: "br",
          ageVerificationStatus: "verified",
        });
        await ctx.firestore().doc("users/peer1").set({
          uid: "peer1",
          homeCountryCode: "br",
          ageVerificationStatus: "verified",
        });
      });
      const db = authed("free1");
      await assertFails(
        db.doc("conversations/c_new").set({
          participants: ["free1", "peer1"],
          pairKey: "free1_peer1",
          replyQuota: {
            freeUid: "free1",
            used: 0,
            limit: 9999,
            enabled: true,
          },
        }),
      );
    });

    it("rejects update that tampers used", async () => {
      await seedConversation(true);
      const db = authed("free1");
      await assertFails(
        db.doc("conversations/c1").update({
          replyQuota: {
            version: 1,
            enabled: true,
            freeUid: "free1",
            initiatorUid: "prem1",
            limit: 300,
            used: 0,
          },
        }),
      );
    });

    it("rejects update that tampers limit", async () => {
      await seedConversation(true);
      const db = authed("free1");
      await assertFails(
        db.doc("conversations/c1").update({ "replyQuota.limit": 99999 }),
      );
    });

    it("rejects update that tampers enabled", async () => {
      await seedConversation(true);
      const db = authed("free1");
      await assertFails(
        db.doc("conversations/c1").update({ "replyQuota.enabled": false }),
      );
    });

    it("rejects update that tampers freeUid", async () => {
      await seedConversation(true);
      const db = authed("free1");
      await assertFails(
        db.doc("conversations/c1").update({ "replyQuota.freeUid": "prem1" }),
      );
    });

    it("rejects update that tampers initiatorUid", async () => {
      await seedConversation(true);
      const db = authed("free1");
      await assertFails(
        db.doc("conversations/c1").update({
          "replyQuota.initiatorUid": "free1",
        }),
      );
    });

    it("rejects complete removal of replyQuota", async () => {
      await seedConversation(true);
      const db = authed("free1");
      await assertFails(
        db.doc("conversations/c1").set(
          { lastMessage: "x", replyQuota: null },
          { merge: true },
        ),
      );
    });

    it("rejects manual creation of replyQuota on existing conv", async () => {
      await seedConversation(false);
      const db = authed("free1");
      await assertFails(
        db.doc("conversations/c1").update({
          replyQuota: {
            freeUid: "free1",
            used: 0,
            limit: 300,
            enabled: true,
            initiatorUid: "prem1",
          },
        }),
      );
    });

    it("allows allowed conversation fields without touching replyQuota", async () => {
      await seedConversation(true);
      const db = authed("free1");
      await assertSucceeds(
        db.doc("conversations/c1").update({
          lastMessage: "ok",
          updatedAt: new Date(),
        }),
      );
    });

    it("rejects dmSendIdempotency client writes", async () => {
      const db = authed("free1");
      await assertFails(
        db.doc("dmSendIdempotency/free1_req1").set({ ok: true }),
      );
    });
  },
);
