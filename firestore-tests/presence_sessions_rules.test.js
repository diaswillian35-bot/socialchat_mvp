/**
 * Firestore Rules — presença (sessions + agregado publicUsers).
 * Roda com: firebase emulators:exec --only firestore "npm test"
 * a partir de firestore-tests/
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
const PROJECT_ID = 'remdy-presence-rules-test';

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
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc('users/alice').set({ ageVerificationStatus: 'verified' });
    await ctx.firestore().doc('users/bob').set({ ageVerificationStatus: 'verified' });
  });
});

function authedDb(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

function sessionPayload(uid, sessionId, overrides = {}) {
  return {
    uid,
    sessionId,
    isOnline: true,
    lastSeenAt: new Date(),
    updatedAt: new Date(),
    platform: 'android',
    ...overrides,
  };
}

describe('publicUsers/{uid}/sessions — presença', () => {
  it('permite escrever a própria sessão com campos válidos', async () => {
    const db = authedDb('alice');
    await assertSucceeds(
      db.doc('publicUsers/alice/sessions/s1').set(sessionPayload('alice', 's1'))
    );
  });

  it('bloqueia escrita em sessão de outro UID', async () => {
    const db = authedDb('bob');
    await assertFails(
      db.doc('publicUsers/alice/sessions/s1').set(sessionPayload('alice', 's1'))
    );
  });

  it('bloqueia uid falsificado na própria path', async () => {
    const db = authedDb('alice');
    await assertFails(
      db
        .doc('publicUsers/alice/sessions/s1')
        .set(sessionPayload('alice', 's1', { uid: 'bob' }))
    );
  });

  it('bloqueia sessionId divergente do path', async () => {
    const db = authedDb('alice');
    await assertFails(
      db
        .doc('publicUsers/alice/sessions/s1')
        .set(sessionPayload('alice', 's1', { sessionId: 'other' }))
    );
  });

  it('bloqueia campos inválidos / extras', async () => {
    const db = authedDb('alice');
    await assertFails(
      db.doc('publicUsers/alice/sessions/s1').set({
        ...sessionPayload('alice', 's1'),
        hack: true,
      })
    );
    await assertFails(
      db.doc('publicUsers/alice/sessions/s1').set(
        sessionPayload('alice', 's1', { isOnline: 'yes' })
      )
    );
    await assertFails(
      db.doc('publicUsers/alice/sessions/s1').set(
        sessionPayload('alice', 's1', { platform: 123 })
      )
    );
  });

  it('bloqueia leitura de sessões de outro usuário', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx
        .firestore()
        .doc('publicUsers/alice/sessions/s1')
        .set(sessionPayload('alice', 's1'));
    });
    const bob = authedDb('bob');
    await assertFails(bob.doc('publicUsers/alice/sessions/s1').get());
  });
});

describe('publicUsers agregado — isOnline:false', () => {
  it('cliente não pode forçar isOnline false no update', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('publicUsers/alice').set({
        uid: 'alice',
        isOnline: true,
        name: 'Alice',
      });
    });
    const db = authedDb('alice');
    await assertFails(
      db.doc('publicUsers/alice').update({ isOnline: false })
    );
  });

  it('cliente pode renovar isOnline true', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('publicUsers/alice').set({
        uid: 'alice',
        isOnline: false,
        name: 'Alice',
      });
    });
    const db = authedDb('alice');
    await assertSucceeds(
      db.doc('publicUsers/alice').update({ isOnline: true })
    );
  });

  it('cliente não escreve sessão alheia nem campos protegidos de grupo via sessions', async () => {
    const db = authedDb('alice');
    await assertFails(
      db.doc('publicUsers/bob/sessions/x').set(sessionPayload('bob', 'x'))
    );
  });
});
