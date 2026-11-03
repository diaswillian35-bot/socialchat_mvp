/**
 * Regras de moderação: suspenso não cria mensagem; cliente não lê
 * quarentena lógica (coleções server-only) nem apaga o próprio status.
 * Requer Firestore emulator na porta 8080.
 */
const fs = require("fs");
const path = require("path");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const { serverTimestamp } = require("firebase/firestore");

const PROJECT_ID = "remdy-moderation-rules";
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
  });
});

after(async () => testEnv && testEnv.cleanup());
beforeEach(async () => testEnv.clearFirestore());

function authed(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

async function seedPair(extraA = {}) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc("users/a1").set({
      uid: "a1",
      homeCountryCode: "br",
      ageVerificationStatus: "verified",
      ...extraA,
    });
    await db.doc("users/b1").set({
      uid: "b1",
      homeCountryCode: "br",
      ageVerificationStatus: "verified",
    });
    await db.doc("conversations/c1").set({
      participants: ["a1", "b1"],
      pairKey: "a1_b1",
    });
    await db.doc("groups/g1").set({
      members: ["a1", "b1"],
      admins: [],
      ownerId: "a1",
      deleted: false,
      countryCode: "br",
    });
  });
}

function dmMessage() {
  return {
    type: "text",
    text: "olá",
    senderId: "a1",
    fromUid: "a1",
    toUid: "b1",
    createdAt: new Date(),
    deleted: false,
    deletedBy: "",
    deletedText: "",
    deletedAt: null,
  };
}

function groupMessage() {
  return {
    id: "m1",
    type: "text",
    text: "olá",
    senderId: "a1",
    createdAt: serverTimestamp(),
    replyToMessageId: "",
    replyToText: "",
    replyToType: "text",
    replyToIsMe: false,
    replyToImageUrl: "",
    deleted: false,
    deletedBy: "",
    deletedText: "",
    deletedAt: null,
  };
}

describe("moderation rules", () => {
  it("permite mensagem de quem não está suspenso", async () => {
    await seedPair();
    const db = authed("a1");
    await assertSucceeds(db.doc("conversations/c1/messages/m1").set(dmMessage()));
  });

  it("nega create de DM e de grupo quando suspenso", async () => {
    await seedPair({
      moderation: { status: "suspended_pending_review" },
    });
    const db = authed("a1");
    await assertFails(db.doc("conversations/c1/messages/m2").set(dmMessage()));
    await assertFails(db.doc("groups/g1/messages/m1").set(groupMessage()));
  });

  it("o usuário não apaga o próprio status de moderação", async () => {
    await seedPair({
      moderation: { status: "suspended_pending_review" },
    });
    const db = authed("a1");
    await assertFails(db.doc("users/a1").update({ moderation: null }));
  });

  it("cliente não lê strikes, auditoria, pending nem holds", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.doc("users/a1").set({ ageVerificationStatus: "verified" });
      await db.doc("moderationStrikes/a1").set({ count: 1 });
      await db.doc("moderationAudit/a1").set({ action: "suspend" });
      await db.doc("pendingModeration/abc").set({ status: "blocked" });
      await db.doc("csamHolds/r1").set({ legalHold: true });
    });
    const db = authed("a1");
    await assertFails(db.doc("moderationStrikes/a1").get());
    await assertFails(db.doc("moderationAudit/a1").get());
    await assertFails(db.doc("pendingModeration/abc").get());
    await assertFails(db.doc("csamHolds/r1").get());
  });

  it("usuário logado lê a config de domínios e não escreve", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc("users/a1").set({
        ageVerificationStatus: "verified",
      });
      await ctx.firestore().doc("appConfig/moderation").set({
        enabled: true,
        blockedDomains: ["onlyfans.com"],
      });
    });
    const db = authed("a1");
    await assertSucceeds(db.doc("appConfig/moderation").get());
    await assertFails(db.doc("appConfig/moderation").update({ enabled: false }));
  });

  function chatImageUrl(cid) {
    return `https://firebasestorage.googleapis.com/v0/b/socialchatmvp.firebasestorage.app/o/chat_images%2F${cid}%2Fa.jpg?alt=media`;
  }

  function groupImageUrl(gid, uid) {
    return `https://firebasestorage.googleapis.com/v0/b/socialchatmvp.firebasestorage.app/o/groups%2F${gid}%2Fimages%2F${uid}%2Fa.jpg?alt=media`;
  }

  it("nega moderation no create e no update de DM e de grupo", async () => {
    await seedPair();
    const db = authed("a1");
    await assertFails(
      db.doc("conversations/c1/messages/m-mod").set({
        ...dmMessage(),
        moderation: { status: "blocked" },
      }),
    );
    await assertSucceeds(db.doc("conversations/c1/messages/m-ok").set(dmMessage()));
    await assertFails(
      db.doc("conversations/c1/messages/m-ok").update({
        moderation: { status: "blocked" },
      }),
    );
    await assertFails(
      db.doc("groups/g1/messages/m-mod").set({
        ...groupMessage(),
        moderation: { status: "blocked" },
      }),
    );
  });

  it("imageUrl e replyToImageUrl só no bucket e no path da conversa ou do grupo", async () => {
    await seedPair();
    const db = authed("a1");
    await assertSucceeds(
      db.doc("conversations/c1/messages/img-ok").set({
        ...dmMessage(),
        type: "image",
        text: "",
        imageUrl: chatImageUrl("c1"),
        replyToImageUrl: chatImageUrl("c1"),
      }),
    );
    await assertFails(
      db.doc("conversations/c1/messages/img-bad").set({
        ...dmMessage(),
        type: "image",
        imageUrl: "https://evil.example/a.jpg",
      }),
    );
    await assertFails(
      db.doc("conversations/c1/messages/reply-bad").set({
        ...dmMessage(),
        replyToImageUrl: chatImageUrl("outra"),
      }),
    );
    await assertSucceeds(
      db.doc("groups/g1/messages/img-ok").set({
        ...groupMessage(),
        type: "image",
        text: "",
        imageUrl: groupImageUrl("g1", "a1"),
        replyToImageUrl: groupImageUrl("g1", "b1"),
      }),
    );
    await assertFails(
      db.doc("groups/g1/messages/img-bad").set({
        ...groupMessage(),
        type: "image",
        text: "",
        imageUrl: "https://firebasestorage.googleapis.com/v0/b/outro.appspot.com/o/groups%2Fg1%2Fimages%2Fa1%2Fa.jpg",
      }),
    );
  });

  it("denúncia CSAM de usuário pode ser criada; o cliente não suspende o denunciado", async () => {
    await seedPair();
    const db = authed("a1");
    await assertSucceeds(
      db.collection("reports").add({
        fromUid: "a1",
        reportedUid: "b1",
        reasonCode: "child_sexual_exploitation_or_abuse",
        priority: "critical",
        requiresChildSafetyReview: true,
        status: "open",
      }),
    );
    await assertFails(
      db.doc("users/b1").update({
        moderation: { status: "suspended_pending_review" },
      }),
    );
  });
});
