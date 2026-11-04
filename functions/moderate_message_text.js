/**
 * onDocumentCreated de mensagens DM e de grupo.
 * Região: northamerica-northeast1.
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const { loadModerationConfig } = require("./moderation/config");
const { evaluateText } = require("./moderation/text_filter");

function worseDecision(a, b) {
  const rank = { csam: 3, link_adult: 2, text_adult: 1 };
  if (!a) return b || null;
  if (!b) return a;
  return (rank[a.reason] || 0) >= (rank[b.reason] || 0) ? a : b;
}
const {
  storagePathFromImageUrl,
  pathHash,
} = require("./moderation/image_policy");
const { applyContentBlock, markMessageModeration } = require("./moderation/apply_block");
const { safeModerationLog } = require("./moderation/safe_log");

const REGION = "northamerica-northeast1";

function senderOf(data) {
  return String((data && (data.senderId || data.fromUid)) || "").trim();
}

async function moderateCreatedMessage(kind, parentId, messageId, data) {
  const db = admin.firestore();
  const cfg = await loadModerationConfig(db);
  if (!cfg.enabled || !data) return;

  const type = String(data.type || "text").trim().toLowerCase();
  const uid = senderOf(data);
  const textDecision = (type === "text" || type === "image")
    ? worseDecision(
      evaluateText(data.text || "", cfg),
      evaluateText(data.replyToText || "", cfg),
    )
    : null;

  if (type === "text") {
    if (!textDecision) {
      safeModerationLog("moderate_message", {
        decision: "allow",
        uid,
        messageId,
        parentId,
        ...(kind === "group" ? { groupId: parentId } : { conversationId: parentId }),
      });
      return;
    }
    await applyContentBlock(admin, db, {
      kind,
      parentId,
      messageId,
      uid,
      reason: textDecision.reason,
      clearText: true,
      source: "auto_text",
      config: cfg,
    });
    return;
  }

  if (type !== "image") return;
  const filePath = storagePathFromImageUrl(data.imageUrl || "");
  if (!filePath) {
    if (textDecision) {
      await applyContentBlock(admin, db, {
        kind,
        parentId,
        messageId,
        uid,
        reason: textDecision.reason,
        clearText: true,
        source: "auto_text",
        config: cfg,
      });
    }
    return;
  }
  const pendingSnap = await db.collection("pendingModeration").doc(pathHash(filePath)).get();
  if (!pendingSnap.exists) {
    if (textDecision) {
      await applyContentBlock(admin, db, {
        kind,
        parentId,
        messageId,
        uid,
        reason: textDecision.reason,
        clearText: true,
        source: "auto_text",
        config: cfg,
      });
    }
    return;
  }
  const pending = pendingSnap.data() || {};
  const action = String(pending.action || pending.status || "");
  if (action === "block" || pending.status === "blocked") {
    const imageUid = String(pending.uid || "");
    await applyContentBlock(admin, db, {
      kind,
      parentId,
      messageId,
      uid: textDecision ? uid : imageUid,
      reason: textDecision && textDecision.reason === "csam"
        ? "csam"
        : (pending.reason || "image_adult"),
      clearImage: true,
      clearText: Boolean(textDecision),
      source: textDecision ? "auto_text" : "auto_vision",
      pathHash: pathHash(filePath),
      config: cfg,
    });
    return;
  }
  if ((action === "review" || pending.status === "review") && !textDecision) {
    await markMessageModeration(admin, db, {
      kind,
      parentId,
      messageId,
      uid: String(pending.uid || ""),
      status: "review",
      reason: pending.reason || "image_racy",
      pathHash: pathHash(filePath),
    });
    return;
  }
  if (textDecision) {
    await applyContentBlock(admin, db, {
      kind,
      parentId,
      messageId,
      uid,
      reason: textDecision.reason,
      clearText: true,
      source: "auto_text",
      config: cfg,
    });
  }
  if (pending.status === "unchecked") {
    await markMessageModeration(admin, db, {
      kind,
      parentId,
      messageId,
      uid: pending.uid || uid,
      status: "unchecked",
      reason: "vision_unavailable",
      pathHash: pathHash(filePath),
    });
  }
}

const moderateMessageText = onDocumentCreated(
  {
    document: "conversations/{conversationId}/messages/{messageId}",
    region: REGION,
  },
  async (event) => {
    try {
      await moderateCreatedMessage(
        "dm",
        event.params.conversationId,
        event.params.messageId,
        event.data ? event.data.data() : null,
      );
    } catch (err) {
      safeModerationLog("moderate_message_error", {
        decision: "error",
        conversationId: event.params.conversationId,
        messageId: event.params.messageId,
        reason: "handler_failed",
      });
      throw err;
    }
  },
);

const moderateGroupMessageText = onDocumentCreated(
  {
    document: "groups/{groupId}/messages/{messageId}",
    region: REGION,
  },
  async (event) => {
    try {
      await moderateCreatedMessage(
        "group",
        event.params.groupId,
        event.params.messageId,
        event.data ? event.data.data() : null,
      );
    } catch (err) {
      safeModerationLog("moderate_message_error", {
        decision: "error",
        groupId: event.params.groupId,
        messageId: event.params.messageId,
        reason: "handler_failed",
      });
      throw err;
    }
  },
);

module.exports = {
  moderateMessageText,
  moderateGroupMessageText,
  moderateCreatedMessage,
};
