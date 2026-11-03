/**
 * Aplica bloqueio de mensagem uma vez (strike + denúncia automática).
 * Não grava o texto original em log nem no documento de denúncia.
 */

const { safeModerationLog } = require("./safe_log");
const { nextStrikeEvents } = require("./strikes");

function serverNow(admin) {
  return admin.firestore.FieldValue.serverTimestamp();
}

async function applyContentBlock(admin, db, input) {
  const parentId = String(input.parentId || "");
  const messageId = String(input.messageId || "");
  const uid = String(input.uid || "");
  const reason = String(input.reason || "text_adult");
  const kind = input.kind === "group" ? "group" : "dm";
  if (!parentId || !messageId) return { applied: false };

  const markerRef = db.collection("moderationApplied").doc(`${parentId}_${messageId}`);
  const messageRef = kind === "group"
    ? db.collection("groups").doc(parentId).collection("messages").doc(messageId)
    : db.collection("conversations").doc(parentId).collection("messages").doc(messageId);

  const first = await db.runTransaction(async (tx) => {
    const marker = await tx.get(markerRef);
    if (marker.exists) return false;
    tx.set(markerRef, {
      reason,
      uid,
      at: serverNow(admin),
    });
    const patch = {
      moderation: {
        status: "blocked",
        reason,
        at: serverNow(admin),
      },
    };
    if (input.clearText) {
      patch.text = "";
      patch.replyToText = "";
    }
    if (input.clearImage) patch.imageUrl = "";
    patch.linkPreview = admin.firestore.FieldValue.delete();
    patch.linkPreviewStatus = admin.firestore.FieldValue.delete();
    tx.set(messageRef, patch, { merge: true });
    return true;
  });

  safeModerationLog("moderation_block", {
    decision: first ? "blocked" : "already_applied",
    reason,
    uid,
    messageId,
    parentId,
    source: input.source || "",
    pathHash: input.pathHash || "",
    ...(kind === "group" ? { groupId: parentId } : { conversationId: parentId }),
  });

  if (!first) return { applied: false };

  let strikes = 0;
  if (uid && input.confirmedUploader !== false) {
    const strikeRef = db.collection("moderationStrikes").doc(uid);
    const nowMs = Date.now();
    strikes = await db.runTransaction(async (tx) => {
      const snap = await tx.get(strikeRef);
      const prev = snap.exists && snap.data() ? snap.data().events : [];
      const events = nextStrikeEvents(prev, nowMs);
      tx.set(strikeRef, {
        count: events.length,
        events,
        updatedAt: serverNow(admin),
      }, { merge: true });
      return events.length;
    });
    const threshold = (input.config && input.config.strikeThreshold) || 3;
    if (strikes >= threshold) {
      await db.collection("users").doc(uid).set({
        moderation: {
          status: "suspended_pending_review",
          at: serverNow(admin),
          reason: "strikes",
        },
      }, { merge: true });
    }
  }

  const reportId = `auto_${reason}_${parentId}_${messageId}`.slice(0, 700);
  const report = {
    fromUid: "system",
    reportedUid: uid,
    reasonCode: reason,
    reason,
    priority: reason === "csam" ? "critical" : "normal",
    status: "open",
    source: input.source || "auto_text",
    contextType: kind === "group" ? "group_message" : "dm_message",
    messageId,
    createdAt: serverNow(admin),
  };
  if (kind === "group") report.groupId = parentId;
  else report.conversationId = parentId;
  if (reason === "csam") report.requiresChildSafetyReview = true;
  try {
    await db.collection("reports").doc(reportId).create(report);
  } catch (err) {
    const code = err && (err.code === 6 || err.code === "already-exists");
    if (!code) throw err;
  }

  return { applied: true, strikes };
}

async function markMessageModeration(admin, db, input) {
  const parentId = String(input.parentId || "");
  const messageId = String(input.messageId || "");
  const status = String(input.status || "");
  if (!parentId || !messageId || !status) return;
  const kind = input.kind === "group" ? "group" : "dm";
  const messageRef = kind === "group"
    ? db.collection("groups").doc(parentId).collection("messages").doc(messageId)
    : db.collection("conversations").doc(parentId).collection("messages").doc(messageId);
  await messageRef.set({
    moderation: {
      status,
      reason: String(input.reason || ""),
      at: serverNow(admin),
    },
  }, { merge: true });
  safeModerationLog("moderation_mark", {
    decision: status,
    reason: input.reason || "",
    uid: input.uid || "",
    messageId,
    parentId,
    pathHash: input.pathHash || "",
    ...(kind === "group" ? { groupId: parentId } : { conversationId: parentId }),
  });
}

module.exports = {
  applyContentBlock,
  markMessageModeration,
};
