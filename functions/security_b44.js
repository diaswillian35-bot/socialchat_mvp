/**
 * b44 (segurança): selo de verificado por SMS, ajuste/perdão de moderação,
 * bot moderador dos grupos (config + boas-vindas) e revogação automática.
 * Núcleos (*Core) recebem db/admin para os testes no emulador.
 */

const crypto = require("crypto");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const { isSuperAdminAuth } = require("./super_admin");
const { botConfig, sanitizeBotChanges, BOT_SENDER_ID } = require("./moderation/group_bot");
const { evaluateText } = require("./moderation/text_filter");
const { evaluateProfanity } = require("./moderation/profanity");
const { toMs } = require("./moderation/ladder");

const REGION_CALL = "us-central1";
const REGION_TRIGGER = "northamerica-northeast1";
const VERIFY_PHONE_PEPPER = defineSecret("VERIFY_PHONE_PEPPER");
const VERIFICATION_POLICY_VERSION = 1;

const ts = () => admin.firestore.FieldValue.serverTimestamp();

// ---------------- admin ----------------
async function hasAdminPermission(db, auth, permission) {
  if (!auth || !auth.uid) return false;
  if (isSuperAdminAuth(auth)) return true;
  const snap = await db.collection("admins").doc(auth.uid).get();
  if (!snap.exists) return false;
  const d = snap.data() || {};
  if (d.isActive === false) return false;
  if (d.isOwner === true) return true;
  return Boolean(d.permissions && d.permissions[permission] === true);
}

async function audit(db, entry) {
  await db.collection("moderationAudit").add({ ...entry, at: ts() });
}

// ---------------- verificação por telefone ----------------
function phoneHash(e164, pepper) {
  const p = String(e164 || "").replace(/[^\d+]/g, "");
  return crypto.createHash("sha256").update(`${pepper || ""}|${p}`).digest("hex");
}

/**
 * phoneNumber vem SEMPRE do Firebase Auth (Admin SDK), nunca do cliente.
 * Um número verifica uma conta só (verificationPhones/{hash}).
 */
async function markPhoneVerifiedCore(db, uid, { phoneNumber, pepper }) {
  const phone = String(phoneNumber || "").trim();
  const userRef = db.collection("users").doc(uid);
  if (!/^\+\d{8,15}$/.test(phone)) {
    // sem telefone vinculado: se tinha selo, revoga (desvinculou).
    const u = await userRef.get();
    if (u.exists && u.data()?.verification?.status === "verified") {
      await revokeVerificationCore(db, uid, { by: "system", reason: "phone_unlinked" });
    }
    throw new HttpsError("failed-precondition", "no_phone", { reason: "no_phone" });
  }
  const hash = phoneHash(phone, pepper);
  const phoneRef = db.collection("verificationPhones").doc(hash);
  const result = await db.runTransaction(async (tx) => {
    const [p, u] = await Promise.all([tx.get(phoneRef), tx.get(userRef)]);
    const owner = p.exists ? String(p.data()?.uid || "") : "";
    if (owner && owner !== uid) return { error: "phone_in_use" };
    const ud = u.exists ? u.data() || {} : {};
    if (ud.isBanned === true || ud.moderation?.status === "banned") return { error: "not_allowed" };
    const prevHash = String(ud.verification?.phoneHash || "");
    if (prevHash && prevHash !== hash) tx.delete(db.collection("verificationPhones").doc(prevHash));
    tx.set(phoneRef, { uid, at: ts() });
    tx.set(userRef, {
      verification: {
        status: "verified",
        method: "phone",
        phoneHash: hash,
        policyVersion: VERIFICATION_POLICY_VERSION,
        at: ts(),
      },
    }, { merge: true });
    tx.set(db.collection("publicUsers").doc(uid), { verified: true }, { merge: true });
    return { ok: true };
  });
  if (result.error) {
    throw new HttpsError("failed-precondition", result.error, { reason: result.error });
  }
  return { verified: true };
}

async function revokeVerificationCore(db, uid, { by, reason }) {
  const userRef = db.collection("users").doc(uid);
  const u = await userRef.get();
  const hash = String((u.exists && u.data()?.verification?.phoneHash) || "");
  const batch = db.batch();
  if (hash) batch.delete(db.collection("verificationPhones").doc(hash));
  batch.set(userRef, {
    verification: {
      status: "revoked",
      method: "phone",
      phoneHash: admin.firestore.FieldValue.delete(),
      revokedBy: String(by || "system"),
      revokedReason: String(reason || ""),
      revokedAt: ts(),
    },
  }, { merge: true });
  batch.set(db.collection("publicUsers").doc(uid), { verified: false }, { merge: true });
  await batch.commit();
  await audit(db, { action: "verification_revoke", targetUid: uid, by: String(by || "system"), reason: String(reason || "") });
  return { revoked: true };
}

const markPhoneVerified = onCall(
  { region: REGION_CALL, secrets: [VERIFY_PHONE_PEPPER] },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Login required.");
    const user = await admin.auth().getUser(uid);
    return markPhoneVerifiedCore(admin.firestore(), uid, {
      phoneNumber: user.phoneNumber || "",
      pepper: VERIFY_PHONE_PEPPER.value(),
    });
  },
);

/** A própria pessoa desvincula o telefone: tira do Auth e revoga o selo. */
const unlinkVerifiedPhone = onCall({ region: REGION_CALL }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Login required.");
  await admin.auth().updateUser(uid, { phoneNumber: null });
  return revokeVerificationCore(admin.firestore(), uid, { by: uid, reason: "unlinked_by_user" });
});

const revokeVerification = onCall({ region: REGION_CALL }, async (request) => {
  const db = admin.firestore();
  if (!(await hasAdminPermission(db, request.auth, "verification"))) {
    throw new HttpsError("permission-denied", "not_admin");
  }
  const target = String(request.data?.uid || "").trim();
  if (!target || target.includes("/")) throw new HttpsError("invalid-argument", "uid");
  return revokeVerificationCore(db, target, { by: request.auth.uid, reason: String(request.data?.reason || "admin").slice(0, 120) });
});

/** Ban/apagar conta revoga o selo automaticamente. */
const onUserVerificationGuard = onDocumentUpdated(
  { document: "users/{uid}", region: REGION_TRIGGER },
  async (event) => {
    const after = event.data?.after?.data() || {};
    const before = event.data?.before?.data() || {};
    if (after.verification?.status !== "verified") return;
    const nowBanned = after.isBanned === true || after.moderation?.status === "banned"
      || after.accountDeleted === true;
    const wasBanned = before.isBanned === true || before.moderation?.status === "banned"
      || before.accountDeleted === true;
    if (nowBanned && !wasBanned) {
      await revokeVerificationCore(admin.firestore(), event.params.uid, { by: "system", reason: "banned" });
    }
  },
);

// ---------------- ajustar/perdoar moderação ----------------
/**
 * action: forgive (zera pontos e status) | unmute | remove_points (n) | confirm_ban
 */
async function adjustModerationCore(db, targetUid, action, { by, points } = {}) {
  const strikeRef = db.collection("moderationStrikes").doc(targetUid);
  const userRef = db.collection("users").doc(targetUid);
  const del = admin.firestore.FieldValue.delete();
  if (action === "forgive") {
    await strikeRef.set({ events: [], count: 0, updatedAt: ts() }, { merge: true });
    await userRef.set({ moderation: { status: "ok", level: 0, mutedUntil: del, at: ts(), reason: "admin_forgive" } }, { merge: true });
  } else if (action === "unmute") {
    await userRef.set({ moderation: { status: "ok", mutedUntil: del, at: ts(), reason: "admin_unmute" } }, { merge: true });
  } else if (action === "remove_points") {
    const n = Math.max(1, Math.min(50, Number(points) || 1));
    await db.runTransaction(async (tx) => {
      const s = await tx.get(strikeRef);
      const events = (s.exists && Array.isArray(s.data()?.events) ? s.data().events : []).slice();
      events.sort((a, b) => a - b);
      const next = events.slice(0, Math.max(0, events.length - n));
      tx.set(strikeRef, { events: next, count: next.length, updatedAt: ts() }, { merge: true });
    });
  } else if (action === "confirm_ban") {
    await userRef.set({ isBanned: true, moderation: { status: "banned", level: 4, mutedUntil: del, at: ts(), reason: "admin_confirm" } }, { merge: true });
  } else {
    throw new HttpsError("invalid-argument", "action");
  }
  await audit(db, { action: `moderation_${action}`, targetUid, by: String(by || ""), points: Number(points) || 0 });
  return { ok: true, action };
}

const adjustModeration = onCall({ region: REGION_CALL }, async (request) => {
  const db = admin.firestore();
  if (!(await hasAdminPermission(db, request.auth, "moderation"))) {
    throw new HttpsError("permission-denied", "not_admin");
  }
  const target = String(request.data?.uid || "").trim();
  if (!target || target.includes("/")) throw new HttpsError("invalid-argument", "uid");
  return adjustModerationCore(db, target, String(request.data?.action || ""), {
    by: request.auth.uid,
    points: request.data?.points,
  });
});

// ---------------- bot moderador do grupo ----------------
function isGroupOwnerOrAdmin(group, uid) {
  if (!group || !uid) return false;
  if (String(group.ownerId || "") === uid) return true;
  return Array.isArray(group.admins) && group.admins.map(String).includes(uid);
}

async function updateGroupModBotCore(db, auth, groupId, changesIn) {
  const uid = auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Login required.");
  const gid = String(groupId || "").trim();
  if (!gid || gid.includes("/")) throw new HttpsError("invalid-argument", "groupId");
  let changes;
  try {
    changes = sanitizeBotChanges(changesIn);
  } catch (e) {
    throw new HttpsError("invalid-argument", String(e.message || "invalid"));
  }
  if (changes.rules && (evaluateText(changes.rules, {}) || evaluateProfanity(changes.rules, { loose: false }))) {
    throw new HttpsError("invalid-argument", "content_filter_blocked", { code: "content_filter_blocked" });
  }
  const ref = db.collection("groups").doc(gid);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "group_not_found");
  const g = snap.data() || {};
  if (g.deleted === true || g.isActive === false) throw new HttpsError("failed-precondition", "group_unavailable");
  if (!isGroupOwnerOrAdmin(g, uid) && !isSuperAdminAuth(auth)) {
    throw new HttpsError("permission-denied", "not_group_admin");
  }
  const next = { ...botConfig(g), ...changes, updatedBy: uid, updatedAt: ts() };
  await ref.set({ modBot: next }, { merge: true });
  return { ok: true, modBot: { ...botConfig({ modBot: { ...botConfig(g), ...changes } }) } };
}

// updateGroupModBot é exportado no index.js com socialOnCall (exige adulto verificado).

/** Mensagem de boas-vindas do bot (só quem entrou vê: botFor). */
async function welcomeNewMembersCore(db, groupId, before, after) {
  if (!after || after.deleted === true) return { sent: 0 };
  const bot = botConfig(after);
  if (!bot.welcomeEnabled) return { sent: 0 };
  const prev = new Set((Array.isArray(before?.members) ? before.members : []).map(String));
  const added = (Array.isArray(after.members) ? after.members : []).map(String)
    .filter((u) => u && !prev.has(u) && u !== String(after.ownerId || ""));
  let sent = 0;
  for (const uid of added.slice(0, 20)) {
    const id = `bot_welcome_${uid}`;
    try {
      await db.collection("groups").doc(groupId).collection("messages").doc(id).create({
        type: "bot_welcome",
        bot: true,
        senderId: BOT_SENDER_ID,
        senderName: "Remdy",
        botFor: uid,
        text: bot.rules || "",
        createdAt: ts(),
        deleted: false,
      });
      sent += 1;
    } catch (err) {
      // já recebeu boas-vindas antes (saiu e voltou): reaproveita o mesmo doc.
      if (!(err && (err.code === 6 || err.code === "already-exists"))) throw err;
      await db.collection("groups").doc(groupId).collection("messages").doc(id)
        .set({ text: bot.rules || "", createdAt: ts() }, { merge: true });
      sent += 1;
    }
  }
  return { sent };
}

const onGroupMembersWelcomeBot = onDocumentUpdated(
  { document: "groups/{groupId}", region: REGION_TRIGGER },
  async (event) => {
    await welcomeNewMembersCore(
      admin.firestore(),
      event.params.groupId,
      event.data?.before?.data() || {},
      event.data?.after?.data() || {},
    );
  },
);

module.exports = {
  phoneHash,
  hasAdminPermission,
  markPhoneVerifiedCore,
  revokeVerificationCore,
  adjustModerationCore,
  updateGroupModBotCore,
  welcomeNewMembersCore,
  isGroupOwnerOrAdmin,
  markPhoneVerified,
  unlinkVerifiedPhone,
  revokeVerification,
  onUserVerificationGuard,
  adjustModeration,
  onGroupMembersWelcomeBot,
  toMs,
};
