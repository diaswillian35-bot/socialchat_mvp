/**
 * Rules: forwardIdempotency must be deny-all for clients.
 * Requires Java + Firestore emulator.
 */
const { readFileSync } = require("fs");
const { resolve } = require("path");
const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} = require("@firebase/rules-unit-testing");
const { doc, getDoc, setDoc } = require("firebase/firestore");

const PROJECT_ID = "socialchatmvp-forward-rules";
const RULES_PATH = resolve(__dirname, "../firestore.rules");

describe("forwardIdempotency deny-all", function () {
  this.timeout(30000);
  let testEnv;

  before(async () => {
    const rules = readFileSync(RULES_PATH, "utf8");
    // Static guard before emulator
    if (!/match \/forwardIdempotency\/\{id\}[\s\S]*?allow read, write: if false;/.test(rules)) {
      throw new Error("forwardIdempotency deny-all missing from firestore.rules");
    }
    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: { rules, host: "127.0.0.1", port: 8080 },
    });
  });

  after(async () => {
    if (testEnv) await testEnv.cleanup();
  });

  it("rejects authenticated client read/write", async () => {
    const ctx = testEnv.authenticatedContext("user_fwd_1");
    const db = ctx.firestore();
    const ref = doc(db, "forwardIdempotency", "fwd_user_fwd_1_intent1");
    await assertFails(getDoc(ref));
    await assertFails(setDoc(ref, { uid: "user_fwd_1", ok: true }));
  });

  it("rejects unauthenticated client read/write", async () => {
    const ctx = testEnv.unauthenticatedContext();
    const db = ctx.firestore();
    const ref = doc(db, "forwardIdempotency", "fwd_anon");
    await assertFails(getDoc(ref));
    await assertFails(setDoc(ref, { hack: true }));
  });
});
