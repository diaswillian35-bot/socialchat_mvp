/**
 * Firestore Rules — users/{uid} homeCountryCode + perfil + Premium/admin.
 * Roda com: firebase emulators:exec --only firestore "npm test"
 * (a partir desta pasta, com projectId dummy)
 */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const RULES_PATH = path.resolve(__dirname, '..', 'firestore.rules');
const PROJECT_ID = 'remdy-rules-test';

/** Payload alinhado a edit_profile_page.dart (completar perfil). */
function profilePayload(overrides = {}) {
  return {
    uid: 'user1',
    name: 'Willian',
    age: 30,
    languages: 'pt, en',
    about: 'Olá',
    country: 'Brasil',
    homeCountryCode: 'br',
    countryCode: 'br',
    stateName: 'SP',
    cityName: 'São Paulo',
    displayLocation: 'São Paulo, SP',
    lat: -23.55,
    lng: -46.63,
    nearbyEnabled: true,
    countryLocked: true,
    profileComplete: true,
    nativeLanguage: 'pt, en',
    ...overrides,
  };
}

function verifiedProfilePayload(overrides = {}) {
  return { ...profilePayload(overrides), ageVerificationStatus: 'verified' };
}

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
      host: '127.0.0.1',
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

function authedDb(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

function adminDb() {
  return testEnv.unauthenticatedContext().firestore();
}

describe('users/{uid} — homeCountryCode e perfil', () => {
  it('cria perfil completo com homeCountryCode na criação', async () => {
    const db = authedDb('user1');
    await assertSucceeds(
      db.doc('users/user1').set(profilePayload())
    );
  });

  it('completa perfil antigo sem homeCountryCode (primeira definição)', async () => {
    // Doc legado criado no login (sem o campo ou vazio).
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('users/user1').set({
        uid: 'user1',
        email: 'a@b.com',
        name: '',
        homeCountryCode: '',
        countryCode: '',
        countryLocked: false,
        isPremium: false,
        ageVerificationStatus: 'verified',
      });
    });

    const db = authedDb('user1');
    await assertSucceeds(
      db.doc('users/user1').set(profilePayload(), { merge: true })
    );

    const snap = await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const s = await ctx.firestore().doc('users/user1').get();
      assert.ok(s.exists);
      assert.strictEqual(s.data().homeCountryCode, 'br');
      assert.strictEqual(s.data().nearbyEnabled, true);
      assert.strictEqual(s.data().cityName, 'São Paulo');
    });
    void snap;
  });

  it('completa perfil antigo com homeCountryCode ausente (null/missing)', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('users/user1').set({
        uid: 'user1',
        name: 'Old',
        isPremium: false,
        ageVerificationStatus: 'verified',
      });
    });

    const db = authedDb('user1');
    await assertSucceeds(
      db.doc('users/user1').set(
        profilePayload({ homeCountryCode: 'ca', countryCode: 'ca', country: 'Canada' }),
        { merge: true }
      )
    );
  });

  it('atualiza perfil mantendo o mesmo país', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('users/user1').set(verifiedProfilePayload());
    });

    const db = authedDb('user1');
    await assertSucceeds(
      db.doc('users/user1').set(
        {
          name: 'Willian Dias',
          about: 'Bio nova',
          age: 31,
          languages: 'pt',
          cityName: 'Campinas',
          displayLocation: 'Campinas, SP',
          nearbyEnabled: false,
          homeCountryCode: 'br',
          countryCode: 'br',
        },
        { merge: true }
      )
    );
  });

  it('atualiza perfil mantendo o mesmo país com casing diferente', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('users/user1').set(verifiedProfilePayload());
    });

    const db = authedDb('user1');
    await assertSucceeds(
      db.doc('users/user1').set({ homeCountryCode: 'BR', name: 'X' }, { merge: true })
    );
  });

  it('bloqueia troca de país depois da primeira definição', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('users/user1').set(verifiedProfilePayload());
    });

    const db = authedDb('user1');
    await assertFails(
      db.doc('users/user1').set(
        { homeCountryCode: 'ca', countryCode: 'ca' },
        { merge: true }
      )
    );
  });

  it('permite atualizar campos do formulário sem tocar no país', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('users/user1').set(verifiedProfilePayload());
    });

    const db = authedDb('user1');
    await assertSucceeds(
      db.doc('users/user1').set(
        {
          name: 'Novo Nome',
          age: 28,
          cityName: 'Santos',
          languages: 'en',
          about: 'Nova bio',
          lat: -23.9,
          lng: -46.3,
          nearbyEnabled: true,
          displayLocation: 'Santos, SP',
        },
        { merge: true }
      )
    );
  });

  it('bloqueia alteração de isPremium', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('users/user1').set(verifiedProfilePayload());
    });

    const db = authedDb('user1');
    await assertFails(
      db.doc('users/user1').set({ isPremium: true }, { merge: true })
    );
  });

  it('bloqueia alteração de premiumUntil / premiumSource', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('users/user1').set(verifiedProfilePayload());
    });

    const db = authedDb('user1');
    await assertFails(
      db.doc('users/user1').set(
        {
          premiumUntil: new Date('2099-01-01'),
          premiumSource: 'invite',
          premiumType: 'trial',
        },
        { merge: true }
      )
    );
  });

  it('bloqueia alteração de isMaster / isBanned / role / permissions', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('users/user1').set(verifiedProfilePayload());
    });

    const db = authedDb('user1');
    await assertFails(
      db.doc('users/user1').set({ isMaster: true }, { merge: true })
    );
    await assertFails(
      db.doc('users/user1').set({ isBanned: true }, { merge: true })
    );
    await assertFails(
      db.doc('users/user1').set({ role: 'admin' }, { merge: true })
    );
    await assertFails(
      db.doc('users/user1').set({ permissions: { events: true } }, { merge: true })
    );
  });

  it('bloqueia create/update de isAdmin e isPlatformAdmin (forjáveis)', async () => {
    const db = authedDb('user1');
    await assertFails(
      db.doc('users/user1').set(profilePayload({ isAdmin: true }))
    );
    await assertFails(
      db.doc('users/user1').set(profilePayload({ isPlatformAdmin: true }))
    );
    await assertFails(
      db.doc('users/user1').set(profilePayload({ role: 'admin' }))
    );

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('users/user1').set(verifiedProfilePayload());
    });

    await assertFails(
      db.doc('users/user1').set({ isAdmin: true }, { merge: true })
    );
    await assertFails(
      db.doc('users/user1').set({ isPlatformAdmin: true }, { merge: true })
    );
    await assertFails(
      db.doc('users/user1').set({ role: 'admin' }, { merge: true })
    );
  });

  it('bloqueia escrita cliente em admins/{uid}', async () => {
    const db = authedDb('user1');
    await assertFails(
      db.doc('admins/user1').set({ role: 'admin' })
    );
  });

  it('bloqueia auto-concessão Premium na criação', async () => {
    const db = authedDb('user1');
    await assertFails(
      db.doc('users/user1').set(profilePayload({ isPremium: true }))
    );
    await assertFails(
      db.doc('users/user1').set(profilePayload({ isMaster: true }))
    );
  });

  it('bloqueia outro usuário de editar o perfil', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('users/user1').set(verifiedProfilePayload());
    });

    const db = authedDb('user2');
    await assertFails(
      db.doc('users/user1').set({ name: 'Hacker' }, { merge: true })
    );
  });
});
