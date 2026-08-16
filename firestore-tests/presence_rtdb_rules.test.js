/**
 * Realtime Database Rules — presença (cliente só conexão).
 */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const RULES_PATH = path.resolve(__dirname, '..', 'database.rules.json');
const PROJECT_ID = 'remdy-rtdb-rules-test';
const DB_URL = 'http://127.0.0.1:9000?ns=remdy-rtdb-rules-test';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    database: {
      rules: fs.readFileSync(RULES_PATH, 'utf8'),
      host: '127.0.0.1',
      port: 9000,
    },
  });
});

after(async () => {
  if (testEnv) await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearDatabase();
});

function authedDb(uid) {
  return testEnv.authenticatedContext(uid).database(DB_URL);
}

describe('RTDB presence — conexão própria', () => {
  it('permite escrever a própria conexão (número)', async () => {
    const db = authedDb('alice');
    await assertSucceeds(
      db.ref('presence/alice/connections/c1').set(Date.now())
    );
  });

  it('bloqueia UID alheio', async () => {
    const db = authedDb('bob');
    await assertFails(
      db.ref('presence/alice/connections/c1').set(Date.now())
    );
  });

  it('bloqueia tipo inválido / dados privados na conexão', async () => {
    const db = authedDb('alice');
    await assertFails(
      db.ref('presence/alice/connections/c1').set({ email: 'x' })
    );
    await assertFails(db.ref('presence/alice/connections/c1').set('online'));
  });
});

describe('RTDB presence — índice/contadores só servidor', () => {
  it('bloqueia cliente em presenceIndex (país falso / múltiplos)', async () => {
    const db = authedDb('alice');
    await assertFails(
      db.ref('presenceIndex/byCountry/br/alice/c1').set(true)
    );
    await assertFails(
      db.ref('presenceIndex/byCountry/us/alice/c2').set(true)
    );
    await assertFails(
      db.ref('presenceIndex/byCountry/br/bob/c1').set(true)
    );
  });

  it('bloqueia cliente em presenceCounters', async () => {
    const db = authedDb('alice');
    await assertFails(db.ref('presenceCounters/world').set(99));
    await assertFails(db.ref('presenceCounters/byCountry/br').set(5));
  });

  it('bloqueia cliente em presenceOnline / presenceMeta', async () => {
    const db = authedDb('alice');
    await assertFails(db.ref('presenceOnline/alice').set({ c: 'us' }));
    await assertFails(db.ref('presenceMeta/alice').set({ countryCode: 'us' }));
  });

  it('bloqueia conexão alheia sob path de outro uid', async () => {
    const db = authedDb('alice');
    await assertFails(
      db.ref('presence/bob/connections/stolen').set(Date.now())
    );
  });

  it('admin/simulate server pode gravar counters (rules disabled)', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.database(DB_URL).ref('presenceCounters/world').set(1);
      await ctx
        .database(DB_URL)
        .ref('presenceCounters/byCountry/br')
        .set(1);
      await ctx
        .database(DB_URL)
        .ref('presenceOnline/alice')
        .set({ c: 'br' });
    });
    const db = authedDb('alice');
    await assertSucceeds(db.ref('presenceCounters/world').get());
    const snap = await db.ref('presenceCounters/world').get();
    assert.strictEqual(snap.val(), 1);
  });
});
