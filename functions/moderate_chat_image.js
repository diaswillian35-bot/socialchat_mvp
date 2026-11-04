/**
 * SafeSearch ao finalizar objeto em chat_images/** e groups/{id}/images/**.
 * Região: northamerica-northeast1. O bucket é declarado para o trigger.
 * Uma chamada por imagem, por gs://, sem baixar o arquivo.
 * Falha da API: não bloqueia; marca unchecked e pede retry (máx. 3).
 */

const { onObjectFinalized } = require("firebase-functions/v2/storage");
const admin = require("firebase-admin");
const { loadModerationConfig } = require("./moderation/config");
const {
  decideSafeSearch,
  isModeratedImagePath,
  isImageContentType,
  pathHash,
  quarantinePath,
  confirmedUploader,
  contextFromPath,
  storagePathFromImageUrl,
  uncheckedOutcome,
  isTemporaryVisionError,
} = require("./moderation/image_policy");
const { applyContentBlock, markMessageModeration } = require("./moderation/apply_block");
const { safeModerationLog } = require("./moderation/safe_log");

const REGION = "northamerica-northeast1";
const BUCKET = "socialchatmvp.firebasestorage.app";

async function annotateSafeSearch(gsUri) {
  const { GoogleAuth } = require("google-auth-library");
  const auth = new GoogleAuth({
    scopes: ["https://www.googleapis.com/auth/cloud-vision"],
  });
  const client = await auth.getClient();
  const res = await client.request({
    url: "https://vision.googleapis.com/v1/images:annotate",
    method: "POST",
    data: {
      requests: [
        {
          image: { source: { imageUri: gsUri } },
          features: [{ type: "SAFE_SEARCH_DETECTION" }],
        },
      ],
    },
  });
  const first = (res.data && res.data.responses && res.data.responses[0]) || {};
  if (first.error) {
    const err = new Error("vision_failed");
    err.code = first.error.code || "vision_failed";
    throw err;
  }
  return first.safeSearchAnnotation || {};
}

async function moveToQuarantine(bucket, filePath) {
  const dest = quarantinePath(filePath);
  const src = bucket.file(filePath);
  const [exists] = await src.exists();
  if (!exists) return dest;
  await src.copy(bucket.file(dest));
  await src.delete({ ignoreNotFound: true });
  return dest;
}

async function matchingMessages(db, filePath, metadata) {
  const ctx = contextFromPath(filePath);
  const messageId = String((metadata && metadata.messageId) || "").trim();
  const exactUrl = String((metadata && metadata.imageUrl) || "").trim();
  const hits = [];
  if (!ctx.parentId) return hits;
  const col = ctx.kind === "group"
    ? db.collection("groups").doc(ctx.parentId).collection("messages")
    : db.collection("conversations").doc(ctx.parentId).collection("messages");
  if (messageId) {
    const ref = col.doc(messageId);
    const snap = await ref.get();
    if (snap.exists) {
      hits.push({ ref, id: snap.id, kind: ctx.kind, parentId: ctx.parentId });
    }
  }
  if (!exactUrl) return hits;
  const snap = await col.where("imageUrl", "==", exactUrl).get();
  for (const doc of snap.docs) {
    if (hits.some((hit) => hit.id === doc.id)) continue;
    const url = String((doc.data() && doc.data().imageUrl) || "");
    if (url !== exactUrl) continue;
    if (storagePathFromImageUrl(url) !== filePath && messageId && doc.id !== messageId) {
      continue;
    }
    hits.push({ ref: doc.ref, id: doc.id, kind: ctx.kind, parentId: ctx.parentId });
  }
  return hits;
}

async function writePending(db, filePath, payload) {
  await db.collection("pendingModeration").doc(pathHash(filePath)).set({
    ...payload,
    pathHash: pathHash(filePath),
    at: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
}

async function bumpUnchecked(db, filePath) {
  const ref = db.collection("pendingModeration").doc(pathHash(filePath));
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const prev = (snap.exists && snap.data() && snap.data().attempts) || 0;
    const attempts = prev + 1;
    tx.set(ref, {
      status: "unchecked",
      action: "unchecked",
      reason: "vision_unavailable",
      attempts,
      pathHash: pathHash(filePath),
      at: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return attempts;
  });
}

/**
 * Núcleo testável. vision e bucket são injetáveis.
 */
async function runImageModeration(object, deps) {
  const filePath = String((object && object.name) || "");
  const contentType = object && object.contentType;
  if (!isModeratedImagePath(filePath)) return { skipped: true };
  if (!isImageContentType(contentType)) return { skipped: true };

  const db = deps.db;
  const cfg = await deps.loadConfig();
  if (!cfg.enabled) return { skipped: true, reason: "disabled" };

  const metadata = (object && object.metadata) || {};
  const uid = confirmedUploader(filePath, metadata);
  const hash = pathHash(filePath);
  const gsUri = `gs://${object.bucket || deps.bucketName}/${filePath}`;

  let annotation;
  try {
    annotation = await deps.annotate(gsUri);
  } catch (err) {
    const temporary = isTemporaryVisionError(err);
    const attempts = temporary ? await bumpUnchecked(db, filePath) : 0;
    const hits = await matchingMessages(db, filePath, metadata);
    for (const hit of hits) {
      await markMessageModeration(admin, db, {
        kind: hit.kind,
        parentId: hit.parentId,
        messageId: hit.id,
        uid,
        status: "unchecked",
        reason: temporary ? "vision_unavailable" : "vision_error",
        pathHash: hash,
      });
    }
    safeModerationLog("moderate_image", {
      decision: temporary ? "unchecked" : "vision_error",
      uid,
      pathHash: hash,
      attempts,
      reason: temporary ? "temporary" : "permanent",
      messageId: hits[0] ? hits[0].id : "",
      parentId: hits[0] ? hits[0].parentId : "",
    });
    if (temporary && uncheckedOutcome(attempts) === "retry") {
      const retryErr = new Error("vision_retry");
      retryErr.code = "vision_retry";
      throw retryErr;
    }
    return { status: "unchecked", attempts, temporary };
  }

  const decision = decideSafeSearch(annotation, cfg);
  safeModerationLog("moderate_image", {
    decision: decision.action,
    reason: decision.reason,
    uid,
    pathHash: hash,
  });

  if (decision.action === "allow") {
    await writePending(db, filePath, {
      status: "clean",
      action: "allow",
      reason: "",
      uid,
    });
    return { status: "allow" };
  }

  if (decision.action === "block") {
    if (deps.moveToQuarantine) await deps.moveToQuarantine(filePath);
    await writePending(db, filePath, {
      status: "blocked",
      action: "block",
      reason: decision.reason,
      uid,
    });
    const hits = await matchingMessages(db, filePath, metadata);
    for (const hit of hits) {
      await applyContentBlock(admin, db, {
        kind: hit.kind,
        parentId: hit.parentId,
        messageId: hit.id,
        uid,
        reason: decision.reason,
        clearImage: true,
        source: "auto_vision",
        pathHash: hash,
        config: cfg,
      });
    }
    return { status: "blocked", messages: hits.length };
  }

  await writePending(db, filePath, {
    status: "review",
    action: "review",
    reason: decision.reason,
    uid,
  });
  const hits = await matchingMessages(db, filePath, metadata);
  for (const hit of hits) {
    await markMessageModeration(admin, db, {
      kind: hit.kind,
      parentId: hit.parentId,
      messageId: hit.id,
      uid,
      status: "review",
      reason: decision.reason,
      pathHash: hash,
    });
  }
  const reportId = `auto_review_${hash}`.slice(0, 700);
  try {
    await db.collection("reports").doc(reportId).create({
      fromUid: "system",
      reportedUid: uid,
      reasonCode: decision.reason || "image_racy",
      reason: decision.reason || "image_racy",
      priority: "normal",
      status: "open",
      source: "auto_vision",
      contextType: "image_review",
      pathHash: hash,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (err) {
    if (!(err && (err.code === 6 || err.code === "already-exists"))) throw err;
  }
  return { status: "review", messages: hits.length };
}

const moderateChatImage = onObjectFinalized(
  {
    region: REGION,
    bucket: BUCKET,
    retry: true,
    memory: "256MiB",
    timeoutSeconds: 60,
  },
  async (event) => {
    const object = event.data || {};
    const bucket = admin.storage().bucket(object.bucket || BUCKET);
    await runImageModeration(object, {
      db: admin.firestore(),
      bucketName: object.bucket || BUCKET,
      loadConfig: () => loadModerationConfig(admin.firestore()),
      annotate: annotateSafeSearch,
      moveToQuarantine: (filePath) => moveToQuarantine(bucket, filePath),
    });
  },
);

module.exports = {
  moderateChatImage,
  runImageModeration,
  annotateSafeSearch,
  BUCKET,
  REGION,
};
