/**
 * Núcleo testável de sendDmMessage (transação Admin SDK).
 * Usado pela Callable e pelos testes de concorrência no emulador.
 */
const { HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {
  authorizeFreeTextSend,
  validateRequestId,
  requiresReplyQuotaCallable,
  countCodePoints,
  IDEMPOTENCY_TTL_MS,
  REPLY_QUOTA_LIMIT,
} = require("./dm_reply_quota");

function asUidList(raw) {
  if (!Array.isArray(raw)) return [];
  return raw.map((x) => String(x || "").trim()).filter(Boolean);
}

function accountBlocked(userData = {}) {
  if (userData.isBanned === true) return "banned";
  if (userData.shadowBan === true) return "shadow_ban";
  if (
    userData.accountDeleted === true ||
    userData.deleted === true ||
    userData.isDeleted === true
  ) {
    return "deleted";
  }
  if (
    Object.prototype.hasOwnProperty.call(userData, "isActive") &&
    userData.isActive === false
  ) {
    return "disabled";
  }
  return null;
}

/**
 * @param {FirebaseFirestore.Firestore} db
 * @param {string} uid
 * @param {object} data conversationId, text, requestId, otherUid?, messageId?, reply*
 */
async function executeSendDmMessage(db, uid, data) {
  const conversationId = String(data.conversationId || "").trim();
  const text = data.text == null ? "" : String(data.text);
  const otherUidHint = String(data.otherUid || "").trim();
  const messageIdIn = String(data.messageId || "").trim();
  const requestIdCheck = validateRequestId(data.requestId);
  if (!requestIdCheck.ok) {
    throw new HttpsError("invalid-argument", "Invalid requestId.");
  }
  const requestId = requestIdCheck.requestId;

  if (!conversationId) {
    throw new HttpsError("invalid-argument", "conversationId required.");
  }

  const idemRef = db.collection("dmSendIdempotency").doc(`${uid}_${requestId}`);
  const idemSnap = await idemRef.get();
  if (idemSnap.exists) {
    const prev = idemSnap.data() || {};
    if (prev.ok === true) {
      return {
        ok: true,
        messageId: prev.messageId,
        conversationId: prev.conversationId || conversationId,
        replyQuota: prev.replyQuota || null,
        idempotentReplay: true,
      };
    }
  }

  const convRef = db.collection("conversations").doc(conversationId);
  const senderRef = db.collection("users").doc(uid);

  const resultPayload = await db.runTransaction(async (tx) => {
    const [convSnap, senderSnap, idemTx] = await Promise.all([
      tx.get(convRef),
      tx.get(senderRef),
      tx.get(idemRef),
    ]);

    if (idemTx.exists && idemTx.data()?.ok === true) {
      const prev = idemTx.data();
      return {
        ok: true,
        messageId: prev.messageId,
        conversationId,
        replyQuota: prev.replyQuota || null,
        idempotentReplay: true,
        skipWrite: true,
      };
    }

    if (!convSnap.exists) {
      throw new HttpsError("not-found", "Conversation not found.");
    }
    const conv = convSnap.data() || {};
    const participants = asUidList(conv.participants);
    if (!participants.includes(uid) || participants.length !== 2) {
      throw new HttpsError("permission-denied", "Not a participant.");
    }
    const otherUid =
      otherUidHint && participants.includes(otherUidHint)
        ? otherUidHint
        : participants.find((p) => p !== uid);
    if (!otherUid) {
      throw new HttpsError("failed-precondition", "Peer missing.");
    }

    const otherRef = db.collection("users").doc(otherUid);
    const otherSnap = await tx.get(otherRef);
    const senderData = senderSnap.data() || {};
    const otherData = otherSnap.data() || {};

    const blockedSelf = accountBlocked(senderData);
    if (
      blockedSelf === "banned" ||
      blockedSelf === "deleted" ||
      blockedSelf === "disabled"
    ) {
      throw new HttpsError("permission-denied", "Account not allowed.");
    }
    if (blockedSelf === "shadow_ban") {
      throw new HttpsError("permission-denied", "Temporarily silenced.");
    }
    if (accountBlocked(otherData)) {
      throw new HttpsError("failed-precondition", "Peer unavailable.");
    }

    const blockA = await tx.get(
      db.collection("users").doc(uid).collection("blocked").doc(otherUid),
    );
    const blockB = await tx.get(
      db.collection("users").doc(otherUid).collection("blocked").doc(uid),
    );
    if (blockA.exists || blockB.exists) {
      throw new HttpsError("permission-denied", "Blocked.");
    }

    // Re-read conv inside tx for latest replyQuota (concurrency).
    const convFresh = convSnap.data() || {};
    const authz = authorizeFreeTextSend({
      senderUid: uid,
      senderData,
      recipientData: otherData,
      existingQuota: convFresh.replyQuota,
      text,
      messageType: "text",
      recipientUid: otherUid,
    });

    if (!authz.ok) {
      const status =
        authz.code === "quota-exceeded"
          ? "resource-exhausted"
          : authz.code === "media-not-allowed" ||
              authz.code === "premium-required"
            ? "permission-denied"
            : "invalid-argument";
      throw new HttpsError(status, authz.message || "Send denied.", {
        code: authz.code,
        replyQuota: authz.quota || null,
      });
    }

    const msgRef = messageIdIn
      ? convRef.collection("messages").doc(messageIdIn)
      : convRef.collection("messages").doc();
    const msgId = msgRef.id;

    const existingMsg = await tx.get(msgRef);
    if (existingMsg.exists) {
      const rq = authz.quotaAfter
        ? {
            used: authz.quotaAfter.used,
            limit: authz.quotaAfter.limit,
            remaining: Math.max(
              0,
              authz.quotaAfter.limit - authz.quotaAfter.used,
            ),
          }
        : null;
      tx.set(
        idemRef,
        {
          ok: true,
          messageId: msgId,
          conversationId,
          replyQuota: rq,
          uid,
          createdAtMs: Date.now(),
          expireAtMs: Date.now() + IDEMPOTENCY_TTL_MS,
        },
        { merge: true },
      );
      return {
        ok: true,
        messageId: msgId,
        conversationId,
        replyQuota: rq,
        idempotentReplay: true,
        skipWrite: true,
      };
    }

    const replyToMessageId = data.replyToMessageId
      ? String(data.replyToMessageId).trim()
      : null;
    const msgData = {
      type: "text",
      text,
      senderId: uid,
      fromUid: uid,
      toUid: otherUid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      clientCreatedAt: admin.firestore.Timestamp.now(),
      deleted: false,
      deletedBy: "",
      deletedText: "",
      deletedAt: null,
      replyToMessageId: replyToMessageId || null,
      replyToText: String(data.replyToText || "").slice(0, 200),
      replyToType: String(data.replyToType || "text").slice(0, 20),
      replyToIsMe: data.replyToIsMe === true,
      replyToImageUrl: "",
    };

    tx.set(msgRef, msgData);

    const patch = {};
    if (authz.mode === "quota" && authz.quotaAfter) {
      patch.replyQuota = {
        version: authz.quotaAfter.version,
        enabled: true,
        freeUid: authz.quotaAfter.freeUid,
        initiatorUid: authz.quotaAfter.initiatorUid || "",
        limit: authz.quotaAfter.limit,
        used: authz.quotaAfter.used,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
    }
    if (Object.keys(patch).length) {
      tx.set(convRef, patch, { merge: true });
    }

    const rq = authz.quotaAfter
      ? {
          used: authz.quotaAfter.used,
          limit: authz.quotaAfter.limit,
          remaining: Math.max(
            0,
            authz.quotaAfter.limit - authz.quotaAfter.used,
          ),
        }
      : requiresReplyQuotaCallable(
            senderData,
            otherData,
            convFresh.replyQuota,
            uid,
          )
        ? { used: 0, limit: REPLY_QUOTA_LIMIT, remaining: REPLY_QUOTA_LIMIT }
        : null;

    tx.set(idemRef, {
      ok: true,
      messageId: msgId,
      conversationId,
      replyQuota: rq,
      uid,
      createdAtMs: Date.now(),
      expireAtMs: Date.now() + IDEMPOTENCY_TTL_MS,
      codePoints: countCodePoints(text),
    });

    return {
      ok: true,
      messageId: msgId,
      conversationId,
      replyQuota: rq,
      idempotentReplay: false,
    };
  });

  return {
    ok: true,
    messageId: resultPayload.messageId,
    conversationId: resultPayload.conversationId,
    replyQuota: resultPayload.replyQuota,
    idempotentReplay: !!resultPayload.idempotentReplay,
  };
}

module.exports = {
  executeSendDmMessage,
  asUidList,
  accountBlocked,
};
