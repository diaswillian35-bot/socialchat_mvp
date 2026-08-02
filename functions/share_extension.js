/**
 * Share Extension Callables — short-lived opaque session + list/send.
 *
 * App Check: soft gate via SHARE_EXT_ENFORCE_APP_CHECK=true (same pattern as Remi).
 * Extension uses URLSession callables without Firebase Auth; session token is the auth.
 * Logs never include raw tokens or full message bodies.
 */

const crypto = require("crypto");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");
const {
  SESSION_TTL_MS,
  IDEMPOTENCY_TTL_MS,
  MAX_SESSIONS_PER_UID,
  SCOPES,
  RATE,
  hashToken,
  generateOpaqueToken,
  generateSessionId,
  isExpired,
  accountBlocked,
  isPremiumUser,
  countryOf,
  canSendInternational,
  normalizeShareText,
  publicDisplayName,
  publicPhotoUrl,
  publicLocationShort,
  evaluateRateLimit,
  idempotencyDocId,
} = require("./share_extension_logic");

const db = () => admin.firestore();

function assertAppCheckSoft(request) {
  if (process.env.SHARE_EXT_ENFORCE_APP_CHECK === "true" && !request.app) {
    throw new HttpsError(
      "failed-precondition",
      "App Check required for share extension.",
    );
  }
}

function requireAuth(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }
  return request.auth.uid;
}

async function bumpRate(key, max, windowMs) {
  const ref = db().collection("_rateLimits").doc(`shareExt_${key}`);
  const now = Date.now();
  await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const next = evaluateRateLimit(snap.data() || {}, now, max, windowMs);
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

async function loadValidSession(token) {
  const raw = String(token || "").trim();
  if (raw.length < 20) {
    throw new HttpsError("unauthenticated", "Invalid session.");
  }
  const tokenHash = hashToken(raw);
  const q = await db()
    .collection("shareExtensionSessions")
    .where("tokenHash", "==", tokenHash)
    .limit(1)
    .get();
  if (q.empty) {
    throw new HttpsError("unauthenticated", "Invalid session.");
  }
  const doc = q.docs[0];
  const data = doc.data() || {};
  if (data.revoked === true) {
    throw new HttpsError("unauthenticated", "Session revoked.");
  }
  if (isExpired(data.expiresAtMs)) {
    throw new HttpsError("unauthenticated", "Session expired.");
  }
  return { sid: doc.id, ref: doc.ref, data };
}

async function assertUserActive(uid) {
  const snap = await db().collection("users").doc(uid).get();
  const data = snap.data() || {};
  const block = accountBlocked(data);
  if (block === "banned" || block === "deleted") {
    throw new HttpsError("permission-denied", "Not allowed.");
  }
  if (block === "shadow_ban") {
    throw new HttpsError("permission-denied", "Not allowed.");
  }
  return data;
}

async function isEitherBlocked(uid, otherUid) {
  const [a, b] = await Promise.all([
    db().collection("users").doc(uid).get(),
    db().collection("users").doc(otherUid).get(),
  ]);
  const blockedA = Array.isArray(a.data()?.blocked) ? a.data().blocked : [];
  const blockedB = Array.isArray(b.data()?.blocked) ? b.data().blocked : [];
  return blockedA.map(String).includes(otherUid) || blockedB.map(String).includes(uid);
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

function isParticipating(groupData, uid) {
  const members = Array.isArray(groupData.members)
    ? groupData.members.map(String)
    : [];
  if (members.includes(uid)) return true;
  if (String(groupData.ownerId || "") === uid) return true;
  const admins = Array.isArray(groupData.admins)
    ? groupData.admins.map(String)
    : [];
  return admins.includes(uid);
}

async function pruneOldSessions(uid) {
  const q = await db()
    .collection("shareExtensionSessions")
    .where("uid", "==", uid)
    .limit(30)
    .get();
  const now = Date.now();
  const active = [];
  const batch = db().batch();
  for (const doc of q.docs) {
    const d = doc.data() || {};
    if (d.revoked === true || isExpired(d.expiresAtMs, now)) {
      batch.delete(doc.ref);
      continue;
    }
    active.push({ doc, createdAtMs: d.createdAtMs || 0 });
  }
  active.sort((a, b) => b.createdAtMs - a.createdAtMs);
  active.slice(MAX_SESSIONS_PER_UID).forEach(({ doc }) => {
    batch.update(doc.ref, {
      revoked: true,
      revokedAtMs: now,
      revokeReason: "rotated",
    });
  });
  await batch.commit();
}

const issueShareExtensionSession = onCall(
  { region: "us-central1" },
  async (request) => {
    assertAppCheckSoft(request);
    const uid = requireAuth(request);
    await bumpRate(
      `issue_${uid}`,
      RATE.issuePerUid.max,
      RATE.issuePerUid.windowMs,
    );
    await assertUserActive(uid);

    const deviceId = String(request.data?.deviceId || "").slice(0, 128);
    await pruneOldSessions(uid);

    const token = generateOpaqueToken();
    const sid = generateSessionId();
    const now = Date.now();
    const expiresAtMs = now + SESSION_TTL_MS;
    await db()
      .collection("shareExtensionSessions")
      .doc(sid)
      .set({
        uid,
        tokenHash: hashToken(token),
        deviceId,
        scopes: [...SCOPES],
        createdAtMs: now,
        expiresAtMs,
        revoked: false,
        jti: crypto.randomBytes(12).toString("hex"),
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

    console.info("shareExt.issue", { uidLen: uid.length, sidPrefix: sid.slice(0, 6) });
    return {
      token,
      sid,
      expiresAtMs,
      scopes: [...SCOPES],
    };
  },
);

async function revokeAllSessionsForUid(uid, reason = "client_all") {
  const now = Date.now();
  const q = await db()
    .collection("shareExtensionSessions")
    .where("uid", "==", uid)
    .limit(50)
    .get();
  if (q.empty) return 0;
  const batch = db().batch();
  for (const doc of q.docs) {
    batch.update(doc.ref, {
      revoked: true,
      revokedAtMs: now,
      revokeReason: reason,
    });
  }
  await batch.commit();
  return q.size;
}

const revokeShareExtensionSessions = onCall(
  { region: "us-central1" },
  async (request) => {
    assertAppCheckSoft(request);
    const uid = requireAuth(request);
    const sid = request.data?.sid ? String(request.data.sid) : null;
    const now = Date.now();
    if (sid) {
      const ref = db().collection("shareExtensionSessions").doc(sid);
      const snap = await ref.get();
      if (snap.exists && snap.data()?.uid === uid) {
        await ref.update({
          revoked: true,
          revokedAtMs: now,
          revokeReason: "client",
        });
      }
      return { ok: true };
    }
    const count = await revokeAllSessionsForUid(uid, "client_all");
    console.info("shareExt.revoke", { uidLen: uid.length, count });
    return { ok: true };
  },
);

const listShareDestinations = onCall(
  { region: "us-central1" },
  async (request) => {
    assertAppCheckSoft(request);
    const token = request.data?.token;
    const query = String(request.data?.query || "")
      .trim()
      .toLowerCase()
      .slice(0, 64);
    const session = await loadValidSession(token);
    if (!Array.isArray(session.data.scopes) || !session.data.scopes.includes("share.list")) {
      throw new HttpsError("permission-denied", "Missing scope.");
    }
    const uid = session.data.uid;
    await bumpRate(`list_${uid}`, RATE.listPerUid.max, RATE.listPerUid.windowMs);
    const myData = await assertUserActive(uid);

    const conversations = [];
    const groups = [];

    const convSnap = await db()
      .collection("conversations")
      .where("participants", "array-contains", uid)
      .limit(80)
      .get();

    for (const doc of convSnap.docs) {
      const data = doc.data() || {};
      const participants = Array.isArray(data.participants)
        ? data.participants.map(String)
        : [];
      const hiddenFor = Array.isArray(data.hiddenFor)
        ? data.hiddenFor.map(String)
        : [];
      if (hiddenFor.includes(uid)) continue;
      const otherUid = participants.find((p) => p !== uid);
      if (!otherUid) continue;

      const [pubSnap, otherUserSnap] = await Promise.all([
        db().collection("publicUsers").doc(otherUid).get(),
        db().collection("users").doc(otherUid).get(),
      ]);
      const pub = pubSnap.data() || {};
      const otherData = otherUserSnap.data() || {};
      const blocked = await isEitherBlocked(uid, otherUid);
      const intlOk = canSendInternational(myData, otherData);
      let allowed = true;
      let blockedReason = "";
      if (blocked || accountBlocked(otherData) || !intlOk) {
        allowed = false;
        blockedReason = "unavailable";
      }
      const displayName = publicDisplayName(pub, "Chat");
      if (query && !displayName.toLowerCase().includes(query)) continue;

      conversations.push({
        destinationId: doc.id,
        type: "dm",
        otherUid,
        displayName,
        photoUrl: publicPhotoUrl(pub),
        location: publicLocationShort(pub),
        allowed,
        blockedReason,
      });
    }

    let groupSnap = await db()
      .collection("groups")
      .where("members", "array-contains", uid)
      .limit(80)
      .get();
    if (groupSnap.empty) {
      groupSnap = await db()
        .collection("groups")
        .where("ownerId", "==", uid)
        .limit(40)
        .get();
    }

    for (const doc of groupSnap.docs) {
      const data = doc.data() || {};
      if (data.deleted === true || data.isDeleted === true) continue;
      if (data.isActive === false) continue;
      if (!isParticipating(data, uid)) continue;
      if (await isGroupBanned(doc.id, uid)) continue;

      const myCountry = countryOf(myData);
      const gCountry = groupCountry(data);
      const world = myCountry && gCountry && myCountry !== gCountry;
      let allowed = true;
      let blockedReason = "";
      if (world && !isPremiumUser(myData) && data.isPremiumGroup !== true) {
        // Match client: international group needs premium for sender.
        allowed = false;
        blockedReason = "unavailable";
      }

      const displayName = String(data.name || data.title || "Group").slice(0, 80);
      if (query && !displayName.toLowerCase().includes(query)) continue;

      groups.push({
        destinationId: doc.id,
        type: "group",
        displayName,
        photoUrl: String(data.photoUrl || data.imageUrl || "").startsWith("https://")
          ? String(data.photoUrl || data.imageUrl).slice(0, 500)
          : "",
        location: String(data.city || gCountry || "").slice(0, 80),
        allowed,
        blockedReason,
      });
    }

    console.info("shareExt.list", {
      uidLen: uid.length,
      dm: conversations.length,
      groups: groups.length,
    });
    return { conversations, groups };
  },
);

const sendShareMessage = onCall(
  { region: "us-central1" },
  async (request) => {
    assertAppCheckSoft(request);
    const token = request.data?.token;
    const destinationId = String(request.data?.destinationId || "").trim();
    const kind = String(request.data?.kind || request.data?.type || "").trim();
    const intentId = String(request.data?.intentId || "").trim().slice(0, 128);
    const clientNonce = String(request.data?.clientNonce || "").trim().slice(0, 128);
    const textRaw = request.data?.text;

    const session = await loadValidSession(token);
    if (!Array.isArray(session.data.scopes) || !session.data.scopes.includes("share.send")) {
      throw new HttpsError("permission-denied", "Missing scope.");
    }
    const uid = session.data.uid;
    // Sender ALWAYS from session — ignore any client-provided sender fields.
    await bumpRate(`send_${uid}`, RATE.sendPerUid.max, RATE.sendPerUid.windowMs);
    await bumpRate(
      `send_${uid}_${destinationId}`,
      RATE.sendPerDest.max,
      RATE.sendPerDest.windowMs,
    );

    const myData = await assertUserActive(uid);
    const parsed = normalizeShareText(textRaw);
    if (!parsed.ok) {
      throw new HttpsError("invalid-argument", "Invalid content.");
    }
    if (!destinationId || (kind !== "dm" && kind !== "group")) {
      throw new HttpsError("invalid-argument", "Invalid destination.");
    }
    if (!intentId) {
      throw new HttpsError("invalid-argument", "intentId required.");
    }

    const idemRef = db()
      .collection("shareExtensionIdempotency")
      .doc(idempotencyDocId(uid, intentId));

    const existing = await idemRef.get();
    if (existing.exists && existing.data()?.messageId) {
      return {
        ok: true,
        messageId: existing.data().messageId,
        duplicate: true,
      };
    }

    let messageId;

    if (kind === "dm") {
      const otherUid = String(request.data?.otherUid || "").trim();
      const convSnap = await db().collection("conversations").doc(destinationId).get();
      if (!convSnap.exists) {
        throw new HttpsError("permission-denied", "Not allowed.");
      }
      const participants = Array.isArray(convSnap.data()?.participants)
        ? convSnap.data().participants.map(String)
        : [];
      if (!participants.includes(uid)) {
        throw new HttpsError("permission-denied", "Not allowed.");
      }
      const resolvedOther =
        otherUid && participants.includes(otherUid)
          ? otherUid
          : participants.find((p) => p !== uid);
      if (!resolvedOther) {
        throw new HttpsError("permission-denied", "Not allowed.");
      }
      if (await isEitherBlocked(uid, resolvedOther)) {
        throw new HttpsError("permission-denied", "Not allowed.");
      }
      const otherSnap = await db().collection("users").doc(resolvedOther).get();
      if (!canSendInternational(myData, otherSnap.data() || {})) {
        throw new HttpsError("permission-denied", "Not allowed.");
      }

      const msgRef = db()
        .collection("conversations")
        .doc(destinationId)
        .collection("messages")
        .doc();
      messageId = msgRef.id;

      await db().runTransaction(async (tx) => {
        const idem = await tx.get(idemRef);
        if (idem.exists && idem.data()?.messageId) {
          messageId = idem.data().messageId;
          return;
        }
        const now = admin.firestore.Timestamp.now();
        tx.set(msgRef, {
          type: "text",
          text: parsed.text,
          senderId: uid,
          fromUid: uid,
          toUid: resolvedOther,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          clientCreatedAt: now,
          deleted: false,
          deletedBy: "",
          deletedText: "",
          deletedAt: null,
          replyToMessageId: null,
          replyToText: "",
          replyToType: "text",
          replyToIsMe: false,
          replyToImageUrl: "",
        });
        const convRef = db().collection("conversations").doc(destinationId);
        tx.set(
          convRef,
          {
            lastMessage: parsed.text.slice(0, 200),
            lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            [`unread.${resolvedOther}`]: admin.firestore.FieldValue.increment(1),
            [`unread.${uid}`]: 0,
          },
          { merge: true },
        );
        tx.set(idemRef, {
          uid,
          intentId,
          clientNonce,
          messageId,
          kind: "dm",
          destinationId,
          createdAtMs: Date.now(),
          expiresAtMs: Date.now() + IDEMPOTENCY_TTL_MS,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    } else {
      const groupRef = db().collection("groups").doc(destinationId);
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
      if (await isGroupBanned(destinationId, uid)) {
        throw new HttpsError("permission-denied", "Not allowed.");
      }
      const myCountry = countryOf(myData);
      const gCountry = groupCountry(g);
      if (
        myCountry &&
        gCountry &&
        myCountry !== gCountry &&
        !isPremiumUser(myData) &&
        g.isPremiumGroup !== true
      ) {
        throw new HttpsError("permission-denied", "Not allowed.");
      }

      const msgRef = groupRef.collection("messages").doc();
      messageId = msgRef.id;

      await db().runTransaction(async (tx) => {
        const idem = await tx.get(idemRef);
        if (idem.exists && idem.data()?.messageId) {
          messageId = idem.data().messageId;
          return;
        }
        tx.set(msgRef, {
          id: messageId,
          type: "text",
          text: parsed.text,
          senderId: uid,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          replyToMessageId: null,
          replyToText: "",
          replyToType: "text",
          replyToIsMe: false,
          replyToImageUrl: "",
          deleted: false,
          deletedBy: "",
          deletedText: "",
          deletedAt: null,
        });
        tx.set(
          groupRef.collection("reads").doc(uid),
          {
            uid,
            lastReadAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
        tx.set(idemRef, {
          uid,
          intentId,
          clientNonce,
          messageId,
          kind: "group",
          destinationId,
          createdAtMs: Date.now(),
          expiresAtMs: Date.now() + IDEMPOTENCY_TTL_MS,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
    }

    console.info("shareExt.send", {
      uidLen: uid.length,
      kind,
      messageIdPrefix: String(messageId).slice(0, 6),
    });

    // Same link-preview path as host (best-effort; never blocks send).
    const httpsMatch = String(parsed.text).match(/\bhttps:\/\/[^\s<>"']+/i);
    if (httpsMatch && messageId) {
      const messagePath =
        kind === "dm"
          ? `conversations/${destinationId}/messages/${messageId}`
          : `groups/${destinationId}/messages/${messageId}`;
      const previewUrl = httpsMatch[0].replace(/[),.;]+$/g, "");
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
          }).catch((e) => {
            console.info("shareExt.preview_soft_fail", {
              code: (e && e.code) || "err",
            });
          });
        } catch (e) {
          console.info("shareExt.preview_skip", { code: "init" });
        }
      });
    }

    return { ok: true, messageId, duplicate: false };
  },
);

/**
 * Daily cleanup: expired sessions and stale idempotency docs.
 * Online checks still reject expired tokens; this bounds storage cost.
 */
const { onSchedule } = require("firebase-functions/v2/scheduler");

const purgeExpiredShareExtensionData = onSchedule(
  {
    region: "us-central1",
    schedule: "every 24 hours",
    timeZone: "Etc/UTC",
  },
  async () => {
    const now = Date.now();
    const batchLimit = 400;
    let deletedSessions = 0;
    let deletedIdem = 0;

    const sess = await db()
      .collection("shareExtensionSessions")
      .where("expiresAtMs", "<", now)
      .limit(batchLimit)
      .get();
    if (!sess.empty) {
      const batch = db().batch();
      for (const doc of sess.docs) {
        batch.delete(doc.ref);
        deletedSessions += 1;
      }
      await batch.commit();
    }

    const idem = await db()
      .collection("shareExtensionIdempotency")
      .where("expiresAtMs", "<", now)
      .limit(batchLimit)
      .get();
    if (!idem.empty) {
      const batch = db().batch();
      for (const doc of idem.docs) {
        batch.delete(doc.ref);
        deletedIdem += 1;
      }
      await batch.commit();
    }

    console.info("shareExt.purge", { deletedSessions, deletedIdem });
  },
);

module.exports = {
  issueShareExtensionSession,
  revokeShareExtensionSessions,
  listShareDestinations,
  sendShareMessage,
  revokeAllSessionsForUid,
  purgeExpiredShareExtensionData,
};
