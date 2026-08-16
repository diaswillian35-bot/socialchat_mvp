/**
 * pendingRequests create/read + collectionGroup (local rules emulator).
 */
const { readFileSync } = require("fs");
const { resolve } = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  setDoc,
  getDoc,
  getDocs,
  collectionGroup,
  query,
  where,
  serverTimestamp,
} = require("firebase/firestore");

const RULES = readFileSync(resolve(__dirname, "../firestore.rules"), "utf8");

const GROUP_ID = "pendingRulesGroup001";
const OWNER = "ownerPendingRulesUid00000000001";
const JOINER = "joinerPendingRulesUid000000001";

describe("groups pendingRequests rules", function () {
  this.timeout(40000);
  let testEnv;

  before(async () => {
    testEnv = await initializeTestEnvironment({
      projectId: "socialchatmvp-rules-pending",
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
      await db.collection("users").doc(OWNER).set({
        homeCountryCode: "br",
        countryCode: "br",
        name: "Owner",
        isPremium: false,
        ageVerificationStatus: "verified",
      });
      await db.collection("users").doc(JOINER).set({
        homeCountryCode: "br",
        countryCode: "br",
        name: "Joiner",
        isPremium: false,
        isActive: true,
        isBanned: false,
        ageVerificationStatus: "verified",
      });
      await db.collection("groups").doc(GROUP_ID).set({
        name: "Approval Group",
        joinPolicy: "approval",
        deleted: false,
        countryCode: "br",
        isPremiumGroup: false,
        ownerId: OWNER,
        members: [OWNER],
        admins: [OWNER],
        membersCount: 1,
        scope: "city",
      });
    });
  });

  it("allows joiner to create own pending request", async () => {
    const ctx = testEnv.authenticatedContext(JOINER);
    const db = ctx.firestore();
    await assertSucceeds(
      setDoc(doc(db, "groups", GROUP_ID, "pendingRequests", JOINER), {
        uid: JOINER,
        name: "Joiner",
        photoUrl: "",
        status: "pending",
        createdAt: serverTimestamp(),
      }),
    );
  });

  it("denies member creating pending for self", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("groups")
        .doc(GROUP_ID)
        .update({ members: [OWNER, JOINER], membersCount: 2 });
    });
    const ctx = testEnv.authenticatedContext(JOINER);
    const db = ctx.firestore();
    await assertFails(
      setDoc(doc(db, "groups", GROUP_ID, "pendingRequests", JOINER), {
        uid: JOINER,
        name: "Joiner",
        photoUrl: "",
        status: "pending",
        createdAt: serverTimestamp(),
      }),
    );
  });

  it("allows joiner to read own pending doc", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("groups")
        .doc(GROUP_ID)
        .collection("pendingRequests")
        .doc(JOINER)
        .set({
          uid: JOINER,
          name: "Joiner",
          photoUrl: "",
          status: "pending",
        });
    });
    const ctx = testEnv.authenticatedContext(JOINER);
    const db = ctx.firestore();
    await assertSucceeds(
      getDoc(doc(db, "groups", GROUP_ID, "pendingRequests", JOINER)),
    );
  });

  it("collectionGroup pending for own uid", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("groups")
        .doc(GROUP_ID)
        .collection("pendingRequests")
        .doc(JOINER)
        .set({
          uid: JOINER,
          name: "Joiner",
          photoUrl: "",
          status: "pending",
        });
    });
    const ctx = testEnv.authenticatedContext(JOINER);
    const db = ctx.firestore();
    const q = query(
      collectionGroup(db, "pendingRequests"),
      where("uid", "==", JOINER),
      where("status", "==", "pending"),
    );
    await assertSucceeds(getDocs(q));
  });
});
