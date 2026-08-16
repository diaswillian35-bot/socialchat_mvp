/**
 * Callable sendDmMessage — envio Free sob franquia internacional (Admin SDK).
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const { executeSendDmMessage } = require("./send_dm_message_core");
const { assertVerifiedAdult } = require("./social_age_guard");

const sendDmMessage = onCall({ region: "us-central1" }, async (request) => {
  await assertVerifiedAdult(request, {
    getFirestore: () => admin.firestore(), HttpsError,
  });
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }
  try {
    return await executeSendDmMessage(
      admin.firestore(),
      request.auth.uid,
      request.data || {},
    );
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("sendDmMessage failed", e);
    throw new HttpsError("internal", "Send failed.");
  }
});

module.exports = { sendDmMessage };
