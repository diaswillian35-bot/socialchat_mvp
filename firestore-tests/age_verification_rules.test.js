const fs = require('fs');
const path = require('path');
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require('@firebase/rules-unit-testing');

const PROJECT_ID = 'remdy-age-rules-test';
let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, '..', 'firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => testEnv && testEnv.cleanup());
beforeEach(async () => testEnv.clearFirestore());

async function seed(uid, status) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().doc(`users/${uid}`).set({
      uid,
      ageVerificationStatus: status,
      dateOfBirth: new Date('1990-01-01T00:00:00Z'),
      ageVerifiedAt: status === 'verified' ? new Date() : null,
    });
  });
}

describe('age verification rules', () => {
  it('lets an unverified user read only their private gate document', async () => {
    await seed('pending', 'pending');
    const db = testEnv.authenticatedContext('pending').firestore();
    await assertSucceeds(db.doc('users/pending').get());
    await assertFails(db.doc('publicUsers/other').get());
  });

  it('keeps a rejected user blocked from representative social areas', async () => {
    await seed('rejected', 'rejected');
    const db = testEnv.authenticatedContext('rejected').firestore();
    await assertSucceeds(db.doc('users/rejected').get());
    await assertFails(db.doc('publicUsers/other').get());
    await assertFails(db.doc('conversations/c1').get());
    await assertFails(db.doc('groups/g1').get());
    await assertFails(db.doc('events/e1').get());
    await assertFails(db.doc('presenceCounters/world').get());
  });

  it('allows verified social access', async () => {
    await seed('adult', 'verified');
    const db = testEnv.authenticatedContext('adult').firestore();
    await assertSucceeds(db.doc('publicUsers/other').get());
  });

  it('prevents the client changing canonical age fields', async () => {
    await seed('adult', 'verified');
    const db = testEnv.authenticatedContext('adult').firestore();
    await assertFails(db.doc('users/adult').set({
      dateOfBirth: new Date('2000-01-01T00:00:00Z'),
    }, { merge: true }));
    await assertFails(db.doc('users/adult').set({
      ageVerificationStatus: 'rejected',
    }, { merge: true }));
    for (const field of [
      'ageVerifiedAt',
      'agePolicyVersion',
      'ageTermsAcceptedAt',
      'ageVerificationCheckedAt',
    ]) {
      await assertFails(db.doc('users/adult').set({
        [field]: field === 'agePolicyVersion' ? 'forged' : new Date(),
      }, { merge: true }));
    }
  });

  it('rejects exact age and birth date in publicUsers', async () => {
    await seed('adult', 'verified');
    const db = testEnv.authenticatedContext('adult').firestore();
    await assertFails(db.doc('publicUsers/adult').set({ uid: 'adult', age: 36 }));
    await assertFails(db.doc('publicUsers/adult').set({
      uid: 'adult', dateOfBirth: new Date('1990-01-01T00:00:00Z'),
    }));
  });
});
