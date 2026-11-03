/**
 * onDocumentCreated reports/{id}.
 * Enriquece a denúncia, avisa o admin e aplica suspensão automática.
 * CSAM: preserva evidência em csamHolds e quarentena (sem exclusão).
 * Região: northamerica-northeast1.
 */

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const { loadModerationConfig } = require("./moderation/config");
const {
  decideReportAction,
  isCsamReport,
  isSystemReporter,
  rateLimitDocId,
} = require("./moderation/report_policy");
const {
  storagePathFromImageUrl,
  pathHash,
  quarantinePath,
  isModeratedImagePath,
} = require("./moderation/image_policy");
const { safeModerationLog } = require("./moderation/safe_log");
const { sendOpsNoticeIfReady } = require("./moderation/report_notice");

const REGION = "northamerica-northeast1";
const WINDOW_MS = 30 * 24 * 60 * 60 * 1000;

async function countDaily(db, fromUid, nowMs) {
  const ref = db.collection("moderationReportDaily").doc(rateLimitDocId(fromUid, nowMs));
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const next = ((snap.exists && snap.data() && snap.data().count) || 0) + 1;
    tx.set(ref, {
      count: next,
      fromUid,
      day: rateLimitDocId(fromUid, nowMs).split("_").pop(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    return next;
  });
}

async function distinctReporters(db, reportedUid, fromUid) {
  if (!reportedUid || isSystemReporter(fromUid)) {
    const existing = await db
      .collection("moderationReporters")
      .doc(reportedUid || "_")
      .collection("uids")
      .where("lastAtMs", ">=", Date.now() - WINDOW_MS)
      .get();
    return existing.size;
  }
  const ref = db
    .collection("moderationReporters")
    .doc(reportedUid)
    .collection("uids")
    .doc(fromUid);
  await ref.set({
    lastAtMs: Date.now(),
    lastAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  const snap = await db
    .collection("moderationReporters")
    .doc(reportedUid)
    .collection("uids")
    .where("lastAtMs", ">=", Date.now() - WINDOW_MS)
    .get();
  return snap.size;
}

async function preserveCsam(db, report, reportId, options = {}) {
  const wipeMessage = options.wipeMessage === true;
  const deleteOriginal = options.deleteOriginal === true;
  const hold = {
    reportId,
    reportedUid: String(report.reportedUid || ""),
    conversationId: String(report.conversationId || ""),
    groupId: String(report.groupId || ""),
    messageId: String(report.messageId || ""),
    legalHold: true,
    at: admin.firestore.FieldValue.serverTimestamp(),
  };
  let messageRef = null;
  if (report.conversationId && report.messageId) {
    messageRef = db
      .collection("conversations")
      .doc(String(report.conversationId))
      .collection("messages")
      .doc(String(report.messageId));
  } else if (report.groupId && report.messageId) {
    messageRef = db
      .collection("groups")
      .doc(String(report.groupId))
      .collection("messages")
      .doc(String(report.messageId));
  }
  if (messageRef) {
    const snap = await messageRef.get();
    if (snap.exists) {
      const data = snap.data() || {};
      const text = String(data.text || "");
      const imageUrl = String(data.imageUrl || "");
      const filePath = storagePathFromImageUrl(imageUrl);
      if (text) hold.text = text;
      if (filePath) {
        hold.storagePath = filePath;
        hold.pathHash = pathHash(filePath);
        if (isModeratedImagePath(filePath) || filePath.startsWith("chat_images/") || filePath.startsWith("groups/")) {
          const bucket = admin.storage().bucket();
          const src = bucket.file(filePath);
          const [exists] = await src.exists();
          if (exists) {
            await src.copy(bucket.file(quarantinePath(filePath)));
            if (deleteOriginal) {
              await src.delete({ ignoreNotFound: true });
            }
          }
          await db.collection("quarantineHolds").doc(pathHash(filePath)).set({
            legalHold: true,
            reason: "csam",
            pathHash: pathHash(filePath),
            at: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        }
      }
      if (wipeMessage) {
        await messageRef.set({
          text: "",
          imageUrl: "",
          moderation: {
            status: "blocked",
            reason: "csam",
            at: admin.firestore.FieldValue.serverTimestamp(),
          },
        }, { merge: true });
      }
    }
  }
  await db.collection("csamHolds").doc(reportId).set(hold, { merge: true });
  safeModerationLog("csam_hold", {
    decision: "preserved",
    reportId,
    uid: String(report.reportedUid || ""),
    pathHash: hold.pathHash || "",
    messageId: hold.messageId,
    conversationId: hold.conversationId,
    groupId: hold.groupId,
  });
}

async function handleReportCreated(reportId, report) {
  const db = admin.firestore();
  const cfg = await loadModerationConfig(db);
  if (!cfg.enabled || !report) return;

  const fromUid = String(report.fromUid || "").trim();
  const reportedUid = String(report.reportedUid || "").trim();
  let dailyCount = 0;
  if (!isSystemReporter(fromUid)) {
    dailyCount = await countDaily(db, fromUid, Date.now());
  }
  const overLimit = decideReportAction({
    report,
    reportedUid,
    dailyCount,
    distinctReporters: 0,
    strikes: 0,
    config: cfg,
  });
  if (overLimit.ignore) {
    await db.collection("reports").doc(reportId).set({
      reportedUid,
      ignoredRateLimit: true,
      moderationEnrichedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    safeModerationLog("report_created", {
      decision: "ignored_rate_limit",
      reportId,
      uid: reportedUid,
      reason: "rate_limit",
    });
    return;
  }
  const distinct = reportedUid
    ? await distinctReporters(db, reportedUid, fromUid)
    : 0;
  let strikes = 0;
  if (reportedUid) {
    const strikeSnap = await db.collection("moderationStrikes").doc(reportedUid).get();
    strikes = (strikeSnap.exists && strikeSnap.data() && strikeSnap.data().count) || 0;
  }
  const decision = decideReportAction({
    report,
    reportedUid,
    dailyCount,
    distinctReporters: distinct,
    strikes,
    config: cfg,
  });

  await db.collection("reports").doc(reportId).set({
    reportedUid,
    distinctReporterCount: distinct,
    priority: decision.priority,
    ignoredRateLimit: decision.ignore === true,
    moderationEnrichedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  safeModerationLog("report_created", {
    decision: decision.ignore ? "ignored_rate_limit" : "enriched",
    reportId,
    uid: reportedUid,
    reason: decision.priority,
    attempts: distinct,
  });

  if (decision.ignore) return;

  if (decision.csam) {
    await preserveCsam(db, report, reportId, {
      wipeMessage: decision.systemCsam === true,
      deleteOriginal: decision.systemCsam === true,
    });
  }

  if (decision.suspend && reportedUid) {
    await db.collection("users").doc(reportedUid).set({
      moderation: {
        status: "suspended_pending_review",
        at: admin.firestore.FieldValue.serverTimestamp(),
        reason: decision.csam ? "csam_report" : "report_threshold",
      },
    }, { merge: true });
    safeModerationLog("moderation_suspend", {
      decision: "suspended_pending_review",
      uid: reportedUid,
      reportId,
      reason: decision.csam ? "csam" : "threshold",
    });
  }

  await sendOpsNoticeIfReady({
    db,
    messaging: admin.messaging(),
    title: "Nova denúncia",
    body: decision.body,
    data: {
      reportId,
      reportedUid,
      priority: decision.priority,
    },
  });
}

const onReportCreated = onDocumentCreated(
  {
    document: "reports/{reportId}",
    region: REGION,
  },
  async (event) => {
    const report = event.data ? event.data.data() : null;
    await handleReportCreated(event.params.reportId, report);
  },
);

module.exports = {
  onReportCreated,
  handleReportCreated,
};
