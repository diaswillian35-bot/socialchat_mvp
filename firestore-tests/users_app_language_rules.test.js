/**
 * Firestore Rules — users/{uid}.appLanguageCode.
 * Auth mockada (authenticatedContext); sem login real.
 * Roda com o emulador Firestore (porta 8080).
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

function verifiedUser(overrides = {}) {
  return {
    uid: 'user1',
    name: 'Willian',
    isPremium: false,
    ageVerificationStatus: 'verified',
    homeCountryCode: 'br',
    countryCode: 'br',
    ...overrides,
  };
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

describe('users/{uid} — appLanguageCode', () => {
  it('o dono verificado pode fazer merge de um código canónico', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('users/user1').set(verifiedUser());
    });

    const db = authedDb('user1');
    for (const code of ['pt-BR', 'pt-PT', 'en', 'es', 'fr']) {
      await assertSucceeds(
        db.doc('users/user1').set({ appLanguageCode: code }, { merge: true })
      );
    }

    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const snap = await ctx.firestore().doc('users/user1').get();
      assert.ok(snap.exists);
      assert.strictEqual(snap.data().appLanguageCode, 'fr');
    });
  });

  it('não pede alteração nas demais regras só por gravar o idioma', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('users/user1').set(
        verifiedUser({ appLanguageCode: 'en' })
      );
    });

    const db = authedDb('user1');
    await assertSucceeds(
      db.doc('users/user1').set({ appLanguageCode: 'pt-BR' }, { merge: true })
    );
  });

  it('bloqueia outro utilizador de gravar appLanguageCode', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('users/user1').set(verifiedUser());
    });

    const db = authedDb('user2');
    await assertFails(
      db.doc('users/user1').set({ appLanguageCode: 'en' }, { merge: true })
    );
  });

  it('bloqueia anónimo de gravar appLanguageCode', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('users/user1').set(verifiedUser());
    });

    const db = testEnv.unauthenticatedContext().firestore();
    await assertFails(
      db.doc('users/user1').set({ appLanguageCode: 'en' }, { merge: true })
    );
  });
});

