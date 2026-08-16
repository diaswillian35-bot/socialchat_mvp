const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");

const PROJECT_ID = "remdy-reports-rules-test";
let testEnv;

before(async function () {
  this.timeout(60000);
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(
        path.resolve(__dirname, "..", "firestore.rules"),
        "utf8",
      ),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

after(async () => testEnv && testEnv.cleanup());
beforeEach(async () => testEnv.clearFirestore());

async function seedReport() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc("reports/critical-1").set({
      fromUid: "reporter",
      reportedUid: "reported",
      reasonCode: "child_sexual_exploitation_or_abuse",
      priority: "critical",
      requiresChildSafetyReview: true,
      contextType: "dm_message",
      conversationId: "conversation-1",
      messageId: "message-1",
      status: "open",
    });
  });
}

describe("reports privacy and immutability", () => {
  it("allows an authenticated reporter to create a reference-only report", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("users/reporter").set({
        ageVerificationStatus: "verified",
      });
    });
    const db = testEnv.authenticatedContext("reporter").firestore();
    await assertSucceeds(
      db.collection("reports").add({
        fromUid: "reporter",
        reportedUid: "reported",
        reasonCode: "child_sexual_exploitation_or_abuse",
        priority: "critical",
        requiresChildSafetyReview: true,
        contextType: "dm_message",
        conversationId: "conversation-1",
        messageId: "message-1",
        status: "open",
      }),
    );
  });

  it("rejects unauthenticated report creation", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.collection("reports").add({ status: "open" }));
  });

  it("never exposes a report to reporter, reported user, or forged roles", async () => {
    await seedReport();
    for (const ctx of [
      testEnv.authenticatedContext("reporter"),
      testEnv.authenticatedContext("reported"),
      testEnv.authenticatedContext("premium", { premium: true }),
      testEnv.authenticatedContext("forged-admin", { admin: true }),
    ]) {
      await assertFails(ctx.firestore().doc("reports/critical-1").get());
    }
  });

  it("never allows a client to edit or delete a report", async () => {
    await seedReport();
    for (const ctx of [
      testEnv.authenticatedContext("reporter"),
      testEnv.authenticatedContext("reported"),
      testEnv.authenticatedContext("premium", { premium: true }),
      testEnv.authenticatedContext("forged-admin", { admin: true }),
    ]) {
      const ref = ctx.firestore().doc("reports/critical-1");
      await assertFails(ref.update({ priority: "normal" }));
      await assertFails(ref.delete());
    }
  });
});
