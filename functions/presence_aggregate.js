/**
 * Agrega presença a partir de publicUsers/{uid}/sessions/{sessionId}.
 * Sessões = fonte verdadeira; o cliente não deve gravar isOnline:false no agregado.
 *
 * Deploy: firebase deploy --only functions:onPublicUserSessionWritten
 */
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const {
  computeAggregateFromSessions,
  ONLINE_WINDOW_MS,
} = require("./presence_aggregate_logic");

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} uid
 */
async function recomputePublicUserPresence(db, uid) {
  const sessionsSnap = await db
    .collection("publicUsers")
    .doc(uid)
    .collection("sessions")
    .orderBy("updatedAt", "desc")
    .limit(100)
    .get();

  const nowMs = Date.now();
  const { anyOnline, latestSeenMs } = computeAggregateFromSessions(
    sessionsSnap.docs,
    nowMs
  );

  const patch = {
    uid,
    isOnline: anyOnline,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (anyOnline && latestSeenMs != null) {
    patch.lastSeenAt = admin.firestore.Timestamp.fromMillis(latestSeenMs);
  }

  const batch = db.batch();
  batch.set(db.collection("publicUsers").doc(uid), patch, { merge: true });
  batch.set(
    db.collection("users").doc(uid),
    {
      isOnline: anyOnline,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...(anyOnline && latestSeenMs != null
        ? { lastSeenAt: admin.firestore.Timestamp.fromMillis(latestSeenMs) }
        : {}),
    },
    { merge: true }
  );
  await batch.commit();
  return { anyOnline, latestSeenMs, sessionCount: sessionsSnap.size };
}

const onPublicUserSessionWritten = onDocumentWritten(
  {
    document: "publicUsers/{uid}/sessions/{sessionId}",
    region: "us-central1",
  },
  async (event) => {
    const uid = event.params.uid;
    if (!uid) return null;
    const db = admin.firestore();
    try {
      return await recomputePublicUserPresence(db, uid);
    } catch (err) {
      console.error("onPublicUserSessionWritten", uid, err);
      throw err;
    }
  }
);

module.exports = {
  onPublicUserSessionWritten,
  computeAggregateFromSessions,
  recomputePublicUserPresence,
  ONLINE_WINDOW_MS,
};
