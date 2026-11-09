"use strict";
// Salas de áudio ao vivo nos grupos (LiveKit Cloud). Sem gravação: nunca usa
// a API de gravação do LiveKit. Escritas em audioRooms só por aqui (Admin SDK).
const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const { AccessToken, RoomServiceClient, WebhookReceiver, TrackSource } =
  require("livekit-server-sdk");
const { isSuperAdminAuth } = require("./super_admin");
const { assertVerifiedAdult } = require("./social_age_guard");
const L = require("./audio_room_logic");
const { roleOf } = require("./group_role_policy");

const LIVEKIT_API_KEY = defineSecret("LIVEKIT_API_KEY");
const LIVEKIT_API_SECRET = defineSecret("LIVEKIT_API_SECRET");

const ERR = {
  unauthenticated: "unauthenticated", group_not_found: "not-found",
  banned: "permission-denied", not_member: "permission-denied",
  country_blocked: "permission-denied", not_moderator: "permission-denied",
  target_is_moderator: "failed-precondition", room_full: "resource-exhausted",
  no_live_room: "failed-precondition",
};
function fail(code) {
  throw new HttpsError(ERR[code] || "failed-precondition", code);
}

function roomService() {
  return new RoomServiceClient(L.LIVEKIT_HOST, LIVEKIT_API_KEY.value(), LIVEKIT_API_SECRET.value());
}

const micPermission = (canPublish) => ({
  canPublish, canSubscribe: true, canPublishData: true,
  canPublishSources: canPublish ? [TrackSource.MICROPHONE] : [],
});

function displayName(user, uid) {
  return (user?.name || user?.displayName || user?.username || "").toString().trim().slice(0, 60) || uid;
}

async function loadContext(request) {
  const uid = request.auth?.uid || "";
  if (!uid) fail("unauthenticated");
  const groupId = (request.data?.groupId || "").toString().trim();
  if (!groupId || groupId.length > 128 || groupId.includes("/")) {
    throw new HttpsError("invalid-argument", "groupId");
  }
  const db = admin.firestore();
  const groupRef = db.collection("groups").doc(groupId);
  const [g, u, b, live] = await Promise.all([
    groupRef.get(),
    db.collection("users").doc(uid).get(),
    groupRef.collection("bannedUsers").doc(uid).get(),
    groupRef.collection("audioRooms").where("status", "==", "live").limit(1).get(),
  ]);
  return {
    uid, groupId, groupRef, db,
    group: g.exists ? g.data() : null,
    user: u.data() || {},
    banned: b.exists && b.data()?.isActive !== false,
    isAdmin: isSuperAdminAuth(request.auth),
    liveDoc: live.empty ? null : live.docs[0],
  };
}

async function handleOpen(c) {
  const e = L.manageError(c); if (e) fail(e);
  if (c.liveDoc) return { roomId: c.liveDoc.id, alreadyLive: true };
  const roomName = L.roomNameFor(c.groupId);
  await roomService().createRoom({ name: roomName, maxParticipants: L.MAX_PARTICIPANTS, emptyTimeout: 300 });
  const ref = c.groupRef.collection("audioRooms").doc();
  await ref.set({
    status: "live", roomName, groupId: c.groupId,
    openedBy: c.uid, openedByName: displayName(c.user, c.uid),
    startedAt: admin.firestore.FieldValue.serverTimestamp(),
    participantCount: 0, presentUids: [], speakerUids: [],
  });
  return { roomId: ref.id, alreadyLive: false };
}

async function handleClose(c) {
  const e = L.manageError(c); if (e) fail(e);
  if (!c.liveDoc) return { closed: false };
  await c.liveDoc.ref.set({
    status: "ended", endedBy: c.uid,
    endedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });
  try { await roomService().deleteRoom(c.liveDoc.get("roomName")); } catch (err) {
    console.warn("audioRoom deleteRoom", err?.message);
  }
  return { closed: true };
}

async function handleToken(c) {
  const e = L.joinError(c); if (e) fail(e);
  if (!c.liveDoc) fail("no_live_room");
  const room = c.liveDoc.data();
  const cap = L.capacityError(room, c.uid); if (cap) fail(cap);
  const grant = L.grantFor({ group: c.group, room, uid: c.uid });
  const at = new AccessToken(LIVEKIT_API_KEY.value(), LIVEKIT_API_SECRET.value(), {
    identity: c.uid, name: displayName(c.user, c.uid), ttl: "2h",
    metadata: JSON.stringify({ role: grant.role }),
  });
  at.addGrant({ roomJoin: true, room: room.roomName, ...micPermission(grant.canPublish) });
  return {
    token: await at.toJwt(), url: L.LIVEKIT_URL, roomName: room.roomName,
    roomId: c.liveDoc.id, role: grant.role, canPublish: grant.canPublish,
  };
}

async function handleHand(c, raise) {
  const e = L.joinError(c); if (e) fail(e);
  if (!c.liveDoc) fail("no_live_room");
  const target = raise ? c.uid : ((c.targetUid || c.uid));
  if (target !== c.uid && !L.isModeratorRole(roleOf(c.group, c.uid))) {
    fail("not_moderator");
  }
  const ref = c.liveDoc.ref.collection("hands").doc(target);
  if (raise) {
    await ref.set({ uid: c.uid, name: displayName(c.user, c.uid),
      raisedAt: admin.firestore.FieldValue.serverTimestamp() });
  } else {
    await ref.delete();
  }
  return { ok: true };
}

async function handleSpeaker(c, approve) {
  const e = L.joinError(c); if (e) fail(e);
  if (!c.liveDoc) fail("no_live_room");
  const targetUid = (c.targetUid || "").toString().trim();
  if (!targetUid) throw new HttpsError("invalid-argument", "targetUid");
  const se = L.speakerChangeError({ group: c.group, uid: c.uid, targetUid }); if (se) fail(se);
  const FV = admin.firestore.FieldValue;
  await c.liveDoc.ref.set({ speakerUids: approve ? FV.arrayUnion(targetUid) : FV.arrayRemove(targetUid) }, { merge: true });
  await c.liveDoc.ref.collection("hands").doc(targetUid).delete();
  try {
    await roomService().updateParticipant(c.liveDoc.get("roomName"), targetUid, { permission: micPermission(approve) });
  } catch (err) {
    console.warn("audioRoom updateParticipant", err?.message);
  }
  return { ok: true };
}

const ACTIONS = new Set(["open", "close", "token", "raiseHand", "lowerHand", "approveSpeaker", "revokeSpeaker"]);

exports.audioRoomAction = onCall(
  { region: "us-central1", secrets: [LIVEKIT_API_KEY, LIVEKIT_API_SECRET] },
  async (request) => {
    const action = (request.data?.action || "").toString();
    if (!ACTIONS.has(action)) throw new HttpsError("invalid-argument", "action");
    await assertVerifiedAdult(request, { getFirestore: () => admin.firestore(), HttpsError });
    const c = await loadContext(request);
    c.targetUid = request.data?.targetUid;
    switch (action) {
      case "open": return handleOpen(c);
      case "close": return handleClose(c);
      case "token": return handleToken(c);
      case "raiseHand": return handleHand(c, true);
      case "lowerHand": return handleHand(c, false);
      case "approveSpeaker": return handleSpeaker(c, true);
      default: return handleSpeaker(c, false);
    }
  },
);

exports.audioRoomWebhook = onRequest(
  { region: "us-central1", secrets: [LIVEKIT_API_KEY, LIVEKIT_API_SECRET] },
  async (req, res) => {
    if (req.method !== "POST") { res.status(405).end(); return; }
    let ev;
    try {
      const receiver = new WebhookReceiver(LIVEKIT_API_KEY.value(), LIVEKIT_API_SECRET.value());
      ev = await receiver.receive(req.rawBody.toString("utf8"), req.get("Authorization"));
    } catch (_) { res.status(401).end(); return; }
    const groupId = L.groupIdFromRoomName(ev.room?.name);
    if (!groupId) { res.status(200).end(); return; }
    const live = await admin.firestore().collection("groups").doc(groupId)
      .collection("audioRooms").where("status", "==", "live").limit(1).get();
    if (live.empty) { res.status(200).end(); return; }
    const ref = live.docs[0].ref;
    const FV = admin.firestore.FieldValue;
    const uid = ev.participant?.identity || "";
    if (ev.event === "participant_joined" && uid) {
      await ref.update({ presentUids: FV.arrayUnion(uid) });
    } else if (ev.event === "participant_left" && uid) {
      await ref.update({ presentUids: FV.arrayRemove(uid) });
      await ref.collection("hands").doc(uid).delete();
    } else if (ev.event === "room_finished") {
      await ref.update({ status: "ended", endedAt: FV.serverTimestamp(), endedBy: "livekit" });
    }
    if (ev.event === "participant_joined" || ev.event === "participant_left") {
      const snap = await ref.get();
      await ref.update({ participantCount: (snap.get("presentUids") || []).length });
    }
    res.status(200).end();
  },
);
