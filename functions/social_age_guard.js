"use strict";

const VERIFIED_STATUS = "verified";

function isVerifiedAdultData(data) {
  return !!data && data.ageVerificationStatus === VERIFIED_STATUS;
}

async function assertVerifiedAdultUid(uid, { getFirestore, HttpsError }) {
  if (!uid) {
    throw new HttpsError("unauthenticated", "Authentication required.");
  }
  const snap = await getFirestore().collection("users").doc(uid).get();
  if (!snap.exists || !isVerifiedAdultData(snap.data())) {
    throw new HttpsError(
      "permission-denied",
      "Adult age verification is required.",
    );
  }
  return { uid, userData: snap.data() };
}

async function assertVerifiedAdult(request, dependencies) {
  const uid = request && request.auth && request.auth.uid;
  return assertVerifiedAdultUid(uid, dependencies);
}

function verifiedAdultOnCall(onCall, options, handler, dependencies) {
  return onCall(options, async (request) => {
    await assertVerifiedAdult(request, dependencies);
    return handler(request);
  });
}

module.exports = {
  VERIFIED_STATUS,
  isVerifiedAdultData,
  assertVerifiedAdultUid,
  assertVerifiedAdult,
  verifiedAdultOnCall,
};
