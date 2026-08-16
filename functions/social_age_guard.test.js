"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  assertVerifiedAdult,
  isVerifiedAdultData,
  verifiedAdultOnCall,
} = require("./social_age_guard");

class FakeHttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function deps(data, exists = true) {
  return {
    HttpsError: FakeHttpsError,
    getFirestore: () => ({
      collection: () => ({
        doc: () => ({
          get: async () => ({ exists, data: () => data }),
        }),
      }),
    }),
  };
}

test("verified status is the only accepted status", () => {
  assert.equal(isVerifiedAdultData({ ageVerificationStatus: "verified" }), true);
  assert.equal(isVerifiedAdultData({ ageVerificationStatus: "pending" }), false);
  assert.equal(isVerifiedAdultData({ ageVerificationStatus: "rejected" }), false);
  assert.equal(isVerifiedAdultData({ isPremium: true }), false);
});

test("guard rejects unauthenticated, missing, pending, rejected, and Premium", async () => {
  await assert.rejects(() => assertVerifiedAdult({}, deps({})),
    (error) => error.code === "unauthenticated");
  await assert.rejects(() => assertVerifiedAdult(
    { auth: { uid: "missing" } }, deps(null, false)),
  (error) => error.code === "permission-denied");
  for (const data of [
    { ageVerificationStatus: "pending" },
    { ageVerificationStatus: "rejected" },
    { isPremium: true, ageVerificationStatus: "pending" },
  ]) {
    await assert.rejects(() => assertVerifiedAdult(
      { auth: { uid: "u1" } }, deps(data)),
    (error) => error.code === "permission-denied");
  }
});

test("guard returns verified uid and data", async () => {
  const data = { ageVerificationStatus: "verified", isPremium: false };
  const result = await assertVerifiedAdult(
    { auth: { uid: "adult" } }, deps(data));
  assert.deepEqual(result, { uid: "adult", userData: data });
});

test("modified client cannot reach wrapped handler before verification", async () => {
  let handlerCalls = 0;
  const fakeOnCall = (_options, handler) => handler;
  const wrapped = verifiedAdultOnCall(
    fakeOnCall,
    { region: "test" },
    async () => { handlerCalls++; return { ok: true }; },
    deps({ ageVerificationStatus: "pending", isPremium: true }),
  );
  await assert.rejects(
    () => wrapped({ auth: { uid: "modified-client" }, data: {} }),
    (error) => error.code === "permission-denied",
  );
  assert.equal(handlerCalls, 0);
});
