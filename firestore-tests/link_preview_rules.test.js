/**
 * Firestore Rules — link preview (campos server-only + cache/rateLimits).
 * Roda com: firebase emulators:exec --only firestore "npm test -- --grep link-preview"
 * ou via npm test se incluído no package.json.
 */
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');
const { setLogLevel } = require('firebase/firestore');

const RULES_PATH = path.resolve(__dirname, '..', 'firestore.rules');
const PROJECT_ID = 'remdy-link-preview-rules-test';

let testEnv;

before(async () => {
  setLogLevel('error');
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

async function seedConversation() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc('conversations/c1').set({
      participants: ['alice', 'bob'],
      type: 'private',
    });
    await db.doc('conversations/c1/messages/m1').set({
      id: 'm1',
      type: 'text',
      text: 'hello https://example.com/',
      senderId: 'alice',
      createdAt: new Date(),
    });
  });
}

async function seedGroup() {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.doc('groups/g1').set({
      members: ['alice', 'bob'],
      admins: [],
      ownerId: 'alice',
      name: 'G',
    });
    await db.doc('groups/g1/messages/m1').set({
      id: 'm1',
      type: 'text',
      text: 'hello https://example.com/',
      senderId: 'alice',
      createdAt: new Date(),
    });
  });
}

describe('link-preview rules — server-only fields', () => {
  it('cliente não pode criar mensagem DM com linkPreview', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('conversations/c1').set({
        participants: ['alice', 'bob'],
        type: 'private',
      });
    });
    const db = authedDb('alice');
    await assertFails(
      db.doc('conversations/c1/messages/m_new').set({
        id: 'm_new',
        type: 'text',
        text: 'hi https://example.com/',
        senderId: 'alice',
        createdAt: new Date(),
        linkPreview: { title: 'x', url: 'https://example.com/' },
      })
    );
  });

  it('cliente não pode criar mensagem DM com linkPreviewStatus', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc('conversations/c1').set({
        participants: ['alice', 'bob'],
        type: 'private',
      });
    });
    const db = authedDb('alice');
    await assertFails(
      db.doc('conversations/c1/messages/m_new').set({
        id: 'm_new',
        type: 'text',
        text: 'hi https://example.com/',
        senderId: 'alice',
        createdAt: new Date(),
        linkPreviewStatus: 'ready',
      })
    );
  });

  it('cliente não pode atualizar linkPreview / linkPreviewStatus no DM', async () => {
    await seedConversation();
    const db = authedDb('alice');
    await assertFails(
      db.doc('conversations/c1/messages/m1').update({
        linkPreviewStatus: 'ready',
        linkPreview: { title: 'Forged' },
      })
    );
  });

  it('cliente não pode atualizar linkPreview no grupo', async () => {
    await seedGroup();
    const db = authedDb('alice');
    await assertFails(
      db.doc('groups/g1/messages/m1').update({
        linkPreview: { title: 'Forged' },
        linkPreviewStatus: 'ready',
      })
    );
  });

  it('cliente não lê nem escreve linkPreviewCache', async () => {
    const db = authedDb('alice');
    await assertFails(db.doc('linkPreviewCache/abc').get());
    await assertFails(
      db.doc('linkPreviewCache/abc').set({
        preview: { title: 'x' },
        status: 'ready',
        fetchedAtMs: Date.now(),
      })
    );
  });

  it('cliente não lê nem escreve _rateLimits', async () => {
    const db = authedDb('alice');
    await assertFails(db.doc('_rateLimits/linkPreview_alice').get());
    await assertFails(
      db.doc('_rateLimits/linkPreview_alice').set({
        windowStartMs: Date.now(),
        count: 1,
      })
    );
  });

  it('Admin SDK (rules disabled) pode escrever cache e rate limits', async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await assertSucceeds(
        db.doc('linkPreviewCache/abc').set({
          preview: { title: 'ok' },
          status: 'ready',
          fetchedAtMs: Date.now(),
        })
      );
      await assertSucceeds(
        db.doc('_rateLimits/linkPreview_alice').set({
          windowStartMs: Date.now(),
          count: 1,
        })
      );
    });
  });
});
