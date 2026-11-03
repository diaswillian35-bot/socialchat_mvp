/**
 * storage.rules: chat_images exige metadata.fromUid == auth.uid.
 * Requer os emuladores de Firestore (8080) e Storage (9199).
 */
const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");

const PROJECT_ID = "socialchatmvp";
let testEnv;

before(async function () {
  this.timeout(60000);
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, "..", "firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
    storage: {
      rules: fs.readFileSync(path.resolve(__dirname, "..", "storage.rules"), "utf8"),
      host: "127.0.0.1",
      port: 9199,
    },
  });
});

after(async () => testEnv && testEnv.cleanup());
beforeEach(async () => testEnv.clearFirestore());

async function seedConversation() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc("conversations/c1").set({
      participants: ["a1", "b1"],
    });
  });
}

function upload(storage, path, metadata) {
  return storage.ref(path).putString("img", "raw", metadata);
}

describe("chat_images metadata.fromUid", () => {
  it("permite upload quando fromUid é o auth.uid", async () => {
    await seedConversation();
    const storage = testEnv.authenticatedContext("a1").storage();
    await assertSucceeds(
      upload(storage, "chat_images/c1/a.jpg", {
        contentType: "image/jpeg",
        customMetadata: { fromUid: "a1" },
      }),
    );
  });

  it("nega upload sem fromUid ou com fromUid de outra pessoa", async () => {
    await seedConversation();
    const storage = testEnv.authenticatedContext("a1").storage();
    await assertFails(
      upload(storage, "chat_images/c1/b.jpg", {
        contentType: "image/jpeg",
      }),
    );
    await assertFails(
      upload(storage, "chat_images/c1/c.jpg", {
        contentType: "image/jpeg",
        customMetadata: { fromUid: "b1" },
      }),
    );
  });
});
