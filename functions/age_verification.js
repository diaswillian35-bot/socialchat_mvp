"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {
  POLICY_VERSION,
  validateAdultDate,
} = require("./age_verification_logic");

async function confirmAdultAgeHandler(request) {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Authentication required.");
  const input = request.data || {};
  if (input.policyVersion !== POLICY_VERSION) {
    throw new HttpsError("failed-precondition", "Policy version is outdated.");
  }
  const result = validateAdultDate(input.dateOfBirth, new Date());
  if (!result.valid) throw new HttpsError("invalid-argument", "Invalid date of birth.");

  const ref = admin.firestore().collection("users").doc(uid);
  const timestamp = admin.firestore.Timestamp.fromDate(result.dateOfBirth);
  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = snap.data() || {};
    const priorStatus = current.ageVerificationStatus;
    const priorBirth = current.dateOfBirth;
    if (priorStatus === "verified" || priorStatus === "rejected") {
      const sameBirth = priorBirth && priorBirth.toMillis &&
        priorBirth.toMillis() === timestamp.toMillis();
      if (!sameBirth) {
        throw new HttpsError("failed-precondition",
          "Date of birth can only be corrected through support.");
      }
      if (priorStatus === "rejected") {
        throw new HttpsError("permission-denied", "Remdy is only for adults.");
      }
      return;
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    tx.set(ref, {
      uid,
      dateOfBirth: timestamp,
      ageVerificationStatus: result.adult ? "verified" : "rejected",
      agePolicyVersion: POLICY_VERSION,
      ageTermsAcceptedAt: now,
      ageVerifiedAt: result.adult ? now : null,
      ageVerificationCheckedAt: now,
      updatedAt: now,
    }, { merge: true });
  });
  if (!result.adult) {
    throw new HttpsError("permission-denied", "Remdy is only for adults.");
  }
  return { verified: true, policyVersion: POLICY_VERSION };
}

const confirmAdultAge = onCall(
  { region: "us-central1" },
  confirmAdultAgeHandler,
);

module.exports = { confirmAdultAge, confirmAdultAgeHandler };
