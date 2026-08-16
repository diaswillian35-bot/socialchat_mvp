/**
 * Firestore Rules — presenceState / counters / checkpoint (server-only write).
 */
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const RULES_PATH = path.resolve(__dirname, '..', 'firestore.rules');
const PROJECT_ID = 'remdy-presence-counters-rules';

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
  });
});

function authedDb(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

describe('presenceState / presenceCounters rules', () => {
  it('cliente autenticado pode ler counters; não escrever', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('presenceCounters/world').set({ count: 1 });
      await ctx.firestore().doc('presenceState/alice').set({ online: true });
    });
    const db = authedDb('alice');
    await assertSucceeds(db.doc('presenceCounters/world').get());
    await assertFails(db.doc('presenceCounters/world').set({ count: 99 }));
    await assertFails(
      db.doc('presenceState/alice').set({ online: false })
    );
  });

  it('checkpoint inacessível ao cliente', async () => {
    const db = authedDb('alice');
    await assertFails(
      db.doc('presenceReconcileCheckpoint/main').get()
    );
    await assertFails(
      db.doc('presenceReconcileCheckpoint/main').set({ cursor: 'x' })
    );
  });
});
