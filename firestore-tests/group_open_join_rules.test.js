/**
 * Security review — self-join open em /groups/{groupId}.
 * Campos permitidos: members, membersCount, updatedAt (== request.time).
 */
const { readFileSync } = require("fs");
const { resolve } = require("path");
const {
  initializeTestEnvironment,
  assertFails,
} = require("@firebase/rules-unit-testing");
const {
  serverTimestamp,
  Timestamp,
  deleteField,
} = require("firebase/firestore");

const RULES = readFileSync(
  resolve(__dirname, "../firestore.rules"),
  "utf8"
);

const GROUP_ID = "GzP04JcPD2sK0z8bq2p9";
const OWNER = "6s8F6kP0o5UcBpAqVTKuTsxWd0h2";
const JOINER = "0mCluVDJs3WQDjEuhwjhHvY4S873";
const OTHER = "otherUid00000000000000000001";

function validJoinPayload(extra = {}) {
  return {
    members: [OWNER, JOINER],
    membersCount: 2,
    updatedAt: serverTimestamp(),
    ...extra,
  };
}

describe("groups open self-join — security review", function () {
  this.timeout(30000);
  let testEnv;

  before(async () => {
    testEnv = await initializeTestEnvironment({
      projectId: "socialchatmvp-rules-join",
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
      await db.collection("users").doc(JOINER).set({
        homeCountryCode: "br",
        countryCode: "br",
        country: "Brasil",
        name: "Willian",
        isPremium: false,
        isMaster: null,
        premiumUntil: null,
        ageVerificationStatus: "verified",
      });
      await db.collection("users").doc(OWNER).set({
        homeCountryCode: "br",
        countryCode: "br",
        name: "Owner",
        ageVerificationStatus: "verified",
      });
      await db.collection("users").doc(OTHER).set({
        homeCountryCode: "br",
        countryCode: "br",
        name: "Other",
        ageVerificationStatus: "verified",
      });
      await db.collection("groups").doc(GROUP_ID).set({
        name: "Teste de Grupo aberto",
        bio: "teste",
        avatarUrl: "https://example.com/a.png",
        country: "Brasil",
        countryCode: "br",
        city: "Navegantes",
        regionKey: "br_sc",
        scope: "city",
        ownerId: OWNER,
        admins: [OWNER],
        moderators: [],
        members: [OWNER],
        membersCount: 1,
        joinPolicy: "open",
        isPremiumGroup: false,
        isPrivate: false,
        deleted: false,
        isActive: true,
        inviteCode: "ABCD12",
        unread: { [OWNER]: 0 },
        lastMessage: "oi",
        lastSenderId: OWNER,
        updatedAt: new Date(),
      });
    });
  });

  // ---------- nenhum self-join direto é permitido ----------

  it("nega até self-join mínimo; somente joinOpenGroup/Admin SDK pode escrever", async () => {
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(validJoinPayload(), {
        merge: true,
      })
    );
  });

  it("nega append direto mesmo preservando a ordem", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("groups").doc(GROUP_ID).set(
        { members: [OWNER, OTHER], membersCount: 2 },
        { merge: true }
      );
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(
        {
          members: [OWNER, OTHER, JOINER],
          membersCount: 3,
          updatedAt: serverTimestamp(),
        },
        { merge: true }
      )
    );
  });

  it("nega write direto com premiumUntil:null sem depender de avaliação Premium", async () => {
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(validJoinPayload(), {
        merge: true,
      })
    );
  });

  // ---------- ofensivos: campos protegidos ----------

  const protectedFields = {
    name: "Hacked",
    bio: "hack",
    avatarUrl: "https://evil.com/x.png",
    inviteCode: "HACK99",
    joinPolicy: "inviteOnly",
    scope: "world",
    country: "Canada",
    countryCode: "ca",
    city: "Toronto",
    regionKey: "ca_on",
    isPremiumGroup: true,
    isPrivate: true,
    ownerId: JOINER,
    admins: [OWNER, JOINER],
    moderators: [JOINER],
    deleted: true,
    isActive: false,
    lastMessage: "pwned",
    lastSenderId: JOINER,
    unread: { [OWNER]: 0, [JOINER]: 0, [OTHER]: 99 },
  };

  Object.entries(protectedFields).forEach(([field, value]) => {
    it(`nega self-join que também altera ${field}`, async () => {
      const db = testEnv.authenticatedContext(JOINER).firestore();
      await assertFails(
        db.collection("groups").doc(GROUP_ID).set(
          validJoinPayload({ [field]: value }),
          { merge: true }
        )
      );
    });
  });

  it("nega alteração de unread (mapa de outros usuários)", async () => {
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(
        validJoinPayload({
          unread: { [OWNER]: 999, [JOINER]: 0 },
        }),
        { merge: true }
      )
    );
  });

  it("nega updatedAt arbitrário (não é serverTimestamp/request.time)", async () => {
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(
        {
          members: [OWNER, JOINER],
          membersCount: 2,
          updatedAt: new Date("2020-01-01T00:00:00Z"),
        },
        { merge: true }
      )
    );
  });

  it("nega join sem updatedAt", async () => {
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(
        {
          members: [OWNER, JOINER],
          membersCount: 2,
        },
        { merge: true }
      )
    );
  });

  // ---------- members / count ----------

  it("nega inserir o próprio uid no meio (exige append no final)", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("groups").doc(GROUP_ID).set(
        { members: [OWNER, OTHER], membersCount: 2 },
        { merge: true }
      );
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(
        {
          members: [OWNER, JOINER, OTHER],
          membersCount: 3,
          updatedAt: serverTimestamp(),
        },
        { merge: true }
      )
    );
  });

  it("nega reordenar members e inserir no meio", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("groups").doc(GROUP_ID).set(
        { members: [OWNER, OTHER], membersCount: 2 },
        { merge: true }
      );
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(
        {
          members: [OTHER, JOINER, OWNER],
          membersCount: 3,
          updatedAt: serverTimestamp(),
        },
        { merge: true }
      )
    );
  });

  it("nega remover membro existente", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("groups").doc(GROUP_ID).set(
        { members: [OWNER, OTHER], membersCount: 2 },
        { merge: true }
      );
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(
        {
          members: [OWNER, JOINER],
          membersCount: 2,
          updatedAt: serverTimestamp(),
        },
        { merge: true }
      )
    );
  });

  it("nega substituir membro existente", async () => {
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(
        {
          members: [JOINER],
          membersCount: 1,
          updatedAt: serverTimestamp(),
        },
        { merge: true }
      )
    );
  });

  it("nega acrescentar uid que não é o próprio", async () => {
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(
        {
          members: [OWNER, OTHER],
          membersCount: 2,
          updatedAt: serverTimestamp(),
        },
        { merge: true }
      )
    );
  });

  it("nega UID duplicado na lista", async () => {
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(
        {
          members: [OWNER, JOINER, JOINER],
          membersCount: 3,
          updatedAt: serverTimestamp(),
        },
        { merge: true }
      )
    );
  });

  it("nega membersCount divergente do tamanho de members", async () => {
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(
        {
          members: [OWNER, JOINER],
          membersCount: 99,
          updatedAt: serverTimestamp(),
        },
        { merge: true }
      )
    );
  });

  it("nega membersCount stale (simula corrida: count errado)", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("groups").doc(GROUP_ID).set(
        { members: [OWNER, OTHER], membersCount: 2 },
        { merge: true }
      );
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    // Cliente com snapshot antigo (members=[OWNER]) tentaria count=2
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(
        {
          members: [OWNER, JOINER],
          membersCount: 2,
          updatedAt: serverTimestamp(),
        },
        { merge: true }
      )
    );
  });

  it("já membro não consegue re-write (idempotência)", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("groups").doc(GROUP_ID).set(
        { members: [OWNER, JOINER], membersCount: 2 },
        { merge: true }
      );
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(
        {
          members: [OWNER, JOINER],
          membersCount: 2,
          updatedAt: serverTimestamp(),
        },
        { merge: true }
      )
    );
  });

  // ---------- ban / país / premium ----------

  it("nega banido (fail-closed com isActive true)", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("groups")
        .doc(GROUP_ID)
        .collection("bannedUsers")
        .doc(JOINER)
        .set({ isActive: true });
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(validJoinPayload(), {
        merge: true,
      })
    );
  });

  it("fail-closed: ban doc sem isActive ainda bloqueia", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("groups")
        .doc(GROUP_ID)
        .collection("bannedUsers")
        .doc(JOINER)
        .set({ reason: "x" });
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(validJoinPayload(), {
        merge: true,
      })
    );
  });

  it("desbanido também não pode fazer write direto", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .collection("groups")
        .doc(GROUP_ID)
        .collection("bannedUsers")
        .doc(JOINER)
        .set({ isActive: false });
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(validJoinPayload(), {
        merge: true,
      })
    );
  });

  it("Free internacional bloqueado server-side", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("groups").doc(GROUP_ID).set(
        { countryCode: "ca", isPremiumGroup: false },
        { merge: true }
      );
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(validJoinPayload(), {
        merge: true,
      })
    );
  });

  it("premiumUntil:null NÃO libera internacional", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection("groups").doc(GROUP_ID).set(
        { countryCode: "ca" },
        { merge: true }
      );
      await db.collection("users").doc(JOINER).set(
        { isPremium: true, premiumUntil: null },
        { merge: true }
      );
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(validJoinPayload(), {
        merge: true,
      })
    );
  });

  it("Premium expirado NÃO libera internacional", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection("groups").doc(GROUP_ID).set(
        { countryCode: "ca" },
        { merge: true }
      );
      await db.collection("users").doc(JOINER).set(
        {
          isPremium: true,
          premiumUntil: Timestamp.fromDate(new Date("2020-01-01T00:00:00Z")),
        },
        { merge: true }
      );
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(validJoinPayload(), {
        merge: true,
      })
    );
  });

  it("Premium futuro também não pode fazer write direto", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection("groups").doc(GROUP_ID).set(
        { countryCode: "ca" },
        { merge: true }
      );
      await db.collection("users").doc(JOINER).set(
        {
          isPremium: true,
          premiumUntil: Timestamp.fromMillis(Date.now() + 86400000 * 30),
        },
        { merge: true }
      );
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(validJoinPayload(), {
        merge: true,
      })
    );
  });

  it("Premium legado também não pode fazer write direto", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection("groups").doc(GROUP_ID).set(
        { countryCode: "ca" },
        { merge: true }
      );
      await db.collection("users").doc(JOINER).set(
        {
          homeCountryCode: "br",
          countryCode: "br",
          isPremium: true,
          premiumUntil: deleteField(),
          isMaster: deleteField(),
        },
        { merge: true }
      );
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(validJoinPayload(), {
        merge: true,
      })
    );
  });

  // ---------- grupo fechado / desativado / cheio / apagado ----------

  it("nega grupo approval (fechado)", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("groups").doc(GROUP_ID).set(
        { joinPolicy: "approval" },
        { merge: true }
      );
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(validJoinPayload(), {
        merge: true,
      })
    );
  });

  it("nega grupo inviteOnly", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("groups").doc(GROUP_ID).set(
        { joinPolicy: "inviteOnly" },
        { merge: true }
      );
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(validJoinPayload(), {
        merge: true,
      })
    );
  });

  it("nega grupo apagado", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("groups").doc(GROUP_ID).set(
        { deleted: true },
        { merge: true }
      );
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(validJoinPayload(), {
        merge: true,
      })
    );
  });

  it("nega grupo desativado (isActive:false)", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("groups").doc(GROUP_ID).set(
        { isActive: false },
        { merge: true }
      );
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(validJoinPayload(), {
        merge: true,
      })
    );
  });

  it("nega grupo cheio (maxMembers)", async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("groups").doc(GROUP_ID).set(
        { maxMembers: 1, members: [OWNER], membersCount: 1 },
        { merge: true }
      );
    });
    const db = testEnv.authenticatedContext(JOINER).firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(validJoinPayload(), {
        merge: true,
      })
    );
  });

  it("nega não autenticado", async () => {
    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      db.collection("groups").doc(GROUP_ID).set(validJoinPayload(), {
        merge: true,
      })
    );
  });
});
