/**
 * forwardMessage — Admin SDK forward for DM/group (text, link+preview, image, audio).
 * Sender and all ACL checks come from Auth + server reads — never from client claims.
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {
  MAX_DESTINATIONS,
  IDEMPOTENCY_TTL_MS,
  RATE,
  evaluateRateLimit,
  accountBlocked,
  isPremiumUser,
  countryOf,
  canSendInternational,
  pairKey,
  normalizeDestinations,
  extractForwardableContent,
  callerCanReadMessage,
  isParticipating,
  idempotencyDocId,
  sanitizeLinkPreview,
} = require("./forward_message_logic");

const db = () => admin.firestore();

function requireAuth(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }
  return request.auth.uid;
}

async function bumpRate(uid) {
  const ref = db().collection("_rateLimits").doc(`forward_${uid}`);
  const now = Date.now();
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const next = evaluateRateLimit(
      snap.data() || {},
      now,
      RATE.forwardPerUid.max,
      RATE.forwardPerUid.windowMs,
    );
    if (!next.allowed) {
      throw new HttpsError("resource-exhausted", "Rate limit exceeded.");
    }
    tx.set(
      ref,
      {
        windowStartMs: next.windowStartMs,
        count: next.count,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  });
}

async function loadActiveUser(uid) {
  const snap = await db().collection("users").doc(uid).get();
  const data = snap.data() || {};
  const block = accountBlocked(data);
  if (block) throw new HttpsError("permission-denied", "Not allowed.");
  return data;
}

async function isEitherBlocked(uid, otherUid) {
  const [a, b] = await Promise.all([
    db().collection("users").doc(uid).get(),
    db().collection("users").doc(otherUid).get(),
  ]);
  const blockedA = Array.isArray(a.data()?.blocked) ? a.data().blocked : [];
  const blockedB = Array.isArray(b.data()?.blocked) ? b.data().blocked : [];
  return (
    blockedA.map(String).includes(otherUid) ||
    blockedB.map(String).includes(uid)
  );
}

async function isGroupBanned(groupId, uid) {
  try {
    const snap = await db()
      .collection("groups")
      .doc(groupId)
      .collection("bannedUsers")
      .doc(uid)
      .get();
    return snap.exists && snap.data()?.isActive === true;
  } catch (_) {
    return true;
  }
}

function groupCountry(groupData = {}) {
  return String(groupData.countryCode || groupData.country || "")
    .trim()
    .toLowerCase();
}

async function resolveSourceMessage(uid, source) {
  const kind = String(source?.kind || "").trim();
  const messageId = String(source?.messageId || "").trim();
  if (!messageId) throw new HttpsError("invalid-argument", "Missing message.");

  if (kind === "dm") {
    const conversationId = String(source.conversationId || "").trim();
    if (!conversationId) {
      throw new HttpsError("invalid-argument", "Missing conversation.");
    }
    const convRef = db().collection("conversations").doc(conversationId);
    const convSnap = await convRef.get();
    if (!convSnap.exists) {
      throw new HttpsError("permission-denied", "Not allowed.");
    }
    const conv = convSnap.data() || {};
    const parts = Array.isArray(conv.participants)
      ? conv.participants.map(String)
      : [];
    if (!parts.includes(uid)) {
      throw new HttpsError("permission-denied", "Not allowed.");
    }
    const msgSnap = await convRef.collection("messages").doc(messageId).get();
    if (!msgSnap.exists) {
      throw new HttpsError("not-found", "Message not found.");
    }
    const msg = msgSnap.data() || {};
    if (!callerCanReadMessage(msg, uid, { hiddenField: "hiddenFor" })) {
      throw new HttpsError("permission-denied", "Not allowed.");
    }
    const content = extractForwardableContent(msg);
    if (!content.ok) {
      throw new HttpsError("failed-precondition", content.error || "invalid");
    }
    return { content, sourceKind: "dm", sourceId: conversationId };
  }

  if (kind === "group") {
    const groupId = String(source.groupId || "").trim();
    if (!groupId) throw new HttpsError("invalid-argument", "Missing group.");
    const groupRef = db().collection("groups").doc(groupId);
    const groupSnap = await groupRef.get();
    if (!groupSnap.exists) {
      throw new HttpsError("permission-denied", "Not allowed.");
    }
    const g = groupSnap.data() || {};
    if (g.deleted === true || g.isDeleted === true || g.isActive === false) {
      throw new HttpsError("permission-denied", "Not allowed.");
    }
    if (!isParticipating(g, uid)) {
      throw new HttpsError("permission-denied", "Not allowed.");
    }
    if (await isGroupBanned(groupId, uid)) {
      throw new HttpsError("permission-denied", "Not allowed.");
    }
    const msgSnap = await groupRef.collection("messages").doc(messageId).get();
    if (!msgSnap.exists) {
      throw new HttpsError("not-found", "Message not found.");
    }
    const msg = msgSnap.data() || {};
    if (!callerCanReadMessage(msg, uid)) {
      throw new HttpsError("permission-denied", "Not allowed.");
    }
    const content = extractForwardableContent(msg);
    if (!content.ok) {
      throw new HttpsError("failed-precondition", content.error || "invalid");
    }
    return { content, sourceKind: "group", sourceId: groupId };
  }

  throw new HttpsError("invalid-argument", "Bad source.");
}

async function findOrCreateDm(uid, otherUid, myData) {
  if (!otherUid || otherUid === uid) {
    return { error: "bad_dest" };
  }
  const otherSnap = await db().collection("users").doc(otherUid).get();
  const otherData = otherSnap.data() || {};
  if (accountBlocked(otherData)) return { error: "not_allowed" };
  if (await isEitherBlocked(uid, otherUid)) return { error: "blocked" };
  if (!canSendInternational(myData, otherData)) return { error: "premium" };

  const key = pairKey(uid, otherUid);
  const deterministicId = key;
  let convRef = db().collection("conversations").doc(deterministicId);
  let convSnap = await convRef.get();
  if (!convSnap.exists) {
    const q = await db()
      .collection("conversations")
      .where("pairKey", "==", key)
      .limit(1)
      .get();
    if (!q.empty) {
      convRef = q.docs[0].ref;
      convSnap = q.docs[0];
    }
  }
  if (!convSnap.exists) {
    await convRef.set(
      {
        participants: [uid, otherUid].sort(),
        pairKey: key,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        lastMessage: "",
        unread: { [uid]: 0, [otherUid]: 0 },
      },
      { merge: true },
    );
  } else {
    const parts = Array.isArray(convSnap.data()?.participants)
      ? convSnap.data().participants.map(String)
      : [];
    if (!parts.includes(uid) || !parts.includes(otherUid)) {
      return { error: "not_allowed" };
    }
  }
  return { conversationId: convRef.id, otherUid };
}

function buildDmPayload(uid, otherUid, content) {
  const base = {
    type: content.type,
    senderId: uid,
    fromUid: uid,
    toUid: otherUid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    deleted: false,
    deletedBy: "",
    deletedText: "",
    deletedAt: null,
    replyToMessageId: null,
    replyToText: "",
    replyToType: "text",
    replyToIsMe: false,
    replyToImageUrl: "",
    forwarded: true,
  };
  if (content.type === "text") {
    base.text = content.text;
    if (content.linkPreview) {
      base.linkPreview = content.linkPreview;
      base.linkPreviewStatus = "ready";
    }
  } else if (content.type === "image") {
    base.imageUrl = content.imageUrl;
    base.hiddenFor = [];
  } else {
    base.audioUrl = content.audioUrl;
    base.durationMs = content.durationMs;
  }
  return base;
}

function buildGroupPayload(uid, messageId, content) {
  const base = {
    id: messageId,
    type: content.type,
    senderId: uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    deleted: false,
    deletedBy: "",
    deletedText: "",
    deletedAt: null,
    replyToMessageId: null,
    replyToText: "",
    replyToType: "text",
    replyToIsMe: false,
    replyToImageUrl: "",
    forwarded: true,
  };
  if (content.type === "text") {
    base.text = content.text;
    if (content.linkPreview) {
      base.linkPreview = content.linkPreview;
      base.linkPreviewStatus = "ready";
    }
  } else if (content.type === "image") {
    base.text = "";
    base.imageUrl = content.imageUrl;
  } else {
    base.text = "";
    base.audioUrl = content.audioUrl;
    base.durationMs = content.durationMs;
  }
  return base;
}

async function writeDm(uid, conversationId, otherUid, content) {
  const msgRef = db()
    .collection("conversations")
    .doc(conversationId)
    .collection("messages")
    .doc();
  const payload = buildDmPayload(uid, otherUid, content);
  await msgRef.set(payload);
  // Unread/lastMessage/push: onPrivateMessageCreated
  return { messageId: msgRef.id, path: msgRef.path };
}

async function writeGroup(uid, groupId, content) {
  const groupRef = db().collection("groups").doc(groupId);
  const msgRef = groupRef.collection("messages").doc();
  const payload = buildGroupPayload(uid, msgRef.id, content);
  const batch = db().batch();
  batch.set(msgRef, payload);
  batch.set(
    groupRef.collection("reads").doc(uid),
    {
      uid,
      lastReadAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  await batch.commit();
  return { messageId: msgRef.id, path: msgRef.path };
}

function enqueuePreviewIfNeeded(uid, content, messagePath) {
  if (content.type !== "text" || content.linkPreview) return;
  const m = String(content.text || "").match(/\bhttps:\/\/[^\s<>"']+/i);
  if (!m) return;
  const previewUrl = m[0].replace(/[),.;]+$/g, "");
  setImmediate(() => {
    try {
      const { createFetchLinkPreviewHandler } = require("./link_preview");
      const handler = createFetchLinkPreviewHandler({
        getFirestore: () => admin.firestore(),
        HttpsError,
      });
      handler({
        auth: { uid },
        data: { url: previewUrl, messagePath },
      }).catch(() => {});
    } catch (_) {}
  });
}

async function forwardToDestination(uid, myData, dest, content) {
  if (dest.kind === "dm") {
    let conversationId = dest.conversationId;
    let otherUid = dest.otherUid;
    if (conversationId) {
      const convSnap = await db()
        .collection("conversations")
        .doc(conversationId)
        .get();
      if (!convSnap.exists) return { ok: false, error: "not_allowed" };
      const parts = Array.isArray(convSnap.data()?.participants)
        ? convSnap.data().participants.map(String)
        : [];
      if (!parts.includes(uid)) return { ok: false, error: "not_allowed" };
      otherUid = parts.find((p) => p !== uid) || "";
      if (!otherUid) return { ok: false, error: "not_allowed" };
      const otherData =
        (await db().collection("users").doc(otherUid).get()).data() || {};
      if (accountBlocked(otherData)) return { ok: false, error: "not_allowed" };
      if (await isEitherBlocked(uid, otherUid)) {
        return { ok: false, error: "blocked" };
      }
      if (!canSendInternational(myData, otherData)) {
        return { ok: false, error: "premium" };
      }
    } else {
      const resolved = await findOrCreateDm(uid, otherUid, myData);
      if (resolved.error) return { ok: false, error: resolved.error };
      conversationId = resolved.conversationId;
      otherUid = resolved.otherUid;
    }
    const written = await writeDm(uid, conversationId, otherUid, content);
    enqueuePreviewIfNeeded(uid, content, written.path);
    return {
      ok: true,
      kind: "dm",
      destinationId: conversationId,
      messageId: written.messageId,
    };
  }

  // group
  const groupId = dest.groupId;
  const groupSnap = await db().collection("groups").doc(groupId).get();
  if (!groupSnap.exists) return { ok: false, error: "not_allowed" };
  const g = groupSnap.data() || {};
  if (g.deleted === true || g.isDeleted === true || g.isActive === false) {
    return { ok: false, error: "not_allowed" };
  }
  if (!isParticipating(g, uid)) return { ok: false, error: "not_member" };
  if (await isGroupBanned(groupId, uid)) return { ok: false, error: "banned" };
  const myCountry = countryOf(myData);
  const gCountry = groupCountry(g);
  if (
    myCountry &&
    gCountry &&
    myCountry !== gCountry &&
    !isPremiumUser(myData) &&
    g.isPremiumGroup !== true
  ) {
    return { ok: false, error: "premium" };
  }
  const written = await writeGroup(uid, groupId, content);
  enqueuePreviewIfNeeded(uid, content, written.path);
  return {
    ok: true,
    kind: "group",
    destinationId: groupId,
    messageId: written.messageId,
  };
}

const forwardMessage = onCall({ region: "us-central1" }, async (request) => {
  await require("./social_age_guard").assertVerifiedAdult(request, {
    getFirestore: db, HttpsError,
  });
  const uid = requireAuth(request);
  await bumpRate(uid);
  const myData = await loadActiveUser(uid);

  const intentId = String(request.data?.intentId || "").trim();
  if (!intentId || intentId.length < 8) {
    throw new HttpsError("invalid-argument", "Missing intentId.");
  }

  const idemRef = db()
    .collection("forwardIdempotency")
    .doc(idempotencyDocId(uid, intentId));
  const idemSnap = await idemRef.get();
  if (idemSnap.exists && Array.isArray(idemSnap.data()?.results)) {
    return {
      ok: true,
      duplicate: true,
      results: idemSnap.data().results,
      successCount: idemSnap.data().successCount || 0,
      failureCount: idemSnap.data().failureCount || 0,
    };
  }

  const { content } = await resolveSourceMessage(uid, request.data?.source);
  const normalized = normalizeDestinations(request.data?.destinations);
  if (!normalized.ok) {
    throw new HttpsError("invalid-argument", normalized.error);
  }

  const results = [];
  for (const dest of normalized.destinations) {
    try {
      const r = await forwardToDestination(uid, myData, dest, content);
      results.push({
        kind: dest.kind,
        destinationId:
          dest.kind === "dm"
            ? dest.conversationId || dest.otherUid
            : dest.groupId,
        ok: r.ok === true,
        error: r.error || null,
        messageId: r.messageId || null,
      });
    } catch (e) {
      results.push({
        kind: dest.kind,
        destinationId:
          dest.kind === "dm"
            ? dest.conversationId || dest.otherUid
            : dest.groupId,
        ok: false,
        error: "failed",
        messageId: null,
      });
    }
  }

  const successCount = results.filter((r) => r.ok).length;
  const failureCount = results.length - successCount;

  await idemRef.set({
    uid,
    intentId,
    results,
    successCount,
    failureCount,
    createdAtMs: Date.now(),
    expiresAtMs: Date.now() + IDEMPOTENCY_TTL_MS,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  console.info("forwardMessage", {
    uidLen: uid.length,
    successCount,
    failureCount,
    type: content.type,
  });

  return {
    ok: successCount > 0,
    duplicate: false,
    results,
    successCount,
    failureCount,
  };
});

module.exports = {
  forwardMessage,
  MAX_DESTINATIONS,
};
