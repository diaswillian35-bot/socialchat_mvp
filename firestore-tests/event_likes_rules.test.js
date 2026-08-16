/**
 * Rules: events likes + comments (cliente não escreve; likesCount protegido).
 */
const { readFileSync } = require("fs");
const { resolve } = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");

const RULES = readFileSync(resolve(__dirname, "../firestore.rules"), "utf8");

const EVENT_ID = "PART6_TMP_event_likes_rules";
const USER_A = "part6UserA000000000000000001";
const USER_B = "part6UserB000000000000000001";

describe("event likes + comments rules", function () {
  this.timeout(30000);
  let testEnv;

  before(async () => {
    testEnv = await initializeTestEnvironment({
      projectId: "socialchatmvp-rules-event-likes",
      firestore: {
        rules: RULES,
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
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection("users").doc(USER_A).set({ ageVerificationStatus: "verified" });
      await db.collection("users").doc(USER_B).set({ ageVerificationStatus: "verified" });
      await db.collection("events").doc(EVENT_ID).set({
        title: "PART6_TMP likes",
        status: "approved",
        isActive: true,
        createdBy: USER_A,
        likesCount: 1,
      });
      await db
        .collection("events")
        .doc(EVENT_ID)
        .collection("likes")
        .doc(USER_A)
        .set({ uid: USER_A });
      await db
        .collection("events")
        .doc(EVENT_ID)
        .collection("comments")
        .doc("commentRoot1")
        .set({
          uid: USER_A,
          text: "hello",
          likesCount: 0,
          likedBy: [],
          isDeleted: false,
        });
    });
  });

  it("allows get of own like doc", async () => {
    const db = testEnv.authenticatedContext(USER_A).firestore();
    await assertSucceeds(
      db
        .collection("events")
        .doc(EVENT_ID)
        .collection("likes")
        .doc(USER_A)
        .get()
    );
  });

  it("denies get of another user like doc", async () => {
    const db = testEnv.authenticatedContext(USER_B).firestore();
    await assertFails(
      db
        .collection("events")
        .doc(EVENT_ID)
        .collection("likes")
        .doc(USER_A)
        .get()
    );
  });

  it("denies list of likes", async () => {
    const db = testEnv.authenticatedContext(USER_A).firestore();
    await assertFails(
      db.collection("events").doc(EVENT_ID).collection("likes").get()
    );
  });

  it("denies client create/delete like", async () => {
    const db = testEnv.authenticatedContext(USER_B).firestore();
    const likeRef = db
      .collection("events")
      .doc(EVENT_ID)
      .collection("likes")
      .doc(USER_B);
    await assertFails(likeRef.set({ uid: USER_B }));
    await assertFails(
      db
        .collection("events")
        .doc(EVENT_ID)
        .collection("likes")
        .doc(USER_A)
        .delete()
    );
  });

  it("denies client updating likesCount on event", async () => {
    const db = testEnv.authenticatedContext(USER_A).firestore();
    await assertFails(
      db.collection("events").doc(EVENT_ID).update({ likesCount: 99 })
    );
  });

  it("denies likesCount-only forged update mixed with other fields", async () => {
    const db = testEnv.authenticatedContext(USER_A).firestore();
    await assertFails(
      db.collection("events").doc(EVENT_ID).update({
        likesCount: 50,
        title: "hack",
      })
    );
  });

  it("denies client comment create/update/delete", async () => {
    const db = testEnv.authenticatedContext(USER_A).firestore();
    const comments = db
      .collection("events")
      .doc(EVENT_ID)
      .collection("comments");
    await assertFails(
      comments.doc("c_new").set({ uid: USER_A, text: "hi" })
    );
    await assertFails(
      comments.doc("commentRoot1").update({ text: "changed" })
    );
    await assertFails(comments.doc("commentRoot1").delete());
  });

  it("denies forging replyToUid / likes on comment via client", async () => {
    const db = testEnv.authenticatedContext(USER_B).firestore();
    await assertFails(
      db
        .collection("events")
        .doc(EVENT_ID)
        .collection("comments")
        .doc("commentRoot1")
        .update({
          replyToUid: USER_B,
          likesCount: 999,
          likedBy: [USER_B],
        })
    );
  });

  it("allows authenticated read of comments", async () => {
    const db = testEnv.authenticatedContext(USER_B).firestore();
    await assertSucceeds(
      db
        .collection("events")
        .doc(EVENT_ID)
        .collection("comments")
        .doc("commentRoot1")
        .get()
    );
  });

  it("denies unauthenticated event read", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(db.collection("events").doc(EVENT_ID).get());
  });
});
