"use strict";

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { httpsError } = require("./i18n/httpsError");
const admin = require("firebase-admin");
const {
  POLICY_VERSION,
  validateAdultDate,
} = require("./age_verification_logic");
const {
  notifyOpsAdminOfNewVerifiedUser,
} = require("./ops_new_user_notify");

async function confirmAdultAgeHandler(request) {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw httpsError("unauthenticated", "Authentication required.");
  const input = request.data || {};
  if (input.policyVersion !== POLICY_VERSION) {
    throw httpsError("failed-precondition", "Policy version is outdated.");
  }
  const result = validateAdultDate(input.dateOfBirth, new Date());
  if (!result.valid) throw httpsError("invalid-argument", "Invalid date of birth.");

  const ref = admin.firestore().collection("users").doc(uid);
  const timestamp = admin.firestore.Timestamp.fromDate(result.dateOfBirth);
  let priorStatus = "";
  let newlyAdultVerified = false;
  let userDataAfter = null;

  await admin.firestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = snap.data() || {};
    priorStatus = (current.ageVerificationStatus || "").toString().trim();
    const priorBirth = current.dateOfBirth;
    if (priorStatus === "verified" || priorStatus === "rejected") {
      const sameBirth = priorBirth && priorBirth.toMillis &&
        priorBirth.toMillis() === timestamp.toMillis();
      if (!sameBirth) {
        throw httpsError("failed-precondition",
          "Date of birth can only be corrected through support.");
      }
      if (priorStatus === "rejected") {
        throw httpsError("permission-denied", "Remdy is only for adults.");
      }
      userDataAfter = current;
      newlyAdultVerified = false;
      return;
    }

    const now = admin.firestore.FieldValue.serverTimestamp();
    const patch = {
      uid,
      dateOfBirth: timestamp,
      ageVerificationStatus: result.adult ? "verified" : "rejected",
      agePolicyVersion: POLICY_VERSION,
      ageTermsAcceptedAt: now,
      ageVerifiedAt: result.adult ? now : null,
      ageVerificationCheckedAt: now,
      updatedAt: now,
    };
    tx.set(ref, patch, { merge: true });
    newlyAdultVerified = result.adult === true;
    userDataAfter = { ...current, ...patch, homeCountryCode: current.homeCountryCode };
  });
  if (!result.adult) {
    throw httpsError("permission-denied", "Remdy is only for adults.");
  }

  if (newlyAdultVerified) {
    try {
      await notifyOpsAdminOfNewVerifiedUser({
        newUid: uid,
        userData: userDataAfter || {},
        priorStatus,
        newlyAdultVerified: true,
      });
    } catch (e) {
      console.warn(
        JSON.stringify({
          action: "ops_new_user_notify_error",
          uid,
          message: (e && e.message) || "unknown",
        }),
      );
    }
  }

  return { verified: true, policyVersion: POLICY_VERSION };
}

const confirmAdultAge = onCall(
  { region: "us-central1" },
  confirmAdultAgeHandler,
);

module.exports = { confirmAdultAge, confirmAdultAgeHandler };
