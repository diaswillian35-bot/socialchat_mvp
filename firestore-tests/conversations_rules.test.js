/**
 * Regressão Rules — conversations/{cid} após proteção replyQuota/hasOnly.
 * Requer Firestore emulator (port 8080).
 */
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");

const RULES_PATH = path.resolve(__dirname, "..", "firestore.rules");
const PROJECT_ID = "remdy-conversations-rules";

let testEnv;

before(async function () {
  this.timeout(60000);
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
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

async function seedUsersSameCountry() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc("users/a1").set({
      uid: "a1",
      homeCountryCode: "br",
      isPremium: false,
      ageVerificationStatus: "verified",
    });
    await db.doc("users/b1").set({
      uid: "b1",
      homeCountryCode: "br",
      isPremium: false,
      ageVerificationStatus: "verified",
    });
  });
}

async function seedIntlPremiumFree() {
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
      premiumUntil: new Date(Date.now() + 86400000),
      ageVerificationStatus: "verified",
    });
  });
}

describe("conversations rules regression (hasOnly + replyQuota)", () => {
  it("allows same-country conversation create without replyQuota", async () => {
    await seedUsersSameCountry();
    const db = authed("a1");
    await assertSucceeds(
      db.doc("conversations/a1_b1").set({
        participants: ["a1", "b1"],
        pairKey: "a1_b1",
        lastMessage: "",
        unread: { a1: 0, b1: 0 },
      }),
    );
  });

  it("rejects Free creating international conversation", async () => {
    await seedIntlPremiumFree();
    const db = authed("free1");
    await assertFails(
      db.doc("conversations/free1_prem1").set({
        participants: ["free1", "prem1"],
        pairKey: "free1_prem1",
      }),
    );
  });

  it("allows Premium creating international conversation", async () => {
    await seedIntlPremiumFree();
    const db = authed("prem1");
    await assertSucceeds(
      db.doc("conversations/free1_prem1").set({
        participants: ["free1", "prem1"],
        pairKey: "free1_prem1",
        lastMessage: "",
        unread: { free1: 0, prem1: 0 },
      }),
    );
  });

  it("allows participant update of lastMessage/unread/updatedAt", async () => {
    await seedUsersSameCountry();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("conversations/c1").set({
        participants: ["a1", "b1"],
        pairKey: "a1_b1",
        lastMessage: "old",
        unread: { a1: 0, b1: 1 },
      });
    });
    const db = authed("a1");
    await assertSucceeds(
      db.doc("conversations/c1").update({
        lastMessage: "novo",
        lastMessageType: "text",
        lastMessageAt: new Date(),
        updatedAt: new Date(),
        unread: { a1: 0, b1: 2 },
      }),
    );
  });

  it("rejects participant list mutation", async () => {
    await seedUsersSameCountry();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("conversations/c1").set({
        participants: ["a1", "b1"],
        pairKey: "a1_b1",
      });
    });
    const db = authed("a1");
    await assertFails(
      db.doc("conversations/c1").update({
        participants: ["a1", "b1", "c1"],
        lastMessage: "x",
      }),
    );
  });

  it("allows same-country Free text message create", async () => {
    await seedUsersSameCountry();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("conversations/c1").set({
        participants: ["a1", "b1"],
        pairKey: "a1_b1",
      });
    });
    const db = authed("a1");
    await assertSucceeds(
      db.doc("conversations/c1/messages/m1").set({
        type: "text",
        text: "olá com reply",
        senderId: "a1",
        fromUid: "a1",
        toUid: "b1",
        createdAt: new Date(),
        clientCreatedAt: new Date(),
        deleted: false,
        deletedBy: "",
        deletedText: "",
        deletedAt: null,
        replyToMessageId: "m0",
        replyToText: "hi",
        replyToType: "text",
        replyToIsMe: false,
        replyToImageUrl: "",
      }),
    );
  });

  it("allows soft-delete by author", async () => {
    await seedUsersSameCountry();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc("conversations/c1").set({
        participants: ["a1", "b1"],
        pairKey: "a1_b1",
      });
      await db.doc("conversations/c1/messages/m1").set({
        type: "text",
        text: "x",
        senderId: "a1",
        fromUid: "a1",
        toUid: "b1",
        deleted: false,
      });
    });
    const db = authed("a1");
    await assertSucceeds(
      db.doc("conversations/c1/messages/m1").update({
        deleted: true,
        deletedBy: "a1",
        deletedText: "apagada",
        deletedAt: new Date(),
      }),
    );
  });

  it("rejects Free international message create (client path)", async () => {
    await seedIntlPremiumFree();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("conversations/c_intl").set({
        participants: ["free1", "prem1"],
        pairKey: "free1_prem1",
      });
    });
    const db = authed("free1");
    await assertFails(
      db.doc("conversations/c_intl/messages/m1").set({
        type: "text",
        text: "should fail",
        senderId: "free1",
        fromUid: "free1",
        toUid: "prem1",
        deleted: false,
      }),
    );
  });

  it("allows conversation presence write for participant", async () => {
    await seedUsersSameCountry();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("conversations/c1").set({
        participants: ["a1", "b1"],
        pairKey: "a1_b1",
      });
    });
    const db = authed("a1");
    await assertSucceeds(
      db.doc("conversations/c1/presence/a1").set({
        uid: "a1",
        typing: true,
        updatedAt: new Date(),
      }),
    );
  });

  it("rejects non-participant read of conversation", async () => {
    await seedUsersSameCountry();
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("users/x1").set({
        uid: "x1", ageVerificationStatus: "verified",
      });
      await ctx.firestore().doc("conversations/c1").set({
        participants: ["a1", "b1"],
        pairKey: "a1_b1",
      });
    });
    const db = authed("x1");
    await assertFails(db.doc("conversations/c1").get());
  });
});
