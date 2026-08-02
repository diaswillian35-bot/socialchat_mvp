/**
 * Premium por convites — concessão somente via Admin SDK.
 * Marcos: 3→1d, 10→7d, 20→30d, 50→60d, 100→90d + embaixador.
 */
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

const MILESTONES = [
  { level: 3, days: 1 },
  { level: 10, days: 7 },
  { level: 20, days: 30 },
  { level: 50, days: 60 },
  { level: 100, days: 90 },
];

function levelForInviteCount(count) {
  const n = Number(count) || 0;
  let level = 0;
  for (const m of MILESTONES) {
    if (n >= m.level) level = m.level;
  }
  return level;
}

function daysForLevel(level) {
  const found = MILESTONES.find((m) => m.level === level);
  return found ? found.days : 0;
}

function parsePremiumUntil(raw) {
  if (!raw) return null;
  if (raw.toDate && typeof raw.toDate === "function") {
    try {
      return raw.toDate();
    } catch (_) {
      return null;
    }
  }
  if (raw instanceof Date) return raw;
  return null;
}

/**
 * Calcula patch de recompensa com base em invitesCount e inviteRewardLevel.
 * Não altera isPremium (assinatura paga).
 */
function buildInviteRewardPatch(inviterData, now = new Date()) {
  const invitesCount =
    typeof inviterData.invitesCount === "number"
      ? inviterData.invitesCount
      : Number(inviterData.invitesCount) || 0;

  const currentRewardLevel =
    typeof inviterData.inviteRewardLevel === "number"
      ? inviterData.inviteRewardLevel
      : Number(inviterData.inviteRewardLevel) || 0;

  const targetLevel = levelForInviteCount(invitesCount);

  if (targetLevel <= currentRewardLevel) {
    return {
      granted: false,
      rewardDays: 0,
      newLevel: currentRewardLevel,
      invitesCount,
      patch: null,
    };
  }

  const rewardDays = daysForLevel(targetLevel);
  if (rewardDays <= 0) {
    return {
      granted: false,
      rewardDays: 0,
      newLevel: currentRewardLevel,
      invitesCount,
      patch: null,
    };
  }

  let baseDate = now;
  const existingUntil = parsePremiumUntil(inviterData.premiumUntil);
  if (existingUntil && existingUntil.getTime() > now.getTime()) {
    baseDate = existingUntil;
  }

  const newPremiumUntil = new Date(
    baseDate.getTime() + rewardDays * 24 * 60 * 60 * 1000
  );

  const patch = {
    premiumUntil: admin.firestore.Timestamp.fromDate(newPremiumUntil),
    premiumType: "trial",
    premiumSource: "invite",
    inviteRewardLevel: targetLevel,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (targetLevel >= 100) {
    patch.isAmbassador = true;
  }

  // Nunca tocar isPremium aqui

  return {
    granted: true,
    rewardDays,
    newLevel: targetLevel,
    invitesCount,
    premiumUntil: newPremiumUntil.toISOString(),
    patch,
  };
}

/**
 * Inviter reivindica recompensas pendentes com base no invitesCount real.
 */
async function claimInvitePremiumRewardHandler(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  const uid = request.auth.uid;
  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);

  try {
    const result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(userRef);
      if (!snap.exists) {
        throw new HttpsError("not-found", "User not found.");
      }

      const data = snap.data() || {};
      if (data.isBanned === true || data.accountDeleted === true) {
        throw new HttpsError("permission-denied", "Account unavailable.");
      }

      const built = buildInviteRewardPatch(data, new Date());

      if (!built.granted || !built.patch) {
        return {
          success: true,
          granted: false,
          alreadyClaimed: true,
          rewardDays: 0,
          inviteRewardLevel: built.newLevel,
          invitesCount: built.invitesCount,
        };
      }

      tx.set(userRef, built.patch, { merge: true });

      return {
        success: true,
        granted: true,
        alreadyClaimed: false,
        rewardDays: built.rewardDays,
        inviteRewardLevel: built.newLevel,
        invitesCount: built.invitesCount,
        premiumUntil: built.premiumUntil,
      };
    });

    console.log(
      JSON.stringify({
        action: "claim_invite_premium_reward",
        uidPrefix: uid.slice(0, 6),
        granted: result.granted,
        rewardDays: result.rewardDays || 0,
        level: result.inviteRewardLevel,
        createdAt: new Date().toISOString(),
      })
    );

    return result;
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("Erro claimInvitePremiumReward:", e);
    throw new HttpsError("internal", "Could not claim invite reward.");
  }
}

/**
 * Convidado aplica código: atribui invitedBy, incrementa invitesCount do
 * convidante e concede recompensa de marco se houver (mesma transaction).
 */
async function applyInviteCodeHandler(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  const inviteeUid = request.auth.uid;
  const inviteCode = (request.data?.inviteCode || request.data?.ref || "")
    .toString()
    .trim();

  if (!inviteCode) {
    throw new HttpsError("invalid-argument", "inviteCode required.");
  }

  const db = admin.firestore();

  const inviterQuery = await db
    .collection("users")
    .where("inviteCode", "==", inviteCode)
    .limit(1)
    .get();

  if (inviterQuery.empty) {
    throw new HttpsError("not-found", "Invite code not found.");
  }

  const inviterUid = inviterQuery.docs[0].id;
  if (inviterUid === inviteeUid) {
    throw new HttpsError("failed-precondition", "Cannot use own invite.");
  }

  const inviteeRef = db.collection("users").doc(inviteeUid);
  const inviterRef = db.collection("users").doc(inviterUid);

  try {
    const result = await db.runTransaction(async (tx) => {
      const inviteeSnap = await tx.get(inviteeRef);
      const inviterSnap = await tx.get(inviterRef);

      if (!inviteeSnap.exists) {
        throw new HttpsError("not-found", "User not found.");
      }
      if (!inviterSnap.exists) {
        throw new HttpsError("not-found", "Inviter not found.");
      }

      const inviteeData = inviteeSnap.data() || {};
      const inviterData = inviterSnap.data() || {};

      if (inviteeData.isBanned === true || inviteeData.accountDeleted === true) {
        throw new HttpsError("permission-denied", "Account unavailable.");
      }
      if (inviterData.isBanned === true || inviterData.accountDeleted === true) {
        throw new HttpsError("failed-precondition", "Inviter unavailable.");
      }

      const already =
        (inviteeData.invitedBy || "").toString().trim().length > 0;
      if (already) {
        return {
          success: true,
          applied: false,
          alreadyApplied: true,
          rewardGranted: false,
          rewardDays: 0,
        };
      }

      const currentInvites =
        typeof inviterData.invitesCount === "number"
          ? inviterData.invitesCount
          : Number(inviterData.invitesCount) || 0;

      const newInvitesCount = currentInvites + 1;

      tx.set(
        inviteeRef,
        {
          invitedBy: inviterUid,
          invitedByCode: inviteCode,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      const inviterPatch = {
        invitesCount: newInvitesCount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      const built = buildInviteRewardPatch(
        { ...inviterData, invitesCount: newInvitesCount },
        new Date()
      );

      if (built.granted && built.patch) {
        Object.assign(inviterPatch, built.patch);
      }

      tx.set(inviterRef, inviterPatch, { merge: true });

      return {
        success: true,
        applied: true,
        alreadyApplied: false,
        rewardGranted: built.granted === true,
        rewardDays: built.rewardDays || 0,
        inviteRewardLevel: built.newLevel,
        invitesCount: newInvitesCount,
        inviterUidPrefix: inviterUid.slice(0, 6),
      };
    });

    console.log(
      JSON.stringify({
        action: "apply_invite_code",
        inviteePrefix: inviteeUid.slice(0, 6),
        applied: result.applied,
        rewardGranted: result.rewardGranted,
        rewardDays: result.rewardDays || 0,
        createdAt: new Date().toISOString(),
      })
    );

    return result;
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("Erro applyInviteCode:", e);
    throw new HttpsError("internal", "Could not apply invite.");
  }
}

exports.claimInvitePremiumReward = onCall(
  { region: "us-central1" },
  claimInvitePremiumRewardHandler
);

exports.applyInviteCode = onCall(
  { region: "us-central1" },
  applyInviteCodeHandler
);
