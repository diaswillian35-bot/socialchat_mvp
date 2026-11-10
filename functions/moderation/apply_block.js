/**
 * Aplica bloqueio de mensagem uma vez (strike + denúncia automática).
 * Não grava o texto original em log nem no documento de denúncia.
 */

const { safeModerationLog } = require("./safe_log");
const { nextStrikeEvents } = require("./strikes");
const { ladderConfig, ladderStep, moderationPatch } = require("./ladder");
const { pushNotice } = require("./notices");

/**
 * b44: soma 1 ponto (janela de 90 dias) e aplica o degrau:
 * 1 aviso, 2 = 24 h sem falar, 3 = 7 dias, 4 = banimento pendente.
 * CSAM vai direto para suspensão pendente (fora dos degraus).
 */
async function applyStrike(admin, db, uid, input = {}) {
  const cfg = input.config || {};
  const reason = String(input.reason || "");
  const nowMs = typeof input.nowMs === "number" ? input.nowMs : Date.now();
  const { windowMs } = ladderConfig(cfg);
  const strikeRef = db.collection("moderationStrikes").doc(uid);
  const userRef = db.collection("users").doc(uid);
  const result = await db.runTransaction(async (tx) => {
    const [snap, userSnap] = await Promise.all([tx.get(strikeRef), tx.get(userRef)]);
    const prev = snap.exists && snap.data() ? snap.data().events : [];
    const events = nextStrikeEvents(prev, nowMs, windowMs);
    tx.set(strikeRef, {
      count: events.length,
      events,
      lastReason: reason,
      updatedAt: serverNow(admin),
    }, { merge: true });
    const step = reason === "csam"
      ? { level: 4, action: "suspend" }
      : ladderStep(events.length, nowMs, cfg);
    const prevMod = userSnap.exists ? (userSnap.data() || {}).moderation : null;
    const p = moderationPatch(prevMod, step, nowMs);
    if (p) {
      const moderation = {
        status: p.status,
        level: p.level,
        reason: p.reason,
        at: serverNow(admin),
        mutedUntil: p.mutedUntilMs
          ? admin.firestore.Timestamp.fromMillis(p.mutedUntilMs)
          : admin.firestore.FieldValue.delete(),
      };
      tx.set(userRef, { moderation }, { merge: true });
    }
    return { points: events.length, step, patch: p };
  });
  if (result.patch && input.notify !== false) {
    const key = result.patch.status === "suspended_pending_review"
      ? "mod_banned_notice"
      : result.step.action === "mute"
        ? "mod_muted_notice"
        : "mod_warning_notice";
    await pushNotice(admin, db, uid, key,
      result.patch.mutedUntilMs ? { untilMs: result.patch.mutedUntilMs } : {});
  }
  safeModerationLog("moderation_strike", {
    decision: result.patch ? result.patch.status : "unchanged",
    reason,
    uid,
    attempts: result.points,
  });
  return result;
}

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
    if (input.botRemoval) {
      // b44: bot moderador remove a mensagem com o estilo de "apagada" que já existe.
      patch.deleted = true;
      patch.deletedBy = "remdy_bot";
      patch.deletedText = "";
      patch.text = "";
    }
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
    const r = await applyStrike(admin, db, uid, { reason, config: input.config });
    strikes = r.points;
  }

  if (input.skipReport) return { applied: true, strikes };

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
  applyStrike,
  applyContentBlock,
  markMessageModeration,
};
