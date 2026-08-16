const {
  onDocumentCreated,
  onDocumentWritten,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");

const admin = require("firebase-admin");
const { validateOpenJoin } = require("./group_open_join_logic");
function distanceKm(lat1, lon1, lat2, lon2) {
  const R = 6371;

  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c;
}

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
/** Place Details server-side — nunca no app/Git. Configurar via Secret Manager. */
const GOOGLE_PLACES_API_KEY = defineSecret("GOOGLE_PLACES_API_KEY");

const {
  resolveTrustedCityPlace,
} = require("./group_places");
const {
  buildCanonicalGeoFields,
  clientForgedRegionalGeo,
  REGION_RADIUS_KM,
} = require("./group_geo_canonical");

const {
  EVENT_CREATE_ALLOWED,
  EVENT_UPDATE_ALLOWED,
  EVENT_PENDING_EDITORIAL_KEYS,
  resolveEventOwnerUid,
  validateEventEditorial,
  buildEventEditorialPatch: buildEventEditorialPatchCore,
  buildCreateEditorialFields,
  asTrimmedString,
} = require("./event_editorial");
const {
  scheduleSocialImageJob,
  SOCIAL_TRIGGER_FIELDS,
} = require("./event_social_hooks");

function buildEventEditorialPatch(dataIn, editorial) {
  return buildEventEditorialPatchCore(dataIn, editorial, (ms) =>
    admin.firestore.Timestamp.fromMillis(ms),
  );
}

const eventInteractions = require("./event_interactions_helpers");
const {
  normalizeCountryCode: normalizeIsoCountryCode,
} = require("./group_places_logic");

admin.initializeApp();

const { verifiedAdultOnCall } = require("./social_age_guard");
const socialOnCall = (options, handler) => verifiedAdultOnCall(
  onCall,
  options,
  handler,
  { getFirestore: () => admin.firestore(), HttpsError },
);

const { confirmAdultAge } = require("./age_verification");
exports.confirmAdultAge = confirmAdultAge;

const { deleteMyAccount } = require("./delete_my_account");
exports.deleteMyAccount = deleteMyAccount;

const { forwardMessage } = require("./forward_message");
exports.forwardMessage = forwardMessage;

const { sendDmMessage } = require("./send_dm_message");
exports.sendDmMessage = sendDmMessage;

const {
  issueShareExtensionSession,
  revokeShareExtensionSessions,
  listShareDestinations,
  sendShareMessage,
  purgeExpiredShareExtensionData,
} = require("./share_extension");
exports.issueShareExtensionSession = issueShareExtensionSession;
exports.revokeShareExtensionSessions = revokeShareExtensionSessions;
exports.listShareDestinations = listShareDestinations;
exports.sendShareMessage = sendShareMessage;
exports.purgeExpiredShareExtensionData = purgeExpiredShareExtensionData;

// Presença migrou para Realtime Database (onDisconnect).
// NÃO exportar onPublicUserSessionWritten — evita CF a cada heartbeat Firestore.
// Arquivo local: ./presence_aggregate.js (legado; não fazer deploy).
// const { onPublicUserSessionWritten } = require("./presence_aggregate");
// exports.onPublicUserSessionWritten = onPublicUserSessionWritten;

// Contadores/índice derivados — deploy somente quando RTDB estiver ativo:
const {
  onPresenceConnectionWritten,
  reconcilePresenceCounters,
  reconcilePresenceCountersNow,
} = require("./presence_rtdb_counters");
exports.onPresenceConnectionWritten = onPresenceConnectionWritten;
exports.reconcilePresenceCounters = reconcilePresenceCounters;
exports.reconcilePresenceCountersNow = reconcilePresenceCountersNow;

const {
  claimInvitePremiumReward,
  applyInviteCode,
} = require("./invite_premium");
exports.claimInvitePremiumReward = claimInvitePremiumReward;
exports.applyInviteCode = applyInviteCode;

const {
  revenueCatWebhook,
  syncRevenueCatEntitlement,
} = require("./revenuecat_webhook");
exports.revenueCatWebhook = revenueCatWebhook;
exports.syncRevenueCatEntitlement = syncRevenueCatEntitlement;

const { createSearchUsersHandler } = require("./user_search");
// Busca segura de usuários: filtragem server-side, retorna só campos públicos.
exports.searchUsers = socialOnCall(
  { region: "us-central1" },
  createSearchUsersHandler({
    getFirestore: () => admin.firestore(),
    HttpsError,
    documentIdPath: admin.firestore.FieldPath.documentId(),
  }),
);

// Link preview seguro (SSRF-hardened): ver functions/link_preview_logic.js
// para a CACHE POLICY completa.
const { fetchLinkPreview } = require("./link_preview");
exports.fetchLinkPreview = fetchLinkPreview;

const {
  assertUserCanUseRemi,
  validateMessageText: remiValidateMessageText,
  validateRequestId: remiValidateRequestId,
  sanitizeHistory: remiSanitizeHistory,
  sanitizeLanguage: remiSanitizeLanguage,
  sanitizeLanguageCode: remiSanitizeLanguageCode,
  sanitizeGoal: remiSanitizeGoal,
  sanitizeLesson: remiSanitizeLesson,
  formatHistoryForPrompt: remiFormatHistoryForPrompt,
  buildMemoryPromptText: remiBuildMemoryPromptText,
  resolveRemiPlan,
  acquireRemiLock,
  consumeRemiQuota,
  refundRemiQuota,
  getIdempotentResult,
  beginIdempotentRequest,
  completeIdempotentRequest,
  failIdempotentRequest,
  releaseRemiLock,
  assertAppCheckIfEnforced,
  remiSafeLog,
} = require("./remi_usage");
const {
  REMI_MODEL,
  REMI_MAX_OUTPUT_TOKENS,
  buildRemiSystemPrompt,
  estimateApproxTokens,
} = require("./remi_prompt");

const ANDROID_CHANNEL_ID = "high_importance_channel";

function pushAllowed(userData, kind) {
  if (!userData || userData.notifEnabled === false) return false;
  if (userData.ageVerificationStatus !== "verified") return false;
  if (kind === "chat" && userData.notifChat === false) return false;
  if (kind === "group" && userData.notifGroups === false) return false;
  if (kind === "event" && userData.notifEvents === false) return false;
  if (kind === "group_join_request" && userData.notifGroups === false)
    return false;
  return true;
}

async function collectTokensForUid(uid, kind) {
  if (!uid) return [];

  const userSnap = await admin.firestore().collection("users").doc(uid).get();
  if (!userSnap.exists) return [];

  const userData = userSnap.data() || {};
  if (!pushAllowed(userData, kind)) return [];

  const tokens = [];
  const mainToken = (userData.fcmToken || "").toString().trim();
  if (mainToken) tokens.push(mainToken);

  const tokensSnap = await admin
    .firestore()
    .collection("users")
    .doc(uid)
    .collection("fcmTokens")
    .get();

  for (const tokenDoc of tokensSnap.docs) {
    const token = (tokenDoc.data().token || tokenDoc.id || "")
      .toString()
      .trim();
    if (token) tokens.push(token);
  }

  return [...new Set(tokens)];
}

async function collectTokensForUids(uids, kind) {
  const all = [];
  for (const uid of uids) {
    all.push(...(await collectTokensForUid(uid, kind)));
  }
  return [...new Set(all)];
}

function profileImageUrl(data) {
  if (!data) return "";
  const photo = (data.photoUrl || "").toString().trim();
  if (photo.startsWith("http")) return photo;
  const avatar = (data.avatarUrl || "").toString().trim();
  if (avatar.startsWith("http")) return avatar;
  return "";
}

function groupImageUrl(group) {
  if (!group) return "";
  const avatar = (group.avatarUrl || group.photoUrl || group.imageUrl || "")
    .toString()
    .trim();
  if (avatar.startsWith("http")) return avatar;
  return "";
}

function androidPushConfig(imageUrl) {
  const image = (imageUrl || "").toString().trim();
  const notification = {
    sound: "default",
    channelId: ANDROID_CHANNEL_ID,
  };
  if (image.startsWith("http")) {
    notification.imageUrl = image;
  }
  return {
    priority: "high",
    notification,
  };
}

function apnsPushConfig(title, body, imageUrl, badge) {
  const image = (imageUrl || "").toString().trim();
  const hasImage = image.startsWith("http");
  const badgeCount =
    typeof badge === "number" && Number.isFinite(badge) && badge >= 0
      ? Math.floor(badge)
      : 1;
  const config = {
    headers: { "apns-priority": "10" },
    payload: {
      aps: {
        alert: { title, body },
        sound: "default",
        badge: badgeCount,
      },
    },
  };
  if (hasImage) {
    config.payload.aps["mutable-content"] = 1;
    config.fcmOptions = { imageUrl: image };
  }
  return config;
}

function toStringData(data) {
  const out = {};
  for (const [key, value] of Object.entries(data || {})) {
    out[key] = value == null ? "" : String(value);
  }
  return out;
}

function unreadFromMap(unreadMap, uid) {
  if (!unreadMap || typeof unreadMap !== "object") return 0;
  const value = unreadMap[uid];
  if (typeof value === "number" && Number.isFinite(value)) {
    return value > 0 ? value : 0;
  }
  if (typeof value === "string") {
    const n = Number.parseInt(value, 10);
    return Number.isFinite(n) && n > 0 ? n : 0;
  }
  return 0;
}

function userCountryFromData(userData) {
  const home = (userData?.homeCountryCode || "")
    .toString()
    .trim()
    .toLowerCase();
  if (home) return home;
  return (userData?.countryCode || "").toString().trim().toLowerCase();
}

function isPremiumUserData(userData) {
  if (!userData) return false;
  if (userData.isMaster === true) return true;
  if (userData.isPremium === true) return true;
  const until = userData.premiumUntil;
  if (until && typeof until.toDate === "function") {
    return until.toDate().getTime() > Date.now();
  }
  if (typeof until === "string" || typeof until === "number") {
    const ms = new Date(until).getTime();
    return Number.isFinite(ms) && ms > Date.now();
  }
  return false;
}

function groupCountryFromData(groupData) {
  return (groupData?.countryCode || "").toString().trim().toLowerCase();
}

function isInternationalGroupAccess(groupData, userData) {
  if (!groupData) return false;
  if (groupData.isPremiumGroup === true) return true;
  const gc = groupCountryFromData(groupData);
  const uc = userCountryFromData(userData);
  return Boolean(gc && uc && gc !== uc);
}

function assertCanAccessInternationalGroup(groupData, userData) {
  if (!isInternationalGroupAccess(groupData, userData)) return;
  if (isPremiumUserData(userData)) return;
  throw new HttpsError(
    "permission-denied",
    "Premium required for international groups.",
  );
}

/** Conta threads com unread > 0 (DM + grupos), alinhado ao badge do app. */
async function computeAppBadge(uid) {
  const db = admin.firestore();
  let total = 0;
  try {
    const convSnap = await db
      .collection("conversations")
      .where("participants", "array-contains", uid)
      .get();
    for (const doc of convSnap.docs) {
      if (unreadFromMap(doc.data()?.unread, uid) > 0) total += 1;
    }
  } catch (e) {
    console.error("computeAppBadge conversations:", e);
  }
  try {
    const groupSnap = await db
      .collection("groups")
      .where("members", "array-contains", uid)
      .where("deleted", "==", false)
      .get();
    for (const doc of groupSnap.docs) {
      if (unreadFromMap(doc.data()?.unread, uid) > 0) total += 1;
    }
  } catch (e) {
    console.error("computeAppBadge groups:", e);
  }
  return total;
}

async function sendPush({ tokens, title, body, data, imageUrl, badge }) {
  const uniqueTokens = [...new Set((tokens || []).filter(Boolean))];
  if (uniqueTokens.length === 0) return null;

  const image = (imageUrl || "").toString().trim();
  const hasImage = image.startsWith("http");
  const payloadData = toStringData({
    ...(data || {}),
    ...(hasImage ? { imageUrl: image } : {}),
  });

  const notification = { title, body };
  if (hasImage) notification.imageUrl = image;

  const response = await admin.messaging().sendEachForMulticast({
    tokens: uniqueTokens,
    notification,
    data: payloadData,
    android: androidPushConfig(image),
    apns: apnsPushConfig(title, body, image, badge),
  });

  await deleteInvalidTokens(response, uniqueTokens);
  return response;
}

async function sendPushToUids({ uids, title, body, data, imageUrl, prefKey }) {
  const uniqueUids = [...new Set((uids || []).filter(Boolean))];
  if (uniqueUids.length === 0) return null;
  let success = 0;
  let failure = 0;
  for (const uid of uniqueUids) {
    const tokens = await collectTokensForUid(uid, prefKey);
    if (!tokens.length) continue;
    const badge = await computeAppBadge(uid);
    const response = await sendPush({
      tokens,
      title,
      body,
      data,
      imageUrl,
      badge,
    });
    success += response?.successCount ?? 0;
    failure += response?.failureCount ?? 0;
  }
  return { successCount: success, failureCount: failure };
}

async function deleteInvalidTokens(response, tokens) {
  const invalidTokens = [];
  response.responses.forEach((r, index) => {
    if (r.success) return;
    const code = r.error?.code || "";
    if (
      code === "messaging/registration-token-not-registered" ||
      code === "messaging/invalid-registration-token"
    ) {
      invalidTokens.push(tokens[index]);
    }
  });

  if (invalidTokens.length === 0) return;

  try {
    const snap = await admin.firestore().collectionGroup("fcmTokens").get();
    for (const doc of snap.docs) {
      const token = (doc.data().token || doc.id || "").toString().trim();
      if (invalidTokens.includes(token)) {
        await doc.ref.delete();
      }
    }
  } catch (e) {
    console.error("Erro limpando tokens inválidos:", e);
  }
}

exports.onGroupMessageCreated = onDocumentCreated(
  "groups/{groupId}/messages/{msgId}",
  async (event) => {
    try {
      const msg = event.data?.data();
      const groupId = event.params.groupId;
      const msgId = event.params.msgId;
      if (!msg) return;

      // Soft-delete na criação: ignorar.
      if (msg.deleted === true) return;

      const senderId = (msg.senderId || msg.fromUid || "").toString().trim();
      if (!senderId) return;

      const rawType = (msg.type || "text").toString().trim().toLowerCase();
      const type =
        rawType === "audio" || rawType === "image" || rawType === "text"
          ? rawType
          : null;
      if (!type) return;

      let lastMessage = "Nova mensagem";
      if (type === "audio") {
        lastMessage = "🎤 Áudio";
      } else if (type === "image") {
        lastMessage = "📷 Foto";
      } else {
        const text = (msg.text || "").toString().trim();
        lastMessage = (text || "Nova mensagem").slice(0, 200);
      }

      const db = admin.firestore();
      const groupRef = db.collection("groups").doc(groupId);
      const processedRef = db
        .collection("processedGroupMessages")
        .doc(`${groupId}_${msgId}`);

      // Bans ativos (fora da tx — evita query na transaction).
      const bannedSnap = await groupRef
        .collection("bannedUsers")
        .where("isActive", "==", true)
        .get();
      const bannedSet = new Set(
        bannedSnap.docs.map((d) => d.id).filter(Boolean),
      );

      let groupName = "Grupo";
      let groupImage = "";
      let targetUids = [];

      const shouldNotify = await db.runTransaction(async (tx) => {
        const processedSnap = await tx.get(processedRef);
        if (processedSnap.exists) {
          return false;
        }

        const groupSnap = await tx.get(groupRef);
        if (!groupSnap.exists) {
          return false;
        }

        const group = groupSnap.data() || {};
        if (group.deleted === true) {
          return false;
        }

        const members = asUidList(group.members);
        if (!members.includes(senderId)) {
          return false;
        }

        const banSnap = await tx.get(
          groupRef.collection("bannedUsers").doc(senderId),
        );
        if (banSnap.exists && banSnap.data()?.isActive === true) {
          return false;
        }

        groupName = (group.name || "Grupo").toString().trim() || "Grupo";
        groupImage = groupImageUrl(group);

        const patch = {
          lastMessage,
          lastSenderId: senderId,
          lastMessageBy: senderId,
          lastMessageType: type,
          lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          [`unread.${senderId}`]: 0,
        };

        targetUids = [];
        for (const uid of members) {
          if (!uid || uid === senderId) continue;
          if (bannedSet.has(uid)) continue;
          patch[`unread.${uid}`] = admin.firestore.FieldValue.increment(1);
          targetUids.push(uid);
        }

        tx.set(groupRef, patch, { merge: true });
        tx.set(processedRef, {
          groupId,
          messageId: msgId,
          senderId,
          processedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return true;
      });

      if (!shouldNotify) {
        return;
      }

      let senderName = "Alguém";
      try {
        const senderSnap = await db.collection("users").doc(senderId).get();
        const senderData = senderSnap.data() || {};
        const n = (senderData.name || "").toString().trim();
        if (n) senderName = n;
      } catch (_) {}

      if (targetUids.length === 0) return;

      const response = await sendPushToUids({
        uids: targetUids,
        title: groupName,
        body: `${senderName}: ${lastMessage}`,
        imageUrl: groupImage,
        prefKey: "group",
        data: {
          type: "group",
          groupId: groupId,
          groupName: groupName,
          imageUrl: groupImage,
        },
      });

      console.log(
        `Push grupo enviado. Success: ${response?.successCount ?? 0}, Fail: ${response?.failureCount ?? 0}`,
      );
    } catch (e) {
      console.error("Erro onGroupMessageCreated:", e);
    }
  },
);
exports.onPrivateMessageCreated = onDocumentCreated(
  "conversations/{conversationId}/messages/{messageId}",
  async (event) => {
    try {
      const msg = event.data?.data();
      if (!msg) return;

      const conversationId = event.params.conversationId;
      const msgType = (msg.type || "text").toString().trim();

      const senderId = (msg.senderId || msg.fromUid || msg.uid || "")
        .toString()
        .trim();
      if (!senderId) return;

      const convRef = admin
        .firestore()
        .collection("conversations")
        .doc(conversationId);
      const convSnap = await convRef.get();
      if (!convSnap.exists) return;

      const conv = convSnap.data() || {};
      const participants = Array.isArray(conv.participants)
        ? conv.participants
        : Array.isArray(conv.members)
          ? conv.members
          : [];

      const targetUids = participants.filter((uid) => uid && uid !== senderId);
      if (targetUids.length === 0) return;

      // Atualiza resumo no servidor e reabre conversa oculta para destinatários.
      const preview =
        msgType === "audio"
          ? "🎤 Áudio"
          : msgType === "image"
            ? "📷 Foto"
            : (msg.text || "Nova mensagem").toString();

      const unreadPatch = {};
      for (const uid of targetUids) {
        unreadPatch[`unread.${uid}`] = admin.firestore.FieldValue.increment(1);
      }

      await convRef.set(
        {
          lastMessage: preview.slice(0, 200),
          lastMessageType: msgType || "text",
          lastMessageAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          ...unreadPatch,
          hiddenFor: admin.firestore.FieldValue.arrayRemove(...targetUids),
        },
        { merge: true },
      );

      let body = preview;
      let senderName = "Alguém";
      let senderImage = "";
      const senderSnap = await admin
        .firestore()
        .collection("users")
        .doc(senderId)
        .get();
      const senderData = senderSnap.data() || {};
      const senderLabel = (senderData.name || "").toString().trim();
      if (senderLabel) senderName = senderLabel;
      senderImage = profileImageUrl(senderData);

      const uniqueTokens = await collectTokensForUids(targetUids, "chat");
      if (uniqueTokens.length === 0) return;

      const response = await sendPush({
        tokens: uniqueTokens,
        title: senderName,
        body,
        imageUrl: senderImage,
        data: {
          type: "chat",
          conversationId,
          senderId,
          otherUid: senderId,
          otherName: senderName,
          imageUrl: senderImage,
        },
      });

      console.log(
        `Push privado enviado (${conversationId}). Success: ${response?.successCount ?? 0}, Fail: ${response?.failureCount ?? 0}`,
      );
    } catch (e) {
      console.error("Erro onPrivateMessageCreated:", e);
    }
  },
);

exports.askRemi = socialOnCall(
  {
    secrets: [GEMINI_API_KEY],
    region: "us-central1",
    // App Check: NÃO ativar enforceAppCheck até validar tokens Android/iPhone.
    // Soft check opcional: REMI_ENFORCE_APP_CHECK=true (ainda desligado).
  },
  async (request) => {
    const startedAt = Date.now();
    let uid = null;
    let lockHeld = false;
    let quotaReserved = false;
    let requestId = null;
    let replyDelivered = false;
    let plan = "free";
    let approxInputTokens = 0;
    const db = admin.firestore();

    const failAndMaybeRefund = async (errorCategory) => {
      if (quotaReserved && requestId && !replyDelivered) {
        try {
          await refundRemiQuota(db, uid, requestId);
        } catch (refundErr) {
          remiSafeLog("remi_refund_failed", {
            uid,
            status: "refund_error",
            errorCategory: "refund",
            level: "error",
            durationMs: Date.now() - startedAt,
            model: REMI_MODEL,
          });
        }
      }
      if (requestId && uid && !replyDelivered) {
        await failIdempotentRequest(db, uid, requestId);
      }
      remiSafeLog("remi_request_failed", {
        uid,
        plan,
        durationMs: Date.now() - startedAt,
        model: REMI_MODEL,
        status: "error",
        approxInputTokens,
        errorCategory,
      });
    };

    try {
      if (!request.auth || !request.auth.uid) {
        throw new HttpsError("unauthenticated", "REMI_UNAUTHENTICATED");
      }

      uid = request.auth.uid;
      assertAppCheckIfEnforced(request);

      requestId = remiValidateRequestId(request.data?.requestId);
      const text = remiValidateMessageText(request.data?.text);
      const historyItems = remiSanitizeHistory(request.data?.history);
      const history = remiFormatHistoryForPrompt(historyItems);
      // Prefer languageCode; fallback to legacy `language` label.
      const languageCode = remiSanitizeLanguageCode(
        request.data?.languageCode || request.data?.language,
      );
      const uiLanguageCode = remiSanitizeLanguageCode(
        request.data?.uiLanguageCode || request.data?.nativeLanguage || "en",
      );
      const language = remiSanitizeLanguage(languageCode);
      const goal = remiSanitizeGoal(request.data?.goal);
      const lesson = remiSanitizeLesson(request.data?.lesson);
      const showPronunciation = request.data?.showPronunciation === true;
      const memoryPath = `users/${uid}/remi/memory_${languageCode}`;

      // Idempotência: retry com mesmo requestId devolve resultado sem Gemini/quota.
      const earlyHit = await getIdempotentResult(db, uid, requestId);
      if (earlyHit && earlyHit.status === "done") {
        remiSafeLog("remi_success", {
          uid,
          plan,
          durationMs: Date.now() - startedAt,
          model: REMI_MODEL,
          status: "ok",
          idempotentHit: true,
          approxInputTokens: 0,
          approxOutputTokens: estimateApproxTokens(earlyHit.reply),
        });
        return { reply: earlyHit.reply };
      }

      const userSnap = await db.collection("users").doc(uid).get();
      if (!userSnap.exists) {
        throw new HttpsError("failed-precondition", "REMI_USER_NOT_FOUND");
      }
      const userData = userSnap.data() || {};
      assertUserCanUseRemi(userData);
      plan = resolveRemiPlan(userData);

      await acquireRemiLock(db, uid, plan);
      lockHeld = true;

      const begin = await beginIdempotentRequest(db, uid, requestId);
      if (begin.hit) {
        remiSafeLog("remi_success", {
          uid,
          plan,
          durationMs: Date.now() - startedAt,
          model: REMI_MODEL,
          status: "ok",
          idempotentHit: true,
          approxOutputTokens: estimateApproxTokens(begin.reply),
        });
        return { reply: begin.reply };
      }

      // Uma única leitura de memória (isolada por idioma-alvo).
      let memory = null;
      let memoryText = "";
      try {
        const memoryDoc = await db.doc(memoryPath).get();
        if (memoryDoc.exists) {
          memory = memoryDoc.data() || {};
          memoryText = remiBuildMemoryPromptText(memory, historyItems);
        }
      } catch (e) {
        remiSafeLog("remi_memory_read_failed", {
          uid,
          status: "memory_read_error",
          errorCategory: "firestore",
          level: "error",
          durationMs: Date.now() - startedAt,
          model: REMI_MODEL,
        });
      }

      // Reserva cota antes do Gemini (impede concorrência com lock).
      await consumeRemiQuota(db, uid, plan, requestId);
      quotaReserved = true;

      const apiKey = GEMINI_API_KEY.value();
      const prompt = buildRemiSystemPrompt({
        memoryText,
        language,
        languageCode,
        uiLanguageCode,
        goal,
        lesson,
        showPronunciation,
        history,
        text,
      });
      approxInputTokens = estimateApproxTokens(prompt);

      let response;
      try {
        response = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/${REMI_MODEL}:generateContent?key=${apiKey}`,
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
            },
            body: JSON.stringify({
              contents: [
                {
                  role: "user",
                  parts: [{ text: prompt }],
                },
              ],
              generationConfig: {
                temperature: 0.7,
                maxOutputTokens: REMI_MAX_OUTPUT_TOKENS,
              },
            }),
            signal: AbortSignal.timeout(55000),
          },
        );
      } catch (netErr) {
        const isTimeout =
          netErr &&
          (netErr.name === "TimeoutError" ||
            netErr.name === "AbortError" ||
            /timeout/i.test(String(netErr.message || "")));
        await failAndMaybeRefund(isTimeout ? "timeout" : "gemini_network");
        throw new HttpsError("internal", "REMI_TEMPORARY_ERROR");
      }

      let json;
      try {
        json = await response.json();
      } catch (_) {
        await failAndMaybeRefund("gemini_parse");
        throw new HttpsError("internal", "REMI_TEMPORARY_ERROR");
      }

      if (!response.ok) {
        await failAndMaybeRefund("gemini_http");
        throw new HttpsError("internal", "REMI_TEMPORARY_ERROR");
      }

      const reply = (
        json?.candidates?.[0]?.content?.parts?.[0]?.text || ""
      ).toString().trim();

      if (!reply) {
        await failAndMaybeRefund("gemini_empty");
        throw new HttpsError("internal", "REMI_TEMPORARY_ERROR");
      }

      // Resposta válida entregue — NÃO reembolsar cota daqui em diante.
      replyDelivered = true;
      try {
        await completeIdempotentRequest(db, uid, requestId, reply);
      } catch (_) {
        remiSafeLog("remi_idempotency_complete_failed", {
          uid,
          status: "idempotency_write_error",
          errorCategory: "firestore",
          level: "error",
          durationMs: Date.now() - startedAt,
          model: REMI_MODEL,
        });
      }

      try {
        let importantFacts = Array.isArray(memory?.importantFacts)
          ? [...memory.importantFacts]
          : [];

        function addFactIfMatch({ lowerText, fact, patterns }) {
          if (
            patterns.some((p) => lowerText.includes(p)) &&
            !importantFacts.includes(fact)
          ) {
            importantFacts.push(fact);
          }
        }

        const lowerText = text.toLowerCase();

        addFactIfMatch({
          lowerText,
          fact: "Lives in Canada",
          patterns: [
            "eu moro no canad",
            "moro no canad",
            "vivo no canad",
            "estou no canad",
          ],
        });
        addFactIfMatch({
          lowerText,
          fact: "Founder of Remdy",
          patterns: [
            "sou fundador da remdy",
            "sou o fundador da remdy",
            "fundador da remdy",
            "criei a remdy",
            "fundei a remdy",
            "esse aplicativo é meu",
            "esse app é meu",
            "desenvolvi a remdy",
          ],
        });
        addFactIfMatch({
          lowerText,
          fact: "Married",
          patterns: [
            "sou casado",
            "eu sou casado",
            "tenho esposa",
            "minha esposa",
          ],
        });
        addFactIfMatch({
          lowerText,
          fact: "Speaks Portuguese",
          patterns: [
            "falo português",
            "eu falo português",
            "minha língua é português",
          ],
        });
        addFactIfMatch({
          lowerText,
          fact: "Works in Construction",
          patterns: [
            "trabalho na construção",
            "trabalho em construção",
            "sou da construção",
            "trabalho com construção",
          ],
        });

        await db.doc(memoryPath).set(
          {
            learningLanguage: language,
            languageCode,
            lastLesson: lesson,
            lastGoal: goal,
            lastUserMessage: text,
            lastRemiReply: reply,
            importantFacts,
            totalMessages: admin.firestore.FieldValue.increment(1),
            updatedAt: new Date(),
          },
          { merge: true },
        );
      } catch (_) {
        remiSafeLog("remi_memory_write_failed", {
          uid,
          status: "memory_write_error",
          errorCategory: "firestore",
          level: "error",
          durationMs: Date.now() - startedAt,
          model: REMI_MODEL,
        });
      }

      remiSafeLog("remi_success", {
        uid,
        plan,
        durationMs: Date.now() - startedAt,
        model: REMI_MODEL,
        status: "ok",
        approxInputTokens,
        approxOutputTokens: estimateApproxTokens(reply),
        idempotentHit: false,
      });

      return { reply };
    } catch (e) {
      if (e instanceof HttpsError) {
        const alreadyLogged =
          e.message === "REMI_TEMPORARY_ERROR" && quotaReserved;
        if (!alreadyLogged) {
          remiSafeLog("remi_rejected", {
            uid,
            plan,
            durationMs: Date.now() - startedAt,
            model: REMI_MODEL,
            status: "rejected",
            errorCategory: e.message || e.code || "https_error",
          });
        }
        // Falhas de validação/quota/auth: sem refund (cota não reservada ou limite).
        // Falhas pós-cota já tratadas em failAndMaybeRefund.
        if (
          quotaReserved &&
          !replyDelivered &&
          e.message !== "REMI_TEMPORARY_ERROR"
        ) {
          await failAndMaybeRefund("function_error");
        }
        throw e;
      }
      await failAndMaybeRefund("internal");
      throw new HttpsError("internal", "REMI_TEMPORARY_ERROR");
    } finally {
      if (lockHeld && uid) {
        await releaseRemiLock(db, uid);
      }
    }
  },
);

exports.onGroupJoinRequestCreated = onDocumentCreated(
  "groups/{groupId}/pendingRequests/{uid}",
  async (event) => {
    try {
      const req = event.data?.data();
      if (!req) return;

      const status = (req.status || "pending").toString().trim();
      if (status !== "pending") return;

      const groupId = event.params.groupId;
      const requestUid = event.params.uid;

      const groupSnap = await admin
        .firestore()
        .collection("groups")
        .doc(groupId)
        .get();
      if (!groupSnap.exists) return;

      const group = groupSnap.data() || {};
      const groupName = (group.name || "Grupo").toString();
      const admins = Array.isArray(group.admins) ? group.admins : [];
      if (admins.length === 0) return;

      const userName = (req.name || "Alguém").toString();
      const targetAdmins = admins.filter(
        (adminUid) => adminUid && adminUid !== requestUid,
      );
      if (targetAdmins.length === 0) return;

      const uniqueTokens = await collectTokensForUids(
        targetAdmins,
        "group_join_request",
      );
      if (uniqueTokens.length === 0) return;

      const title = "Novo pedido de entrada";
      const body = `${userName} quer entrar no grupo ${groupName}`;

      const response = await sendPush({
        tokens: uniqueTokens,
        title,
        body,
        data: {
          type: "group_join_request",
          groupId,
          requestUid,
        },
      });

      console.log(
        `Push pedido de entrada enviado (${groupId}/${requestUid}). Success: ${response?.successCount ?? 0}, Fail: ${response?.failureCount ?? 0}`,
      );
    } catch (e) {
      console.error("Erro onGroupJoinRequestCreated:", e);
    }
  },
);

async function notifyEventCreator({ creatorUid, title, body, eventId, type }) {
  if (!creatorUid) return;
  const tokens = await collectTokensForUid(creatorUid, "event");
  if (!tokens.length) return;
  const badge = await computeAppBadge(creatorUid);
  await sendPush({
    tokens,
    title,
    body,
    badge,
    data: {
      type: type || "event_moderation",
      eventId: eventId || "",
    },
  });
}

exports.onEventUpdated = onDocumentUpdated(
  "events/{eventId}",
  async (event) => {
    try {
      const eventId = event.params.eventId;
      const before = event.data?.before?.data();
      const data = event.data?.after?.data();

      if (!data) return;

      // likesCount-only (toggleEventLike): sem push, sem fanout, sem revisão.
      if (
        before &&
        eventInteractions.onlyLikesCountChanged(before, data)
      ) {
        return;
      }

      const creatorUid = (
        data.createdBy ||
        data.ownerUid ||
        data.organizerId ||
        ""
      )
        .toString()
        .trim();
      const eventTitle = (data.title || "Seu evento").toString().trim();
      const statusBefore = (before?.status || "")
        .toString()
        .trim()
        .toLowerCase();
      const statusAfter = (data.status || "").toString().trim().toLowerCase();

      // Push ao organizador: aprovado / rejeitado / precisa de alterações.
      if (creatorUid && statusBefore !== statusAfter) {
        if (statusAfter === "approved") {
          await notifyEventCreator({
            creatorUid,
            eventId,
            type: "event_approved",
            title: "Evento aprovado",
            body: `"${eventTitle}" foi aprovado e já pode aparecer no app.`,
          });
        } else if (statusAfter === "rejected") {
          await notifyEventCreator({
            creatorUid,
            eventId,
            type: "event_rejected",
            title: "Evento rejeitado",
            body: `"${eventTitle}" foi rejeitado. Revise e envie novamente.`,
          });
        }
      }

      const pendingBefore = before?.hasPendingChanges === true;
      const pendingAfter = data.hasPendingChanges === true;
      if (creatorUid && pendingBefore && !pendingAfter) {
        const rejectedAtBefore = before?.pendingChangesRejectedAt || null;
        const rejectedAtAfter = data.pendingChangesRejectedAt || null;
        const approvedAtBefore = before?.pendingChangesApprovedAt || null;
        const approvedAtAfter = data.pendingChangesApprovedAt || null;
        if (!rejectedAtBefore && rejectedAtAfter) {
          await notifyEventCreator({
            creatorUid,
            eventId,
            type: "event_needs_changes",
            title: "Alterações solicitadas",
            body: `"${eventTitle}" precisa de ajustes antes de republicar as mudanças.`,
          });
        } else if (!approvedAtBefore && approvedAtAfter) {
          await notifyEventCreator({
            creatorUid,
            eventId,
            type: "event_changes_approved",
            title: "Alterações aprovadas",
            body: `As alterações de "${eventTitle}" foram aprovadas.`,
          });
        }
      } else if (creatorUid && !pendingBefore && pendingAfter) {
        // Organizador enviou alterações — admin é notificado em outro fluxo;
        // aqui confirmamos ao criador que o pedido foi registrado.
        await notifyEventCreator({
          creatorUid,
          eventId,
          type: "event_changes_submitted",
          title: "Alterações enviadas",
          body: `As alterações de "${eventTitle}" foram enviadas para análise.`,
        });
      }

      const wasActive = before?.isActive === true;
      const isActive = data.isActive === true;
      const status = (data.status || "").toString();

      if (wasActive) return;
      if (!isActive) return;
      if (status !== "approved") return;

      const title = (data.title || "Novo evento").toString().trim();
      const city = (data.city || "").toString().trim();
      const category = (data.category || "").toString().trim();
      const countryCode = (data.countryCode || "")
        .toString()
        .trim()
        .toLowerCase();
      // creatorUid já resolvido acima para push ao organizador.

      const eventLat = Number(data.lat || data.latitude);
      const eventLng = Number(data.lng || data.longitude);

      if (!countryCode) return;

      if (!eventLat || !eventLng) {
        console.log("Evento sem lat/lng:", eventId);
        return;
      }

      const radiusKm = 50;

      const tokensByLang = {
        pt: [],
        en: [],
        es: [],
        fr: [],
      };

      const usersSnap = await admin
        .firestore()
        .collection("users")
        .where("homeCountryCode", "==", countryCode)
        .get();
      console.log(
        `Evento ${eventId} - usuários encontrados no país (${countryCode}): ${usersSnap.docs.length}`,
      );

      for (const userDoc of usersSnap.docs) {
        if (userDoc.id === creatorUid) continue;

        const userData = userDoc.data() || {};
        if (!pushAllowed(userData, "event")) continue;

        const lang = (userData.appLanguageCode || userData.languageCode || "pt")
          .toString()
          .substring(0, 2)
          .toLowerCase();

        const finalLang = tokensByLang[lang] ? lang : "pt";

        const userLat = Number(userData.lat || userData.latitude);
        const userLng = Number(userData.lng || userData.longitude);

        if (!userLat || !userLng) continue;

        const distance = distanceKm(eventLat, eventLng, userLat, userLng);
        console.log(
          `${userData.name || userDoc.id} -> ${distance.toFixed(1)} km`,
        );

        if (distance > radiusKm) continue;
        console.log(`✔ Dentro do raio: ${userData.name || userDoc.id}`);

        await userDoc.ref.set(
          {
            hasNewEvents: true,
            lastNewEventId: eventId,
            lastNewEventAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        const userTokens = await collectTokensForUid(userDoc.id, "event");
        if (userTokens.length > 0) {
          tokensByLang[finalLang].push(...userTokens);
        }
      }

      let totalSuccess = 0;
      let totalFail = 0;

      for (const [lang, tokenList] of Object.entries(tokensByLang)) {
        const uniqueTokens = [...new Set(tokenList)];
        if (uniqueTokens.length === 0) continue;

        let pushTitle = "📍 Novo evento perto de você";
        let pushBody = `${title} • Toque para ver detalhes`;

        if (lang === "en") {
          pushTitle = "📍 New event near you";
          pushBody = `${title} • Tap to view details`;
        }

        if (lang === "es") {
          pushTitle = "📍 Nuevo evento cerca de ti";
          pushBody = `${title} • Toca para ver detalles`;
        }

        if (lang === "fr") {
          pushTitle = "📍 Nouvel événement près de vous";
          pushBody = `${title} • Touchez pour voir les détails`;
        }

        const notifTitle = city ? `${pushTitle} (${city})` : pushTitle;
        const notifBody = `${title}${category ? " • " + category : ""}`;

        console.log(
          `Idioma ${lang}: ${uniqueTokens.length} token(s) para envio`,
        );

        const response = await sendPush({
          tokens: uniqueTokens,
          title: notifTitle,
          body: notifBody,
          data: {
            type: "event",
            eventId,
          },
        });

        totalSuccess += response?.successCount ?? 0;
        totalFail += response?.failureCount ?? 0;
      }

      console.log(
        `Push evento enviado. Success: ${totalSuccess}, Fail: ${totalFail}`,
      );
    } catch (e) {
      console.error("Erro onEventUpdated:", e);
    }
  },
);

function normalizeGroupInviteCode(raw) {
  return (raw || "").toString().trim().toUpperCase();
}

function normalizeGroupJoinPolicy(raw) {
  const p = (raw || "open").toString().trim().toLowerCase();
  if (p === "approval" || p === "adminapproval") return "approval";
  if (p === "inviteonly" || p === "invite_only" || p === "invite-only") {
    return "inviteOnly";
  }
  return "open";
}

/**
 * Self-join seguro em grupo aberto.
 *
 * O cliente não atualiza /groups/{groupId}; a transação Admin SDK preserva a
 * lista original exatamente e altera somente members/membersCount/updatedAt.
 */
exports.joinOpenGroup = socialOnCall({ region: "us-central1" }, async (request) => {
  if (!request.auth?.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  const uid = request.auth.uid;
  const groupId = (request.data?.groupId || "").toString().trim();
  if (!groupId || groupId.length > 128) {
    throw new HttpsError("invalid-argument", "Invalid groupId.");
  }

  const db = admin.firestore();
  const groupRef = db.collection("groups").doc(groupId);
  const userRef = db.collection("users").doc(uid);
  const banRef = groupRef.collection("bannedUsers").doc(uid);

  try {
    const result = await db.runTransaction(async (tx) => {
      // Todas as leituras antes da escrita; a transação serializa dois joins.
      const [groupSnap, userSnap, banSnap] = await Promise.all([
        tx.get(groupRef),
        tx.get(userRef),
        tx.get(banRef),
      ]);
      const groupData = groupSnap.data() || {};
      const decision = validateOpenJoin({
        groupExists: groupSnap.exists,
        groupData,
        userExists: userSnap.exists,
        userData: userSnap.data() || {},
        banExists: banSnap.exists,
        banData: banSnap.data() || {},
        uid,
      });

      if (decision.error) {
        throw new HttpsError(decision.error, decision.reason);
      }

      const groupName = (
        groupData.name ||
        groupData.title ||
        "Grupo"
      ).toString();
      if (decision.alreadyMember) {
        return {
          groupId,
          groupName,
          alreadyMember: true,
          joined: false,
        };
      }

      tx.update(groupRef, {
        members: decision.members,
        membersCount: decision.membersCount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        groupId,
        groupName,
        alreadyMember: false,
        joined: true,
      };
    });

    console.log(
      JSON.stringify({
        action: "group_open_join",
        groupId,
        userId: uid,
        joined: result.joined,
        alreadyMember: result.alreadyMember,
        createdAt: new Date().toISOString(),
      }),
    );
    return result;
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    console.error("joinOpenGroup:", error);
    throw new HttpsError("internal", "Could not join group.");
  }
});

/**
 * Entrada segura em grupo inviteOnly via código.
 * Cliente NÃO pode self-join inviteOnly nas Rules — só esta Function (Admin SDK).
 */
exports.joinGroupByInviteCode = socialOnCall(
  {
    region: "us-central1",
  },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const uid = request.auth.uid;
    const code = normalizeGroupInviteCode(request.data?.inviteCode);

    if (!code || code.length < 4 || code.length > 16) {
      throw new HttpsError("invalid-argument", "Invalid invite code.");
    }

    const db = admin.firestore();

    const userSnap = await db.collection("users").doc(uid).get();
    if (!userSnap.exists) {
      throw new HttpsError("failed-precondition", "User profile not found.");
    }

    const userData = userSnap.data() || {};
    if (userData.isBanned === true) {
      throw new HttpsError("permission-denied", "Account is banned.");
    }

    const querySnap = await db
      .collection("groups")
      .where("inviteCode", "==", code)
      .limit(2)
      .get();

    if (querySnap.empty) {
      throw new HttpsError("not-found", "Invite not found.");
    }

    if (querySnap.size > 1) {
      console.error("inviteCode conflict: multiple groups share same code");
      throw new HttpsError("failed-precondition", "Invite code conflict.");
    }

    const groupRef = querySnap.docs[0].ref;

    try {
      const result = await db.runTransaction(async (tx) => {
        const groupSnap = await tx.get(groupRef);
        if (!groupSnap.exists) {
          throw new HttpsError("not-found", "Group not found.");
        }

        const data = groupSnap.data() || {};
        const groupId = groupSnap.id;
        const groupName = (data.name || data.title || "Grupo").toString();

        if (data.deleted === true) {
          throw new HttpsError("failed-precondition", "Group unavailable.");
        }

        const docCode = normalizeGroupInviteCode(data.inviteCode);
        if (!docCode || docCode !== code) {
          throw new HttpsError("not-found", "Invite not found.");
        }

        const policy = normalizeGroupJoinPolicy(data.joinPolicy);
        if (policy !== "inviteOnly") {
          throw new HttpsError(
            "failed-precondition",
            "Group does not accept invite-only join.",
          );
        }

        assertCanAccessInternationalGroup(data, userData);

        const banSnap = await tx.get(
          groupRef.collection("bannedUsers").doc(uid),
        );
        if (banSnap.exists && banSnap.data()?.isActive === true) {
          throw new HttpsError("permission-denied", "Cannot join this group.");
        }

        const membersRaw = Array.isArray(data.members) ? data.members : [];
        const members = membersRaw
          .map((m) => (m || "").toString().trim())
          .filter((m) => m.length > 0);

        if (members.includes(uid)) {
          return {
            groupId,
            groupName,
            alreadyMember: true,
            joined: false,
          };
        }

        members.push(uid);

        tx.set(
          groupRef,
          {
            members,
            membersCount: members.length,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            [`unread.${uid}`]: 0,
          },
          { merge: true },
        );

        return {
          groupId,
          groupName,
          alreadyMember: false,
          joined: true,
        };
      });

      console.log(
        JSON.stringify({
          action: "group_joined_by_invite",
          groupId: result.groupId,
          userId: uid,
          alreadyMember: result.alreadyMember,
          joined: result.joined,
          createdAt: new Date().toISOString(),
        }),
      );

      return result;
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("Erro joinGroupByInviteCode:", e);
      throw new HttpsError("internal", "Could not join group.");
    }
  },
);

function asUidList(raw) {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((m) => (m || "").toString().trim())
    .filter((m) => m.length > 0);
}

function isGroupOwnerOrAdminData(data, uid) {
  if (!data || !uid) return false;
  if ((data.ownerId || "").toString() === uid) return true;
  const admins = asUidList(data.admins);
  return admins.includes(uid);
}

/**
 * Banir membro do grupo (owner/admin). Admin SDK — cliente não escreve bannedUsers.
 */
exports.banGroupMember = socialOnCall({ region: "us-central1" }, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  const actorUid = request.auth.uid;
  const groupId = (request.data?.groupId || "").toString().trim();
  const targetUid = (request.data?.targetUid || "").toString().trim();
  const reason = (request.data?.reason || "").toString().trim().slice(0, 300);

  if (!groupId || !targetUid) {
    throw new HttpsError("invalid-argument", "groupId and targetUid required.");
  }
  if (actorUid === targetUid) {
    throw new HttpsError("failed-precondition", "Cannot ban yourself.");
  }

  const db = admin.firestore();
  const groupRef = db.collection("groups").doc(groupId);
  const banRef = groupRef.collection("bannedUsers").doc(targetUid);
  const pendingRef = groupRef.collection("pendingRequests").doc(targetUid);
  const actorRef = db.collection("users").doc(actorUid);
  const targetRef = db.collection("users").doc(targetUid);

  try {
    const result = await db.runTransaction(async (tx) => {
      const groupSnap = await tx.get(groupRef);
      const actorSnap = await tx.get(actorRef);
      const targetSnap = await tx.get(targetRef);
      const banSnap = await tx.get(banRef);
      const pendingSnap = await tx.get(pendingRef);

      if (!groupSnap.exists) {
        throw new HttpsError("not-found", "Group not found.");
      }

      const data = groupSnap.data() || {};
      if (data.deleted === true) {
        throw new HttpsError("failed-precondition", "Group unavailable.");
      }

      if (!isGroupOwnerOrAdminData(data, actorUid)) {
        throw new HttpsError("permission-denied", "Not allowed.");
      }

      const ownerId = (data.ownerId || "").toString().trim();
      if (targetUid === ownerId) {
        throw new HttpsError("failed-precondition", "Cannot ban the owner.");
      }

      if (!actorSnap.exists) {
        throw new HttpsError("failed-precondition", "Actor profile missing.");
      }
      const actorData = actorSnap.data() || {};
      if (actorData.isBanned === true) {
        throw new HttpsError("permission-denied", "Account is banned.");
      }
      const actorName = (actorData.name || "").toString().trim() || "Admin";

      const targetData = targetSnap.exists ? targetSnap.data() || {} : {};
      const targetName = (targetData.name || "").toString().trim() || "User";
      const targetPhoto = (
        targetData.photoUrl ||
        targetData.avatarUrl ||
        ""
      ).toString();

      let members = asUidList(data.members);
      let admins = asUidList(data.admins);
      const wasMember = members.includes(targetUid);

      members = members.filter((m) => m !== targetUid);
      admins = admins.filter((a) => a !== targetUid);

      const patch = {
        members,
        admins,
        membersCount: members.length,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        [`unread.${targetUid}`]: admin.firestore.FieldValue.delete(),
      };

      tx.set(groupRef, patch, { merge: true });

      tx.set(
        banRef,
        {
          uid: targetUid,
          name: targetName,
          photoUrl: targetPhoto,
          reason,
          bannedAt: admin.firestore.FieldValue.serverTimestamp(),
          bannedBy: actorUid,
          bannedByName: actorName,
          isActive: true,
          unbannedAt: null,
          unbannedBy: "",
          unbannedByName: "",
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      if (pendingSnap.exists) {
        const p = pendingSnap.data() || {};
        if ((p.status || "").toString().trim() === "pending") {
          tx.set(
            pendingRef,
            {
              status: "rejected",
              rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
              rejectedBy: actorUid,
              rejectionReason: "banned",
            },
            { merge: true },
          );
        }
      }

      return {
        groupId,
        targetUid,
        wasMember,
        alreadyBanned: banSnap.exists && banSnap.data()?.isActive === true,
      };
    });

    console.log(
      JSON.stringify({
        action: "group_member_banned",
        groupId,
        targetUid,
        performedBy: actorUid,
        reason: reason ? "[set]" : "",
        createdAt: new Date().toISOString(),
      }),
    );

    return { success: true, ...result };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("Erro banGroupMember:", e);
    throw new HttpsError("internal", "Could not ban member.");
  }
});

/**
 * Desbanir membro — não readiciona em members.
 */
exports.unbanGroupMember = socialOnCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const actorUid = request.auth.uid;
    const groupId = (request.data?.groupId || "").toString().trim();
    const targetUid = (request.data?.targetUid || "").toString().trim();

    if (!groupId || !targetUid) {
      throw new HttpsError(
        "invalid-argument",
        "groupId and targetUid required.",
      );
    }

    const db = admin.firestore();
    const groupRef = db.collection("groups").doc(groupId);
    const banRef = groupRef.collection("bannedUsers").doc(targetUid);
    const actorRef = db.collection("users").doc(actorUid);

    try {
      const result = await db.runTransaction(async (tx) => {
        const groupSnap = await tx.get(groupRef);
        const actorSnap = await tx.get(actorRef);
        const banSnap = await tx.get(banRef);

        if (!groupSnap.exists) {
          throw new HttpsError("not-found", "Group not found.");
        }

        const data = groupSnap.data() || {};
        if (data.deleted === true) {
          throw new HttpsError("failed-precondition", "Group unavailable.");
        }

        if (!isGroupOwnerOrAdminData(data, actorUid)) {
          throw new HttpsError("permission-denied", "Not allowed.");
        }

        if (!actorSnap.exists) {
          throw new HttpsError("failed-precondition", "Actor profile missing.");
        }
        const actorData = actorSnap.data() || {};
        if (actorData.isBanned === true) {
          throw new HttpsError("permission-denied", "Account is banned.");
        }
        const actorName = (actorData.name || "").toString().trim() || "Admin";

        if (!banSnap.exists) {
          throw new HttpsError("not-found", "Ban record not found.");
        }

        const banData = banSnap.data() || {};
        if (banData.isActive !== true) {
          return {
            groupId,
            targetUid,
            alreadyUnbanned: true,
          };
        }

        tx.set(
          banRef,
          {
            isActive: false,
            unbannedAt: admin.firestore.FieldValue.serverTimestamp(),
            unbannedBy: actorUid,
            unbannedByName: actorName,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        return {
          groupId,
          targetUid,
          alreadyUnbanned: false,
        };
      });

      console.log(
        JSON.stringify({
          action: "group_member_unbanned",
          groupId,
          targetUid,
          performedBy: actorUid,
          createdAt: new Date().toISOString(),
        }),
      );

      return { success: true, ...result };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("Erro unbanGroupMember:", e);
      throw new HttpsError("internal", "Could not unban member.");
    }
  },
);

/**
 * Promover membro a admin — somente owner.
 */
exports.promoteGroupAdmin = socialOnCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const actorUid = request.auth.uid;
    const groupId = (request.data?.groupId || "").toString().trim();
    const targetUid = (request.data?.targetUid || "").toString().trim();

    if (!groupId || !targetUid) {
      throw new HttpsError(
        "invalid-argument",
        "groupId and targetUid required.",
      );
    }

    const db = admin.firestore();
    const groupRef = db.collection("groups").doc(groupId);
    const banRef = groupRef.collection("bannedUsers").doc(targetUid);
    const actorRef = db.collection("users").doc(actorUid);

    try {
      const result = await db.runTransaction(async (tx) => {
        const groupSnap = await tx.get(groupRef);
        const actorSnap = await tx.get(actorRef);
        const banSnap = await tx.get(banRef);

        if (!groupSnap.exists) {
          throw new HttpsError("not-found", "Group not found.");
        }

        const data = groupSnap.data() || {};
        if (data.deleted === true) {
          throw new HttpsError("failed-precondition", "Group unavailable.");
        }

        const ownerId = (data.ownerId || "").toString().trim();
        if (actorUid !== ownerId) {
          throw new HttpsError("permission-denied", "Only owner can promote.");
        }

        if (!actorSnap.exists || actorSnap.data()?.isBanned === true) {
          throw new HttpsError("permission-denied", "Not allowed.");
        }

        if (targetUid === ownerId) {
          throw new HttpsError(
            "failed-precondition",
            "Owner is already admin.",
          );
        }

        if (banSnap.exists && banSnap.data()?.isActive === true) {
          throw new HttpsError("failed-precondition", "Target is banned.");
        }

        const members = asUidList(data.members);
        let admins = asUidList(data.admins);

        if (!members.includes(targetUid)) {
          throw new HttpsError(
            "failed-precondition",
            "Target is not a member.",
          );
        }

        if (admins.includes(targetUid)) {
          return { groupId, targetUid, alreadyAdmin: true };
        }

        admins.push(targetUid);

        tx.set(
          groupRef,
          {
            admins,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        return { groupId, targetUid, alreadyAdmin: false };
      });

      console.log(
        JSON.stringify({
          action: "group_admin_promoted",
          groupId,
          targetUid,
          performedBy: actorUid,
          createdAt: new Date().toISOString(),
        }),
      );

      return { success: true, ...result };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("Erro promoteGroupAdmin:", e);
      throw new HttpsError("internal", "Could not promote admin.");
    }
  },
);

/**
 * Rebaixar admin para membro — somente owner.
 */
exports.demoteGroupAdmin = socialOnCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const actorUid = request.auth.uid;
    const groupId = (request.data?.groupId || "").toString().trim();
    const targetUid = (request.data?.targetUid || "").toString().trim();

    if (!groupId || !targetUid) {
      throw new HttpsError(
        "invalid-argument",
        "groupId and targetUid required.",
      );
    }

    const db = admin.firestore();
    const groupRef = db.collection("groups").doc(groupId);
    const actorRef = db.collection("users").doc(actorUid);

    try {
      const result = await db.runTransaction(async (tx) => {
        const groupSnap = await tx.get(groupRef);
        const actorSnap = await tx.get(actorRef);

        if (!groupSnap.exists) {
          throw new HttpsError("not-found", "Group not found.");
        }

        const data = groupSnap.data() || {};
        if (data.deleted === true) {
          throw new HttpsError("failed-precondition", "Group unavailable.");
        }

        const ownerId = (data.ownerId || "").toString().trim();
        if (actorUid !== ownerId) {
          throw new HttpsError("permission-denied", "Only owner can demote.");
        }

        if (!actorSnap.exists || actorSnap.data()?.isBanned === true) {
          throw new HttpsError("permission-denied", "Not allowed.");
        }

        if (targetUid === ownerId) {
          throw new HttpsError(
            "failed-precondition",
            "Cannot demote the owner.",
          );
        }

        const members = asUidList(data.members);
        let admins = asUidList(data.admins);

        if (!admins.includes(targetUid)) {
          return { groupId, targetUid, alreadyMemberOnly: true };
        }

        if (!members.includes(targetUid)) {
          throw new HttpsError(
            "failed-precondition",
            "Target is not a member.",
          );
        }

        admins = admins.filter((a) => a !== targetUid);

        tx.set(
          groupRef,
          {
            admins,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        return { groupId, targetUid, alreadyMemberOnly: false };
      });

      console.log(
        JSON.stringify({
          action: "group_admin_demoted",
          groupId,
          targetUid,
          performedBy: actorUid,
          createdAt: new Date().toISOString(),
        }),
      );

      return { success: true, ...result };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("Erro demoteGroupAdmin:", e);
      throw new HttpsError("internal", "Could not demote admin.");
    }
  },
);

/**
 * Remover membro do grupo (sem banir).
 * Owner: pode remover membro ou admin.
 * Admin: só membro comum.
 */
exports.removeGroupMember = socialOnCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const actorUid = request.auth.uid;
    const groupId = (request.data?.groupId || "").toString().trim();
    const targetUid = (request.data?.targetUid || "").toString().trim();

    if (!groupId || !targetUid) {
      throw new HttpsError(
        "invalid-argument",
        "groupId and targetUid required.",
      );
    }
    if (actorUid === targetUid) {
      throw new HttpsError("failed-precondition", "Use leave group instead.");
    }

    const db = admin.firestore();
    const groupRef = db.collection("groups").doc(groupId);
    const actorRef = db.collection("users").doc(actorUid);

    try {
      const result = await db.runTransaction(async (tx) => {
        const groupSnap = await tx.get(groupRef);
        const actorSnap = await tx.get(actorRef);

        if (!groupSnap.exists) {
          throw new HttpsError("not-found", "Group not found.");
        }

        const data = groupSnap.data() || {};
        if (data.deleted === true) {
          throw new HttpsError("failed-precondition", "Group unavailable.");
        }

        if (!isGroupOwnerOrAdminData(data, actorUid)) {
          throw new HttpsError("permission-denied", "Not allowed.");
        }

        if (!actorSnap.exists || actorSnap.data()?.isBanned === true) {
          throw new HttpsError("permission-denied", "Not allowed.");
        }

        const ownerId = (data.ownerId || "").toString().trim();
        if (targetUid === ownerId) {
          throw new HttpsError(
            "failed-precondition",
            "Cannot remove the owner.",
          );
        }

        let members = asUidList(data.members);
        let admins = asUidList(data.admins);
        const targetIsAdmin = admins.includes(targetUid);
        const actorIsOwner = actorUid === ownerId;

        if (!members.includes(targetUid) && !targetIsAdmin) {
          return { groupId, targetUid, alreadyRemoved: true };
        }

        if (!actorIsOwner && targetIsAdmin) {
          throw new HttpsError(
            "permission-denied",
            "Admin cannot remove another admin.",
          );
        }

        members = members.filter((m) => m !== targetUid);
        admins = admins.filter((a) => a !== targetUid);

        tx.set(
          groupRef,
          {
            members,
            admins,
            membersCount: members.length,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            [`unread.${targetUid}`]: admin.firestore.FieldValue.delete(),
          },
          { merge: true },
        );

        return {
          groupId,
          targetUid,
          alreadyRemoved: false,
          wasAdmin: targetIsAdmin,
        };
      });

      console.log(
        JSON.stringify({
          action: "group_member_removed",
          groupId,
          targetUid,
          performedBy: actorUid,
          createdAt: new Date().toISOString(),
        }),
      );

      return { success: true, ...result };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("Erro removeGroupMember:", e);
      throw new HttpsError("internal", "Could not remove member.");
    }
  },
);

/**
 * Transferir ownership do grupo — somente owner atual.
 * newOwnerUid deve ser membro (e preferencialmente admin).
 */
exports.transferGroupOwnership = socialOnCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const uid = request.auth.uid;
    const groupId = (request.data?.groupId || "").toString().trim();
    const newOwnerUid = (request.data?.newOwnerUid || "").toString().trim();
    if (!groupId || !newOwnerUid) {
      throw new HttpsError(
        "invalid-argument",
        "groupId and newOwnerUid required.",
      );
    }
    if (uid === newOwnerUid) {
      throw new HttpsError("failed-precondition", "Already the owner.");
    }

    const db = admin.firestore();
    const groupRef = db.collection("groups").doc(groupId);
    const actorRef = db.collection("users").doc(uid);

    try {
      const result = await db.runTransaction(async (tx) => {
        const groupSnap = await tx.get(groupRef);
        const actorSnap = await tx.get(actorRef);
        if (!groupSnap.exists) {
          throw new HttpsError("not-found", "Group not found.");
        }
        const data = groupSnap.data() || {};
        if (data.deleted === true) {
          throw new HttpsError("failed-precondition", "Group unavailable.");
        }
        if (!actorSnap.exists || actorSnap.data()?.isBanned === true) {
          throw new HttpsError("permission-denied", "Not allowed.");
        }
        const ownerId = (data.ownerId || "").toString().trim();
        if (uid !== ownerId) {
          throw new HttpsError(
            "permission-denied",
            "Only owner can transfer ownership.",
          );
        }

        let members = asUidList(data.members);
        let admins = asUidList(data.admins);
        if (!members.includes(newOwnerUid)) {
          throw new HttpsError(
            "failed-precondition",
            "New owner must be a member.",
          );
        }

        if (!admins.includes(newOwnerUid)) {
          admins.push(newOwnerUid);
        }
        // Mantém o antigo owner como admin.
        if (!admins.includes(uid)) {
          admins.push(uid);
        }

        tx.set(
          groupRef,
          {
            ownerId: newOwnerUid,
            admins,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedBy: uid,
          },
          { merge: true },
        );

        return { groupId, previousOwnerId: uid, newOwnerUid };
      });

      console.log(
        JSON.stringify({
          action: "group_ownership_transferred",
          ...result,
          createdAt: new Date().toISOString(),
        }),
      );
      return { success: true, ...result };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("Erro transferGroupOwnership:", e);
      throw new HttpsError("internal", "Could not transfer ownership.");
    }
  },
);

/**
 * Saída voluntária — membro/admin (não owner).
 */
exports.leaveGroup = socialOnCall({ region: "us-central1" }, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  const uid = request.auth.uid;
  const groupId = (request.data?.groupId || "").toString().trim();
  if (!groupId) {
    throw new HttpsError("invalid-argument", "groupId required.");
  }

  const db = admin.firestore();
  const groupRef = db.collection("groups").doc(groupId);
  const userRef = db.collection("users").doc(uid);

  try {
    const result = await db.runTransaction(async (tx) => {
      const groupSnap = await tx.get(groupRef);
      const userSnap = await tx.get(userRef);

      if (!groupSnap.exists) {
        throw new HttpsError("not-found", "Group not found.");
      }

      const data = groupSnap.data() || {};
      if (data.deleted === true) {
        return { groupId, alreadyLeft: true, deleted: true };
      }

      if (userSnap.exists && userSnap.data()?.isBanned === true) {
        throw new HttpsError("permission-denied", "Account is banned.");
      }

      const ownerId = (data.ownerId || "").toString().trim();
      if (uid === ownerId) {
        throw new HttpsError(
          "failed-precondition",
          "Owner cannot leave the group.",
        );
      }

      let members = asUidList(data.members);
      let admins = asUidList(data.admins);
      const wasMember = members.includes(uid);
      const wasAdmin = admins.includes(uid);

      if (!wasMember && !wasAdmin) {
        return { groupId, alreadyLeft: true, deleted: false };
      }

      members = members.filter((m) => m !== uid);
      admins = admins.filter((a) => a !== uid);

      tx.set(
        groupRef,
        {
          members,
          admins,
          membersCount: members.length,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          [`unread.${uid}`]: admin.firestore.FieldValue.delete(),
        },
        { merge: true },
      );

      return {
        groupId,
        alreadyLeft: false,
        deleted: false,
        wasMember,
        wasAdmin,
      };
    });

    // Limpeza idempotente de subcoleções (fora da transação).
    try {
      await groupRef.collection("presence").doc(uid).delete();
    } catch (_) {}
    try {
      await groupRef.collection("reads").doc(uid).delete();
    } catch (_) {}

    console.log(
      JSON.stringify({
        action: "group_member_left",
        groupId,
        performedBy: uid,
        createdAt: new Date().toISOString(),
      }),
    );

    return { success: true, ...result };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("Erro leaveGroup:", e);
    throw new HttpsError("internal", "Could not leave group.");
  }
});

/**
 * Exclusão lógica do grupo — somente owner.
 */
exports.deleteGroup = socialOnCall({ region: "us-central1" }, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  const uid = request.auth.uid;
  const groupId = (request.data?.groupId || "").toString().trim();
  if (!groupId) {
    throw new HttpsError("invalid-argument", "groupId required.");
  }

  const db = admin.firestore();
  const groupRef = db.collection("groups").doc(groupId);
  const userRef = db.collection("users").doc(uid);

  try {
    const result = await db.runTransaction(async (tx) => {
      const groupSnap = await tx.get(groupRef);
      const userSnap = await tx.get(userRef);

      if (!groupSnap.exists) {
        throw new HttpsError("not-found", "Group not found.");
      }

      const data = groupSnap.data() || {};
      const ownerId = (data.ownerId || "").toString().trim();

      if (uid !== ownerId) {
        throw new HttpsError("permission-denied", "Only owner can delete.");
      }

      if (userSnap.exists && userSnap.data()?.isBanned === true) {
        throw new HttpsError("permission-denied", "Account is banned.");
      }

      if (data.deleted === true) {
        return { groupId, alreadyDeleted: true };
      }

      tx.set(
        groupRef,
        {
          deleted: true,
          isActive: false,
          deletedAt: admin.firestore.FieldValue.serverTimestamp(),
          deletedBy: uid,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      return { groupId, alreadyDeleted: false };
    });

    // Limpa presence do owner (best-effort).
    try {
      await groupRef.collection("presence").doc(uid).delete();
    } catch (_) {}

    console.log(
      JSON.stringify({
        action: "group_deleted",
        groupId,
        performedBy: uid,
        createdAt: new Date().toISOString(),
      }),
    );

    return { success: true, ...result };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("Erro deleteGroup:", e);
    throw new HttpsError("internal", "Could not delete group.");
  }
});

function normalizeJoinPolicyStrict(raw) {
  const p = (raw || "").toString().trim();
  if (p === "open" || p === "approval" || p === "inviteOnly") return p;
  return null;
}

const GROUP_SETTINGS_SHARED = new Set([
  "bio",
  "isPrivate",
  "joinPolicy",
  "avatarUrl",
  "avatarPath",
]);

const GROUP_SETTINGS_OWNER_ONLY = new Set([
  "name",
  "scope",
  "city",
  "cityName",
  "cityKey",
  "country",
  "countryCode",
  "stateName",
  "displayLocation",
  "placeId",
  // latitude/longitude/regionCenter* NÃO são editáveis diretamente:
  // o servidor deriva de placeId via Places Details.
  "regionKey",
]);

const GROUP_SETTINGS_FORBIDDEN = new Set([
  "ownerId",
  "admins",
  "members",
  "membersCount",
  "unread",
  "createdAt",
  "deleted",
  "deletedAt",
  "deletedBy",
  "isActive",
  "inviteCode",
  "lastMessage",
  "lastSenderId",
  "lastMessageAt",
]);

/**
 * Edição segura de configurações do grupo (allowlist).
 */
exports.updateGroupSettings = socialOnCall(
  { region: "us-central1", secrets: [GOOGLE_PLACES_API_KEY] },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const actorUid = request.auth.uid;
    const groupId = (request.data?.groupId || "").toString().trim();
    const changesIn = request.data?.changes;

    if (!groupId) {
      throw new HttpsError("invalid-argument", "groupId required.");
    }
    if (
      !changesIn ||
      typeof changesIn !== "object" ||
      Array.isArray(changesIn)
    ) {
      throw new HttpsError("invalid-argument", "changes object required.");
    }

    const keys = Object.keys(changesIn);
    if (keys.length === 0) {
      throw new HttpsError("invalid-argument", "No changes provided.");
    }

    // Cliente não pode gravar centro/geohash/raio diretamente.
    const blockedDirectGeo = [
      "regionCenterLat",
      "regionCenterLng",
      "regionCenterGeohash",
      "regionRadiusKm",
      "regionCenterCity",
      "regionCenterCountryCode",
      "latitude",
      "longitude",
    ];
    for (const key of keys) {
      if (GROUP_SETTINGS_FORBIDDEN.has(key) || blockedDirectGeo.includes(key)) {
        throw new HttpsError("invalid-argument", `Field not allowed: ${key}`);
      }
    }

    const db = admin.firestore();
    const groupRef = db.collection("groups").doc(groupId);
    const actorRef = db.collection("users").doc(actorUid);

    const geoKeys = new Set([
      "scope",
      "city",
      "cityName",
      "cityKey",
      "country",
      "countryCode",
      "stateName",
      "displayLocation",
      "placeId",
      "regionKey",
    ]);
    const geoTouched = keys.some((k) => geoKeys.has(k));

    try {
      const groupSnapPre = await groupRef.get();
      if (!groupSnapPre.exists) {
        throw new HttpsError("not-found", "Group not found.");
      }
      const dataPre = groupSnapPre.data() || {};
      if (dataPre.deleted === true || dataPre.isActive === false) {
        throw new HttpsError("failed-precondition", "Group unavailable.");
      }

      let trustedPlace = null;
      let canonicalGeo = null;
      if (geoTouched) {
        const nextScope = (
          changesIn.scope !== undefined ? changesIn.scope : dataPre.scope || "city"
        )
          .toString()
          .trim();
        if (!["city", "region", "country"].includes(nextScope)) {
          throw new HttpsError("invalid-argument", "Invalid scope.");
        }
        const nextCountryCode = normalizeIsoCountryCode(
          changesIn.countryCode !== undefined
            ? changesIn.countryCode
            : dataPre.countryCode || dataPre.country,
        );
        const nextCountryName = (
          changesIn.country !== undefined
            ? changesIn.country
            : dataPre.country || ""
        )
          .toString()
          .trim();
        const nextPlaceId = (
          changesIn.placeId !== undefined
            ? changesIn.placeId
            : dataPre.placeId || ""
        )
          .toString()
          .trim();

        if (nextScope === "country") {
          if (!nextCountryCode || !nextCountryName) {
            throw new HttpsError("invalid-argument", "Invalid location.");
          }
          canonicalGeo = buildCanonicalGeoFields("country", {
            countryCode: nextCountryCode,
            countryName: nextCountryName,
          });
        } else {
          if (!nextPlaceId) {
            throw new HttpsError("invalid-argument", "placeId required.");
          }
          if (!nextCountryCode) {
            throw new HttpsError("invalid-argument", "Invalid country.");
          }
          try {
            const resolved = await resolveTrustedCityPlace({
              placeId: nextPlaceId,
              expectedCountryCode: nextCountryCode,
              apiKey: GOOGLE_PLACES_API_KEY.value(),
              db,
            });
            trustedPlace = resolved.place;
          } catch (placeErr) {
            throw mapPlacesError(placeErr);
          }
          canonicalGeo = buildCanonicalGeoFields(nextScope, {
            place: trustedPlace,
            countryName: nextCountryName || trustedPlace.countryName,
            countryCode: nextCountryCode,
            stateName:
              changesIn.stateName !== undefined
                ? changesIn.stateName
                : dataPre.stateName || "",
            displayLocation:
              changesIn.displayLocation !== undefined
                ? changesIn.displayLocation
                : dataPre.displayLocation || "",
          });
        }
      }

      const result = await db.runTransaction(async (tx) => {
        const groupSnap = await tx.get(groupRef);
        const actorSnap = await tx.get(actorRef);

        if (!groupSnap.exists) {
          throw new HttpsError("not-found", "Group not found.");
        }

        const data = groupSnap.data() || {};
        if (data.deleted === true) {
          throw new HttpsError("failed-precondition", "Group unavailable.");
        }

        if (!actorSnap.exists || actorSnap.data()?.isBanned === true) {
          throw new HttpsError("permission-denied", "Not allowed.");
        }
        if (
          Object.prototype.hasOwnProperty.call(actorSnap.data() || {}, "isActive") &&
          actorSnap.data().isActive === false
        ) {
          throw new HttpsError("permission-denied", "Account is disabled.");
        }

        const ownerId = (data.ownerId || "").toString().trim();
        const isOwner = actorUid === ownerId;
        const isAdmin = isGroupOwnerOrAdminData(data, actorUid);

        if (!isAdmin) {
          throw new HttpsError("permission-denied", "Not allowed to edit.");
        }

        const actorName =
          (actorSnap.data()?.name || "").toString().trim() || "Admin";
        const patch = {};
        const changedFields = [];

        for (const key of keys) {
          const shared = GROUP_SETTINGS_SHARED.has(key);
          const ownerOnly = GROUP_SETTINGS_OWNER_ONLY.has(key);

          if (!shared && !ownerOnly) {
            throw new HttpsError("invalid-argument", `Unknown field: ${key}`);
          }
          if (ownerOnly && !isOwner) {
            throw new HttpsError(
              "permission-denied",
              `Only owner can edit: ${key}`,
            );
          }

          // Campos geo são aplicados via canonicalGeo (owner-only).
          if (geoKeys.has(key)) {
            if (!isOwner) {
              throw new HttpsError(
                "permission-denied",
                `Only owner can edit: ${key}`,
              );
            }
            continue;
          }

          let value = changesIn[key];

          if (key === "name") {
            const name = (value || "").toString().trim();
            if (!name) {
              throw new HttpsError("invalid-argument", "Name is required.");
            }
            if (name.length > 80) {
              throw new HttpsError("invalid-argument", "Name too long.");
            }
            value = name;
          } else if (key === "bio") {
            const bio = (value || "").toString().trim();
            if (bio.length > 1000) {
              throw new HttpsError("invalid-argument", "Bio too long.");
            }
            value = bio;
          } else if (key === "joinPolicy") {
            const policy = normalizeJoinPolicyStrict(value);
            if (!policy) {
              throw new HttpsError("invalid-argument", "Invalid joinPolicy.");
            }
            value = policy;
            patch.isPrivate = policy !== "open";
          } else if (key === "isPrivate") {
            value = value === true;
          } else if (key === "avatarUrl" || key === "avatarPath") {
            const s = (value || "").toString().trim();
            if (s) {
              const encoded = encodeURIComponent(`groups/${groupId}/`);
              const plain = `groups/${groupId}/`;
              const ok =
                s.startsWith(plain) ||
                s.includes(encoded) ||
                s.includes(`/groups/${groupId}/`) ||
                s.includes(`groups%2F${groupId}%2F`);
              if (!ok) {
                throw new HttpsError(
                  "invalid-argument",
                  key === "avatarPath"
                    ? "Invalid avatar path."
                    : "Invalid avatar URL.",
                );
              }
            }
            value = s;
          }

          patch[key] = value;
          changedFields.push(key);
        }

        if (canonicalGeo) {
          Object.assign(patch, canonicalGeo);
          for (const k of Object.keys(canonicalGeo)) {
            if (!changedFields.includes(k)) changedFields.push(k);
          }
        }

        patch.updatedAt = admin.firestore.FieldValue.serverTimestamp();
        patch.updatedBy = actorUid;

        tx.set(groupRef, patch, { merge: true });

        return {
          groupId,
          changedFields,
          performedBy: actorUid,
          performedByName: actorName,
        };
      });

      console.log(
        JSON.stringify({
          action: "group_settings_updated",
          groupId,
          performedBy: result.performedBy,
          changedFields: result.changedFields,
          createdAt: new Date().toISOString(),
        }),
      );

      return { success: true, ...result };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("Erro updateGroupSettings:", e);
      throw new HttpsError("internal", "Could not update group.");
    }
  },
);

function mapPlacesError(placeErr) {
  const code = placeErr && placeErr.code;
  if (code === "not-a-city") {
    return new HttpsError("invalid-argument", "Place is not a city.");
  }
  if (code === "country-mismatch") {
    return new HttpsError("invalid-argument", "City/country mismatch.");
  }
  if (code === "invalid-place" || code === "invalid-country") {
    return new HttpsError("invalid-argument", "Invalid placeId.");
  }
  if (code === "places-unavailable") {
    return new HttpsError("failed-precondition", "Places lookup unavailable.");
  }
  return new HttpsError("invalid-argument", "Invalid location.");
}

const GROUP_CREATE_ALLOWED = new Set([
  "name",
  "bio",
  "joinPolicy",
  "isPrivate",
  "scope",
  "city",
  "cityName",
  "cityKey",
  "country",
  "countryCode",
  "stateName",
  "displayLocation",
  "placeId",
  "latitude",
  "longitude",
  "regionKey",
  "regionCenterCity",
  "regionCenterCountryCode",
  "regionCenterLat",
  "regionCenterLng",
  "regionRadiusKm",
  "regionCenterGeohash",
  "requestId",
]);

const GROUP_CREATE_FORBIDDEN = new Set([
  "groupId",
  "ownerId",
  "admins",
  "members",
  "membersCount",
  "unread",
  "inviteCode",
  "createdAt",
  "updatedAt",
  "updatedBy",
  "deleted",
  "deletedAt",
  "deletedBy",
  "isActive",
  "lastMessage",
  "lastMessageAt",
  "lastSenderId",
  "lastMessageBy",
  "avatarUrl",
  "avatarPath",
]);

function generateGroupInviteCode() {
  const chars = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < 6; i++) {
    code += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return code;
}

/**
 * Criação segura de grupo — campos internos só no backend.
 * Convenção: owner também fica em admins (compatível com create_group_page).
 * Cidade/região: placeId → Places Details (server) → coords/geohash/raio.
 */
exports.createGroup = socialOnCall(
  { region: "us-central1", secrets: [GOOGLE_PLACES_API_KEY] },
  async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  const uid = request.auth.uid;
  const dataIn = request.data || {};

  if (!dataIn || typeof dataIn !== "object" || Array.isArray(dataIn)) {
    throw new HttpsError("invalid-argument", "Invalid payload.");
  }

  const keys = Object.keys(dataIn);
  for (const key of keys) {
    if (GROUP_CREATE_FORBIDDEN.has(key)) {
      throw new HttpsError("invalid-argument", `Field not allowed: ${key}`);
    }
    if (!GROUP_CREATE_ALLOWED.has(key)) {
      throw new HttpsError("invalid-argument", `Unknown field: ${key}`);
    }
  }

  const requestId = (dataIn.requestId || "").toString().trim();
  if (!requestId || requestId.length < 8 || requestId.length > 128) {
    throw new HttpsError("invalid-argument", "requestId required.");
  }
  if (!/^[A-Za-z0-9_-]+$/.test(requestId)) {
    throw new HttpsError("invalid-argument", "Invalid requestId.");
  }

  const name = (dataIn.name || "").toString().trim();
  if (!name) {
    throw new HttpsError("invalid-argument", "Name is required.");
  }
  if (name.length < 3) {
    throw new HttpsError("invalid-argument", "Name too short.");
  }
  if (name.length > 80) {
    throw new HttpsError("invalid-argument", "Name too long.");
  }

  const bio = (dataIn.bio || "").toString().trim();
  if (bio.length > 1000) {
    throw new HttpsError("invalid-argument", "Bio too long.");
  }

  const joinPolicy = normalizeJoinPolicyStrict(dataIn.joinPolicy ?? "open");
  if (!joinPolicy) {
    throw new HttpsError("invalid-argument", "Invalid joinPolicy.");
  }
  const isPrivate = joinPolicy !== "open";

  const strField = (key, max) => {
    if (dataIn[key] === undefined || dataIn[key] === null) return "";
    if (typeof dataIn[key] === "number" || typeof dataIn[key] === "boolean") {
      throw new HttpsError("invalid-argument", `Invalid ${key}.`);
    }
    if (typeof dataIn[key] === "object") {
      throw new HttpsError("invalid-argument", `Invalid ${key}.`);
    }
    const s = dataIn[key].toString().trim();
    if (s.length > max) {
      throw new HttpsError("invalid-argument", `${key} too long.`);
    }
    return s;
  };

  const scope = strField("scope", 40) || "city";
  if (!["city", "region", "country"].includes(scope)) {
    throw new HttpsError("invalid-argument", "Invalid location.");
  }

  const countryName = strField("country", 80);
  const countryCode = normalizeIsoCountryCode(strField("countryCode", 3));
  const placeId = strField("placeId", 200);
  const stateName = strField("stateName", 120);
  const displayLocation = strField("displayLocation", 160);

  if (!countryName) {
    throw new HttpsError("invalid-argument", "Invalid location.");
  }
  if (!countryCode) {
    throw new HttpsError("invalid-argument", "Invalid location.");
  }

  // Cliente pode enviar radius/coords, mas não são autoritativos.
  if (
    dataIn.regionRadiusKm !== undefined &&
    dataIn.regionRadiusKm !== null &&
    dataIn.regionRadiusKm !== "" &&
    Number(dataIn.regionRadiusKm) !== REGION_RADIUS_KM
  ) {
    throw new HttpsError("invalid-argument", "Invalid regional radius.");
  }

  const db = admin.firestore();
  let canonicalGeo;
  try {
    if (scope === "country") {
      canonicalGeo = buildCanonicalGeoFields("country", {
        countryCode,
        countryName,
      });
    } else {
      if (!placeId) {
        throw new HttpsError("invalid-argument", "placeId required.");
      }
      const resolved = await resolveTrustedCityPlace({
        placeId,
        expectedCountryCode: countryCode,
        apiKey: GOOGLE_PLACES_API_KEY.value(),
        db,
      });
      canonicalGeo = buildCanonicalGeoFields(scope, {
        place: resolved.place,
        countryName,
        countryCode,
        stateName,
        displayLocation,
      });
      if (clientForgedRegionalGeo(dataIn, canonicalGeo)) {
        throw new HttpsError(
          "invalid-argument",
          "Forged regional coordinates rejected.",
        );
      }
    }
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    throw mapPlacesError(e);
  }

  const payload = {
    name,
    bio,
    joinPolicy,
    isPrivate,
    ...canonicalGeo,
  };

  const userRef = db.collection("users").doc(uid);
  const requestRef = db
    .collection("groupCreationRequests")
    .doc(`${uid}_${requestId}`);

  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError("failed-precondition", "User profile not found.");
  }
  const userData = userSnap.data() || {};
  if (userData.isBanned === true) {
    throw new HttpsError("permission-denied", "Account is banned.");
  }
  if (isAccountDisabledData(userData)) {
    throw new HttpsError("permission-denied", "Account is disabled.");
  }

  // Free/Premium: join internacional continua validado nos fluxos de join.
  assertCanAccessInternationalGroup(
    { countryCode: payload.countryCode, isPremiumGroup: false },
    userData,
  );

  const performedByName = (userData.name || "").toString().trim() || "User";

  const existingReq = await requestRef.get();
  if (existingReq.exists) {
    const prev = existingReq.data() || {};
    return {
      success: true,
      groupId: prev.groupId,
      inviteCode: prev.inviteCode,
      created: false,
    };
  }

  const maxAttempts = 8;
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const inviteCode = generateGroupInviteCode();
    const groupRef = db.collection("groups").doc();
    const groupId = groupRef.id;
    const codeRef = db.collection("groupInviteCodes").doc(inviteCode);

    try {
      const result = await db.runTransaction(async (tx) => {
        const reqSnap = await tx.get(requestRef);
        if (reqSnap.exists) {
          const prev = reqSnap.data() || {};
          return {
            groupId: prev.groupId,
            inviteCode: prev.inviteCode,
            created: false,
          };
        }

        const codeSnap = await tx.get(codeRef);
        if (codeSnap.exists) {
          throw new HttpsError("aborted", "Invite code collision.");
        }

        const now = admin.firestore.FieldValue.serverTimestamp();
        tx.set(groupRef, {
          name: payload.name,
          bio: payload.bio,
          country: payload.country,
          countryCode: payload.countryCode,
          city: payload.city,
          cityName: payload.cityName,
          cityKey: payload.cityKey,
          stateName: payload.stateName,
          displayLocation: payload.displayLocation,
          placeId: payload.placeId,
          latitude: payload.latitude,
          longitude: payload.longitude,
          scope: payload.scope,
          regionKey: payload.regionKey,
          regionCenterCity: payload.regionCenterCity,
          regionCenterCountryCode: payload.regionCenterCountryCode,
          regionCenterLat: payload.regionCenterLat,
          regionCenterLng: payload.regionCenterLng,
          regionRadiusKm: payload.regionRadiusKm,
          regionCenterGeohash: payload.regionCenterGeohash,
          avatarUrl: "",
          avatarPath: "",
          ownerId: uid,
          admins: [uid],
          members: [uid],
          membersCount: 1,
          inviteCode,
          isPrivate: payload.isPrivate,
          joinPolicy: payload.joinPolicy,
          isPremiumGroup: false,
          deleted: false,
          isActive: true,
          unread: { [uid]: 0 },
          lastMessage: "",
          lastSenderId: "",
          lastMessageAt: null,
          createdAt: now,
          updatedAt: now,
          updatedBy: uid,
        });

        tx.set(groupRef.collection("reads").doc(uid), {
          lastReadAt: now,
        });

        tx.set(requestRef, {
          groupId,
          inviteCode,
          createdBy: uid,
          createdAt: now,
        });

        tx.set(codeRef, {
          groupId,
          createdBy: uid,
          createdAt: now,
        });

        return { groupId, inviteCode, created: true };
      });

      if (result.created) {
        console.log(
          JSON.stringify({
            action: "group_created",
            groupId: result.groupId,
            performedBy: uid,
            performedByName,
            scope: payload.scope,
            createdAt: new Date().toISOString(),
          }),
        );
      }

      return { success: true, ...result };
    } catch (e) {
      if (e instanceof HttpsError && e.code === "aborted") {
        continue;
      }
      if (e instanceof HttpsError) throw e;
      console.error("Erro createGroup:", e);
      throw new HttpsError("internal", "Could not create group.");
    }
  }

  throw new HttpsError("internal", "Could not allocate invite code.");
},
);

function isAccountDisabledData(userData) {
  if (!userData) return false;
  if (
    Object.prototype.hasOwnProperty.call(userData, "isActive") &&
    userData.isActive === false
  ) {
    return true;
  }
  return (
    userData.isDisabled === true ||
    userData.disabled === true ||
    userData.deactivated === true
  );
}

async function notifyJoinRequestDecision({
  requestUid,
  groupId,
  groupName,
  approved,
}) {
  try {
    const tokens = await collectTokensForUid(requestUid, "group");
    if (!tokens.length) return;

    const name = (groupName || "group").toString().trim() || "group";
    const title = approved
      ? "Sua solicitação foi aprovada."
      : "Solicitação não aprovada";
    const body = approved
      ? `Agora você pode participar de ${name}.`
      : "Sua solicitação para entrar no grupo não foi aprovada.";

    await sendPush({
      tokens,
      title,
      body,
      data: {
        type: approved ? "group_join_approved" : "group_join_rejected",
        groupId: String(groupId || ""),
        requestUid: String(requestUid || ""),
      },
    });
  } catch (e) {
    console.error("Erro push join decision:", e);
  }
}

/**
 * Aprovar pedido de entrada (approval) — Admin SDK.
 */
exports.approveGroupJoinRequest = socialOnCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const actorUid = request.auth.uid;
    const groupId = (request.data?.groupId || "").toString().trim();
    const requestUid = (request.data?.requestUid || "").toString().trim();

    if (!groupId || !requestUid) {
      throw new HttpsError(
        "invalid-argument",
        "groupId and requestUid required.",
      );
    }
    if (actorUid === requestUid) {
      throw new HttpsError(
        "permission-denied",
        "Cannot approve your own request.",
      );
    }

    const db = admin.firestore();
    const groupRef = db.collection("groups").doc(groupId);
    const pendingRef = groupRef.collection("pendingRequests").doc(requestUid);
    const banRef = groupRef.collection("bannedUsers").doc(requestUid);
    const actorRef = db.collection("users").doc(actorUid);
    const targetRef = db.collection("users").doc(requestUid);

    try {
      const result = await db.runTransaction(async (tx) => {
        const groupSnap = await tx.get(groupRef);
        const pendingSnap = await tx.get(pendingRef);
        const banSnap = await tx.get(banRef);
        const actorSnap = await tx.get(actorRef);
        const targetSnap = await tx.get(targetRef);

        if (!groupSnap.exists) {
          throw new HttpsError("not-found", "Group not found.");
        }

        const data = groupSnap.data() || {};
        if (data.deleted === true) {
          throw new HttpsError("failed-precondition", "Group unavailable.");
        }

        if (!isGroupOwnerOrAdminData(data, actorUid)) {
          throw new HttpsError("permission-denied", "Not allowed.");
        }

        if (!actorSnap.exists || actorSnap.data()?.isBanned === true) {
          throw new HttpsError("permission-denied", "Not allowed.");
        }
        if (isAccountDisabledData(actorSnap.data() || {})) {
          throw new HttpsError("permission-denied", "Not allowed.");
        }

        const policy = normalizeJoinPolicyStrict(data.joinPolicy);
        if (policy !== "approval") {
          throw new HttpsError(
            "failed-precondition",
            "Group does not accept join requests.",
          );
        }

        if (!pendingSnap.exists) {
          throw new HttpsError("not-found", "Join request not found.");
        }

        const pending = pendingSnap.data() || {};
        const pendingUid = (pending.uid || requestUid).toString().trim();
        if (pendingUid && pendingUid !== requestUid) {
          throw new HttpsError("failed-precondition", "Request mismatch.");
        }

        const status = (pending.status || "").toString().trim();
        const members = asUidList(data.members);
        const alreadyMember = members.includes(requestUid);
        const actorName =
          (actorSnap.data()?.name || "").toString().trim() || "Admin";
        const groupName = (data.name || "").toString().trim() || "Grupo";

        if (status === "approved") {
          return {
            groupId,
            requestUid,
            approved: true,
            alreadyMember,
            newlyApproved: false,
            groupName,
          };
        }

        if (status !== "pending") {
          throw new HttpsError(
            "failed-precondition",
            "Request is not pending.",
          );
        }

        if (!targetSnap.exists) {
          throw new HttpsError(
            "failed-precondition",
            "Requester profile missing.",
          );
        }
        const targetData = targetSnap.data() || {};
        if (targetData.isBanned === true || isAccountDisabledData(targetData)) {
          throw new HttpsError("failed-precondition", "Requester cannot join.");
        }

        if (banSnap.exists && banSnap.data()?.isActive === true) {
          throw new HttpsError(
            "failed-precondition",
            "Requester is banned from this group.",
          );
        }

        assertCanAccessInternationalGroup(data, targetSnap.data() || {});

        let newlyAdded = false;
        if (!alreadyMember) {
          members.push(requestUid);
          newlyAdded = true;
        }

        const patch = {
          members,
          membersCount: members.length,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        if (newlyAdded || !alreadyMember) {
          patch[`unread.${requestUid}`] = 0;
        } else if (alreadyMember) {
          // Garante unread inicial se ausente sem alterar outros.
          const unread = data.unread || {};
          if (unread[requestUid] === undefined) {
            patch[`unread.${requestUid}`] = 0;
          }
        }

        tx.set(groupRef, patch, { merge: true });

        tx.set(
          pendingRef,
          {
            status: "approved",
            approvedAt: admin.firestore.FieldValue.serverTimestamp(),
            approvedBy: actorUid,
            approvedByName: actorName,
          },
          { merge: true },
        );

        return {
          groupId,
          requestUid,
          approved: true,
          alreadyMember: alreadyMember && !newlyAdded,
          newlyApproved: true,
          groupName,
        };
      });

      if (result.newlyApproved) {
        console.log(
          JSON.stringify({
            action: "group_join_request_approved",
            groupId,
            targetUid: requestUid,
            performedBy: actorUid,
            createdAt: new Date().toISOString(),
          }),
        );
        await notifyJoinRequestDecision({
          requestUid,
          groupId,
          groupName: result.groupName,
          approved: true,
        });
      }

      return {
        success: true,
        groupId: result.groupId,
        requestUid: result.requestUid,
        approved: result.approved,
        alreadyMember: result.alreadyMember,
      };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("Erro approveGroupJoinRequest:", e);
      throw new HttpsError("internal", "Could not approve request.");
    }
  },
);

/**
 * Rejeitar pedido de entrada — Admin SDK. Não altera members.
 */
exports.rejectGroupJoinRequest = socialOnCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const actorUid = request.auth.uid;
    const groupId = (request.data?.groupId || "").toString().trim();
    const requestUid = (request.data?.requestUid || "").toString().trim();
    let reason = (request.data?.reason || "").toString().trim();
    if (reason.length > 300) {
      throw new HttpsError("invalid-argument", "Reason too long.");
    }

    if (!groupId || !requestUid) {
      throw new HttpsError(
        "invalid-argument",
        "groupId and requestUid required.",
      );
    }
    if (actorUid === requestUid) {
      throw new HttpsError(
        "permission-denied",
        "Cannot reject your own request.",
      );
    }

    const db = admin.firestore();
    const groupRef = db.collection("groups").doc(groupId);
    const pendingRef = groupRef.collection("pendingRequests").doc(requestUid);
    const actorRef = db.collection("users").doc(actorUid);

    try {
      const result = await db.runTransaction(async (tx) => {
        const groupSnap = await tx.get(groupRef);
        const pendingSnap = await tx.get(pendingRef);
        const actorSnap = await tx.get(actorRef);

        if (!groupSnap.exists) {
          throw new HttpsError("not-found", "Group not found.");
        }

        const data = groupSnap.data() || {};
        if (data.deleted === true) {
          throw new HttpsError("failed-precondition", "Group unavailable.");
        }

        if (!isGroupOwnerOrAdminData(data, actorUid)) {
          throw new HttpsError("permission-denied", "Not allowed.");
        }

        if (!actorSnap.exists || actorSnap.data()?.isBanned === true) {
          throw new HttpsError("permission-denied", "Not allowed.");
        }
        if (isAccountDisabledData(actorSnap.data() || {})) {
          throw new HttpsError("permission-denied", "Not allowed.");
        }

        if (!pendingSnap.exists) {
          throw new HttpsError("not-found", "Join request not found.");
        }

        const pending = pendingSnap.data() || {};
        const pendingUid = (pending.uid || requestUid).toString().trim();
        if (pendingUid && pendingUid !== requestUid) {
          throw new HttpsError("failed-precondition", "Request mismatch.");
        }

        const status = (pending.status || "").toString().trim();
        const actorName =
          (actorSnap.data()?.name || "").toString().trim() || "Admin";
        const groupName = (data.name || "").toString().trim() || "Grupo";

        if (status === "rejected") {
          return {
            groupId,
            requestUid,
            rejected: true,
            alreadyRejected: true,
            newlyRejected: false,
            groupName,
          };
        }

        if (status === "approved") {
          throw new HttpsError(
            "failed-precondition",
            "Request is not pending.",
          );
        }

        if (status !== "pending") {
          throw new HttpsError(
            "failed-precondition",
            "Request is not pending.",
          );
        }

        const patch = {
          status: "rejected",
          rejectedAt: admin.firestore.FieldValue.serverTimestamp(),
          rejectedBy: actorUid,
          rejectedByName: actorName,
        };
        if (reason) {
          patch.rejectionReason = reason;
        }

        tx.set(pendingRef, patch, { merge: true });

        return {
          groupId,
          requestUid,
          rejected: true,
          alreadyRejected: false,
          newlyRejected: true,
          groupName,
          reason,
        };
      });

      if (result.newlyRejected) {
        console.log(
          JSON.stringify({
            action: "group_join_request_rejected",
            groupId,
            targetUid: requestUid,
            performedBy: actorUid,
            reason: result.reason || "",
            createdAt: new Date().toISOString(),
          }),
        );
        await notifyJoinRequestDecision({
          requestUid,
          groupId,
          groupName: result.groupName,
          approved: false,
        });
      }

      return {
        success: true,
        groupId: result.groupId,
        requestUid: result.requestUid,
        rejected: result.rejected,
        alreadyRejected: result.alreadyRejected,
      };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("Erro rejectGroupJoinRequest:", e);
      throw new HttpsError("internal", "Could not reject request.");
    }
  },
);

/**
 * Zera unread do próprio usuário e atualiza reads/{uid}.
 */
exports.markGroupAsRead = socialOnCall({ region: "us-central1" }, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  const uid = request.auth.uid;
  const groupId = (request.data?.groupId || "").toString().trim();
  if (!groupId) {
    throw new HttpsError("invalid-argument", "groupId required.");
  }

  const db = admin.firestore();
  const groupRef = db.collection("groups").doc(groupId);
  const readRef = groupRef.collection("reads").doc(uid);
  const banRef = groupRef.collection("bannedUsers").doc(uid);

  try {
    await db.runTransaction(async (tx) => {
      const groupSnap = await tx.get(groupRef);
      const banSnap = await tx.get(banRef);

      if (!groupSnap.exists) {
        throw new HttpsError("not-found", "Group not found.");
      }

      const data = groupSnap.data() || {};
      if (data.deleted === true) {
        throw new HttpsError("failed-precondition", "Group unavailable.");
      }

      if (banSnap.exists && banSnap.data()?.isActive === true) {
        throw new HttpsError("permission-denied", "Banned from group.");
      }

      const members = asUidList(data.members);
      const isOwner = (data.ownerId || "").toString().trim() === uid;
      const isAdmin = isGroupOwnerOrAdminData(data, uid);
      if (!members.includes(uid) && !isOwner && !isAdmin) {
        throw new HttpsError("permission-denied", "Not a group member.");
      }

      tx.set(
        groupRef,
        {
          [`unread.${uid}`]: 0,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      tx.set(
        readRef,
        {
          uid,
          lastReadAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    });

    return { success: true, groupId };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("Erro markGroupAsRead:", e);
    throw new HttpsError("internal", "Could not mark group as read.");
  }
});

function asAttendeeUidList(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  const seen = new Set();
  for (const item of raw) {
    const uid = (item || "").toString().trim();
    if (!uid || seen.has(uid)) continue;
    seen.add(uid);
    out.push(uid);
  }
  return out;
}

function eventAcceptsJoin(data) {
  if (!data) return false;
  if (data.deleted === true) return false;
  if (data.isActive !== true) return false;
  const status = (data.status || "").toString().trim().toLowerCase();
  if (status !== "approved") return false;
  if (status === "cancelled" || status === "pending" || status === "rejected") {
    return false;
  }
  return true;
}

function eventStartAtHasPassed(data) {
  const startAt = data?.startAt;
  if (!startAt) return false;
  let ms = null;
  if (typeof startAt.toMillis === "function") {
    ms = startAt.toMillis();
  } else if (typeof startAt._seconds === "number") {
    ms = startAt._seconds * 1000;
  } else if (typeof startAt.seconds === "number") {
    ms = startAt.seconds * 1000;
  }
  if (ms == null || Number.isNaN(ms)) return false;
  return ms < Date.now();
}

/**
 * Participar de evento — Admin SDK (contadores consistentes).
 */
exports.joinEvent = socialOnCall({ region: "us-central1" }, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  const uid = request.auth.uid;
  const eventId = (request.data?.eventId || "").toString().trim();
  if (!eventId) {
    throw new HttpsError("invalid-argument", "eventId required.");
  }

  const db = admin.firestore();
  const eventRef = db.collection("events").doc(eventId);
  const attendeeRef = eventRef.collection("attendees").doc(uid);
  const userRef = db.collection("users").doc(uid);
  const publicRef = db.collection("publicUsers").doc(uid);

  try {
    const result = await db.runTransaction(async (tx) => {
      const eventSnap = await tx.get(eventRef);
      const attendeeSnap = await tx.get(attendeeRef);
      const userSnap = await tx.get(userRef);
      const publicSnap = await tx.get(publicRef);

      if (!eventSnap.exists) {
        throw new HttpsError("not-found", "Event not found.");
      }

      const data = eventSnap.data() || {};
      if (!eventAcceptsJoin(data)) {
        throw new HttpsError(
          "failed-precondition",
          "Event is not available for joining.",
        );
      }

      if (eventStartAtHasPassed(data)) {
        throw new HttpsError(
          "failed-precondition",
          "Event no longer accepts attendees.",
        );
      }

      if (!userSnap.exists && !publicSnap.exists) {
        throw new HttpsError("failed-precondition", "User profile not found.");
      }

      const userData = userSnap.exists
        ? userSnap.data() || {}
        : publicSnap.data() || {};
      if (userData.isBanned === true || isAccountDisabledData(userData)) {
        throw new HttpsError("permission-denied", "Account is banned.");
      }

      let uids = asAttendeeUidList(data.attendeesUids);
      const alreadyJoined = attendeeSnap.exists || uids.includes(uid);

      if (alreadyJoined) {
        if (!uids.includes(uid)) {
          uids.push(uid);
        }
        const count = Math.max(uids.length, 0);
        // Garante documento do attendee se só existir no array.
        if (!attendeeSnap.exists) {
          const name = (userData.name || "").toString().trim() || "User";
          const photoUrl = (
            userData.photoUrl ||
            userData.profilePhotoUrl ||
            userData.avatarUrl ||
            ""
          ).toString();
          tx.set(attendeeRef, {
            uid,
            name,
            photoUrl,
            joinedAt: admin.firestore.FieldValue.serverTimestamp(),
          });
        }
        if ((data.attendeesCount || 0) !== count || !uids.includes(uid)) {
          tx.set(
            eventRef,
            {
              attendeesUids: uids,
              attendeesCount: count,
              participantsCount: count,
            },
            { merge: true },
          );
        }
        return {
          eventId,
          joined: true,
          alreadyJoined: true,
          attendeesCount: count,
        };
      }

      const name = (userData.name || "").toString().trim() || "User";
      const photoUrl = (
        userData.photoUrl ||
        userData.profilePhotoUrl ||
        userData.avatarUrl ||
        ""
      ).toString();

      uids.push(uid);
      const count = uids.length;

      tx.set(attendeeRef, {
        uid,
        name,
        photoUrl,
        joinedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      tx.set(
        eventRef,
        {
          attendeesUids: uids,
          attendeesCount: count,
          participantsCount: count,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      return {
        eventId,
        joined: true,
        alreadyJoined: false,
        attendeesCount: count,
        performedByName: name,
      };
    });

    if (!result.alreadyJoined) {
      console.log(
        JSON.stringify({
          action: "event_joined",
          eventId,
          performedBy: uid,
          performedByName: result.performedByName || "",
          createdAt: new Date().toISOString(),
        }),
      );
    }

    return {
      success: true,
      eventId: result.eventId,
      joined: result.joined,
      alreadyJoined: result.alreadyJoined,
      attendeesCount: result.attendeesCount,
    };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("Erro joinEvent:", e);
    throw new HttpsError("internal", "Could not join event.");
  }
});

/**
 * Sair de evento — Admin SDK.
 */
exports.leaveEvent = socialOnCall({ region: "us-central1" }, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  const uid = request.auth.uid;
  const eventId = (request.data?.eventId || "").toString().trim();
  if (!eventId) {
    throw new HttpsError("invalid-argument", "eventId required.");
  }

  const db = admin.firestore();
  const eventRef = db.collection("events").doc(eventId);
  const attendeeRef = eventRef.collection("attendees").doc(uid);
  const userRef = db.collection("users").doc(uid);

  try {
    const result = await db.runTransaction(async (tx) => {
      const eventSnap = await tx.get(eventRef);
      const attendeeSnap = await tx.get(attendeeRef);
      const userSnap = await tx.get(userRef);

      if (!eventSnap.exists) {
        throw new HttpsError("not-found", "Event not found.");
      }

      const data = eventSnap.data() || {};
      let uids = asAttendeeUidList(data.attendeesUids);
      const wasJoined = attendeeSnap.exists || uids.includes(uid);

      if (!wasJoined) {
        const count = Math.max(
          typeof data.attendeesCount === "number"
            ? data.attendeesCount
            : uids.length,
          0,
        );
        return {
          eventId,
          left: true,
          wasNotJoined: true,
          attendeesCount: count,
        };
      }

      uids = uids.filter((id) => id !== uid);
      const count = Math.max(uids.length, 0);

      if (attendeeSnap.exists) {
        tx.delete(attendeeRef);
      }

      tx.set(
        eventRef,
        {
          attendeesUids: uids,
          attendeesCount: count,
          participantsCount: count,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );

      const actorName =
        (userSnap.exists && (userSnap.data()?.name || "").toString().trim()) ||
        "User";

      return {
        eventId,
        left: true,
        wasNotJoined: false,
        attendeesCount: count,
        performedByName: actorName,
      };
    });

    if (!result.wasNotJoined) {
      console.log(
        JSON.stringify({
          action: "event_left",
          eventId,
          performedBy: uid,
          performedByName: result.performedByName || "",
          createdAt: new Date().toISOString(),
        }),
      );
    }

    return {
      success: true,
      eventId: result.eventId,
      left: result.left,
      wasNotJoined: result.wasNotJoined,
      attendeesCount: result.attendeesCount,
    };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("Erro leaveEvent:", e);
    throw new HttpsError("internal", "Could not leave event.");
  }
});

const EVENT_COMMENT_MAX_LEN = eventInteractions.EVENT_COMMENT_MAX_LEN;
const EVENT_COMMENT_REPLY_PREVIEW_LEN =
  eventInteractions.EVENT_COMMENT_REPLY_PREVIEW_LEN;

function eventOrganizerUid(data) {
  return eventInteractions.eventOrganizerUid(data);
}

function eventAllowsComments(data) {
  return eventInteractions.eventAllowsComments(data);
}

function eventAllowsLikes(data) {
  return eventInteractions.eventAllowsLikes(data);
}

function resolveUserProfileNamePhoto(userData) {
  const name = (userData?.name || "").toString().trim() || "User";
  const photoUrl = (
    userData?.photoUrl ||
    userData?.profilePhotoUrl ||
    userData?.avatarUrl ||
    ""
  ).toString();
  return { name, photoUrl };
}

function resolveRootCommentId(parent) {
  return eventInteractions.resolveRootCommentId(parent);
}

/**
 * Criar comentário/resposta em evento.
 */
exports.createEventComment = socialOnCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const uid = request.auth.uid;
    const dataIn = request.data || {};
    // Ignora uid/name/likesCount/autor enviados pelo cliente.
    const eventId = (dataIn.eventId || "").toString().trim();
    if (!eventInteractions.isValidEventId(eventId)) {
      throw new HttpsError("invalid-argument", "eventId required.");
    }

    const sanitized = eventInteractions.sanitizeCommentText(dataIn.text);
    if (sanitized.error === "invalid") {
      throw new HttpsError("invalid-argument", "Invalid text.");
    }
    if (sanitized.error === "empty") {
      throw new HttpsError("invalid-argument", "Comment is empty.");
    }
    if (sanitized.error === "too_long") {
      throw new HttpsError("invalid-argument", "Comment is too long.");
    }
    const text = sanitized.text;

    let replyToCommentId = "";
    if (
      dataIn.replyToCommentId !== undefined &&
      dataIn.replyToCommentId !== null &&
      dataIn.replyToCommentId !== ""
    ) {
      if (typeof dataIn.replyToCommentId !== "string") {
        throw new HttpsError("invalid-argument", "Invalid replyToCommentId.");
      }
      replyToCommentId = dataIn.replyToCommentId.trim();
      if (
        replyToCommentId &&
        !eventInteractions.isValidClientId(replyToCommentId)
      ) {
        throw new HttpsError("invalid-argument", "Invalid replyToCommentId.");
      }
    }

    const requestId = (dataIn.requestId || "").toString().trim();
    if (!eventInteractions.isValidClientId(requestId)) {
      throw new HttpsError("invalid-argument", "requestId required.");
    }

    let clientCommentId = "";
    if (
      dataIn.commentId !== undefined &&
      dataIn.commentId !== null &&
      dataIn.commentId !== ""
    ) {
      if (typeof dataIn.commentId !== "string") {
        throw new HttpsError("invalid-argument", "Invalid commentId.");
      }
      clientCommentId = dataIn.commentId.trim();
      if (!eventInteractions.isValidClientId(clientCommentId)) {
        throw new HttpsError("invalid-argument", "Invalid commentId.");
      }
    }

    let clientCreatedAtMs = null;
    if (
      dataIn.clientCreatedAtMs !== undefined &&
      dataIn.clientCreatedAtMs !== null &&
      dataIn.clientCreatedAtMs !== ""
    ) {
      const n = Number(dataIn.clientCreatedAtMs);
      if (!Number.isFinite(n) || n <= 0) {
        throw new HttpsError("invalid-argument", "Invalid clientCreatedAtMs.");
      }
      clientCreatedAtMs = Math.floor(n);
    }

    const db = admin.firestore();
    const eventRef = db.collection("events").doc(eventId);
    const commentsRef = eventRef.collection("comments");
    const requestRef = db
      .collection("eventCommentRequests")
      .doc(`${uid}_${requestId}`);
    const userRef = db.collection("users").doc(uid);
    const publicRef = db.collection("publicUsers").doc(uid);

    try {
      const result = await db.runTransaction(async (tx) => {
        const requestSnap = await tx.get(requestRef);
        if (requestSnap.exists) {
          const prev = requestSnap.data() || {};
          return {
            eventId,
            commentId: (prev.commentId || "").toString(),
            created: false,
            alreadyCreated: true,
            isReply: !!prev.isReply,
            replyToUid: (prev.replyToUid || "").toString(),
            organizerUid: (prev.organizerUid || "").toString(),
            performedByName: (prev.performedByName || "").toString(),
          };
        }

        const eventSnap = await tx.get(eventRef);
        const userSnap = await tx.get(userRef);
        const publicSnap = await tx.get(publicRef);

        let parentSnap = null;
        if (replyToCommentId) {
          parentSnap = await tx.get(commentsRef.doc(replyToCommentId));
        }

        let existingCommentSnap = null;
        if (clientCommentId) {
          existingCommentSnap = await tx.get(commentsRef.doc(clientCommentId));
        }

        if (!eventSnap.exists) {
          throw new HttpsError("not-found", "Event not found.");
        }
        const eventData = eventSnap.data() || {};
        if (!eventAllowsComments(eventData)) {
          const status = (eventData.status || "").toString().toLowerCase();
          if (status === "cancelled" || status === "canceled") {
            throw new HttpsError(
              "failed-precondition",
              "Event is cancelled.",
            );
          }
          throw new HttpsError(
            "failed-precondition",
            "Event is not available for comments.",
          );
        }

        if (!userSnap.exists && !publicSnap.exists) {
          throw new HttpsError(
            "failed-precondition",
            "User profile not found.",
          );
        }
        const userData = userSnap.exists
          ? userSnap.data() || {}
          : publicSnap.data() || {};
        if (userData.isBanned === true || isAccountDisabledData(userData)) {
          throw new HttpsError("permission-denied", "Account is banned.");
        }

        let replyToName = null;
        let replyToText = null;
        let replyToUid = null;
        let rootCommentId = null;
        let visualReplyToCommentId = replyToCommentId || null;

        if (replyToCommentId) {
          if (!parentSnap || !parentSnap.exists) {
            throw new HttpsError("not-found", "Parent comment not found.");
          }
          const parent = parentSnap.data() || {};
          const meta = eventInteractions.buildReplyMetaFromParent({
            replyToCommentId,
            parent,
          });
          if (meta.error === "parent_deleted") {
            throw new HttpsError(
              "failed-precondition",
              "Parent comment is deleted.",
            );
          }
          if (meta.error) {
            throw new HttpsError("not-found", "Parent comment not found.");
          }
          replyToUid = meta.replyToUid;
          replyToName = meta.replyToName;
          replyToText = meta.replyToText;
          rootCommentId = meta.rootCommentId;
          visualReplyToCommentId = meta.replyToCommentId;
        }

        if (existingCommentSnap && existingCommentSnap.exists) {
          const existing = existingCommentSnap.data() || {};
          if ((existing.uid || "").toString() !== uid) {
            throw new HttpsError(
              "already-exists",
              "Comment id already exists.",
            );
          }
          tx.set(requestRef, {
            uid,
            eventId,
            commentId: clientCommentId,
            requestId,
            isReply: !!replyToCommentId,
            replyToUid: replyToUid || "",
            organizerUid: eventOrganizerUid(eventData),
            performedByName: (existing.name || "").toString(),
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          return {
            eventId,
            commentId: clientCommentId,
            created: false,
            alreadyCreated: true,
            isReply: !!replyToCommentId,
            replyToUid: replyToUid || "",
            organizerUid: eventOrganizerUid(eventData),
            performedByName: (existing.name || "").toString(),
          };
        }

        const { name, photoUrl } = resolveUserProfileNamePhoto(userData);
        const organizerUid = eventOrganizerUid(eventData);
        const isOrganizer = organizerUid === uid;

        const commentRef = clientCommentId
          ? commentsRef.doc(clientCommentId)
          : commentsRef.doc();
        const payload = {
          uid,
          name,
          photoUrl,
          text,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          clientCreatedAt: clientCreatedAtMs
            ? admin.firestore.Timestamp.fromMillis(clientCreatedAtMs)
            : null,
          likesCount: 0,
          likedBy: [],
          isDeleted: false,
          readByOrganizer: isOrganizer,
          replyToCommentId: visualReplyToCommentId,
          replyToUid: replyToUid,
          replyToName: replyToName,
          replyToText: replyToText,
          rootCommentId: rootCommentId,
        };

        tx.set(commentRef, payload);
        tx.set(requestRef, {
          uid,
          eventId,
          commentId: commentRef.id,
          requestId,
          isReply: !!replyToCommentId,
          replyToUid: replyToUid || "",
          organizerUid,
          performedByName: name,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        return {
          eventId,
          commentId: commentRef.id,
          created: true,
          alreadyCreated: false,
          isReply: !!replyToCommentId,
          replyToUid: replyToUid || "",
          organizerUid,
          performedByName: name,
          textPreview:
            text.length > 120 ? `${text.slice(0, 117)}...` : text,
        };
      });

      if (result.created) {
        console.log(
          JSON.stringify({
            action: result.isReply
              ? "event_comment_replied"
              : "event_comment_created",
            eventId,
            commentId: result.commentId,
            performedBy: uid,
            createdAt: new Date().toISOString(),
          }),
        );

        if (
          eventInteractions.shouldSendCommentPush({
            created: result.created,
            alreadyCreated: result.alreadyCreated,
          })
        ) {
          try {
            const notifyUids = eventInteractions.resolveCommentPushTargets({
              actorUid: uid,
              isReply: result.isReply,
              replyToUid: result.replyToUid,
              organizerUid: result.organizerUid,
            });
            if (notifyUids.length > 0) {
              const type = result.isReply ? "event_reply" : "event_comment";
              const title = result.isReply
                ? "Nova resposta"
                : "Novo comentário no evento";
              const body = result.textPreview
                ? `Novo comentário: ${result.textPreview}`
                : "Novo comentário no evento";
              await sendPushToUids({
                uids: notifyUids,
                title,
                body,
                data: {
                  type,
                  eventId,
                  commentId: result.commentId || "",
                },
                prefKey: "event",
              });
            }
          } catch (pushErr) {
            console.error("createEventComment push error:", pushErr);
          }
        }
      }

      return {
        success: true,
        eventId: result.eventId,
        commentId: result.commentId,
        created: result.created,
        alreadyCreated: result.alreadyCreated,
      };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("Erro createEventComment:", e);
      throw new HttpsError("internal", "Could not create comment.");
    }
  },
);

/**
 * Curtir/descurtir evento (set semântico / idempotente).
 * Contrato: { eventId, desiredLiked: boolean }
 * requestId opcional só para log/diagnóstico — NÃO persiste coleção.
 * Nome legado toggleEventLike — age como setEventLike.
 * Sem push. Cliente não define uid nem likesCount.
 *
 * Custo: lê event + likes/{uid} (+ user); writes só se estado mudar
 * (no máx. 1 like doc + 1 likesCount). No-op = 0 writes.
 */

/**
 * Exportação de dados pessoais de participantes/curtidas/compartilhamentos.
 * Sempre negada — minimização de dados (compatível com objetivos da LGPD).
 * Deploy necessário para vigorar no backend remoto.
 */
exports.exportEventParticipants = socialOnCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }
    throw new HttpsError(
      "permission-denied",
      "Personal data export for event participants, likers, or sharers is not allowed.",
    );
  },
);

exports.toggleEventLike = socialOnCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const uid = request.auth.uid;
    const dataIn = request.data || {};
    // Ignora qualquer uid/likesCount enviado pelo cliente.
    const eventId = (dataIn.eventId || "").toString().trim();
    if (!eventInteractions.isValidEventId(eventId)) {
      throw new HttpsError("invalid-argument", "eventId required.");
    }

    const parsed = eventInteractions.parseDesiredLiked(dataIn.desiredLiked);
    if (parsed.error === "missing") {
      throw new HttpsError("invalid-argument", "desiredLiked required.");
    }
    if (parsed.error === "invalid_type") {
      throw new HttpsError("invalid-argument", "desiredLiked must be boolean.");
    }
    const desiredLiked = parsed.desiredLiked;

    // Opcional: diagnóstico apenas (nunca gravado).
    const requestIdDiag = (dataIn.requestId || "").toString().trim();

    const db = admin.firestore();
    const eventRef = db.collection("events").doc(eventId);
    const likeRef = eventRef.collection("likes").doc(uid);
    const userRef = db.collection("users").doc(uid);

    try {
      const result = await db.runTransaction(async (tx) => {
        const eventSnap = await tx.get(eventRef);
        const likeSnap = await tx.get(likeRef);
        const userSnap = await tx.get(userRef);

        if (!eventSnap.exists) {
          throw new HttpsError("not-found", "Event not found.");
        }
        const eventData = eventSnap.data() || {};
        if (!eventAllowsLikes(eventData)) {
          const status = (eventData.status || "").toString().toLowerCase();
          if (status === "cancelled" || status === "canceled") {
            throw new HttpsError(
              "failed-precondition",
              "Event is cancelled.",
            );
          }
          throw new HttpsError(
            "failed-precondition",
            "Event is not available.",
          );
        }

        if (!userSnap.exists) {
          throw new HttpsError(
            "failed-precondition",
            "User profile not found.",
          );
        }
        const userData = userSnap.data() || {};
        if (userData.isBanned === true || isAccountDisabledData(userData)) {
          throw new HttpsError("permission-denied", "Account is banned.");
        }

        const currentlyLiked = likeSnap.exists;
        const currentCount = eventInteractions.normalizeLikesCount(
          eventData.likesCount,
        );
        const next = eventInteractions.applyDesiredLike({
          currentCount,
          currentlyLiked,
          desiredLiked,
        });

        if (next.changed) {
          if (desiredLiked) {
            tx.set(likeRef, {
              uid,
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
            });
          } else {
            tx.delete(likeRef);
          }
          // Somente likesCount — sem updatedAt/status.
          tx.set(eventRef, { likesCount: next.likesCount }, { merge: true });
        }

        return {
          eventId,
          liked: next.liked,
          likesCount: next.likesCount,
          changed: next.changed,
        };
      });

      console.log(
        JSON.stringify({
          action: result.liked ? "event_liked" : "event_unliked",
          eventId,
          likesCount: result.likesCount,
          changed: result.changed === true,
          ...(requestIdDiag ? { requestId: requestIdDiag } : {}),
          createdAt: new Date().toISOString(),
        }),
      );

      return { success: true, ...result };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("Erro toggleEventLike:", e);
      throw new HttpsError("internal", "Could not toggle event like.");
    }
  },
);

/**
 * Curtir/descurtir comentário de evento.
 */
exports.toggleEventCommentLike = socialOnCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const uid = request.auth.uid;
    const eventId = (request.data?.eventId || "").toString().trim();
    const commentId = (request.data?.commentId || "").toString().trim();
    if (!eventId || !commentId) {
      throw new HttpsError(
        "invalid-argument",
        "eventId and commentId required.",
      );
    }

    const db = admin.firestore();
    const eventRef = db.collection("events").doc(eventId);
    const commentRef = eventRef.collection("comments").doc(commentId);
    const userRef = db.collection("users").doc(uid);

    try {
      const result = await db.runTransaction(async (tx) => {
        const eventSnap = await tx.get(eventRef);
        const commentSnap = await tx.get(commentRef);
        const userSnap = await tx.get(userRef);

        if (!eventSnap.exists) {
          throw new HttpsError("not-found", "Event not found.");
        }
        if (!commentSnap.exists) {
          throw new HttpsError("not-found", "Comment not found.");
        }

        if (userSnap.exists) {
          const userData = userSnap.data() || {};
          if (userData.isBanned === true || isAccountDisabledData(userData)) {
            throw new HttpsError("permission-denied", "Account is banned.");
          }
        }

        const comment = commentSnap.data() || {};
        if (comment.isDeleted === true) {
          throw new HttpsError(
            "failed-precondition",
            "Comment is no longer available.",
          );
        }

        let likedBy = asAttendeeUidList(comment.likedBy);
        const alreadyLiked = likedBy.includes(uid);
        if (alreadyLiked) {
          likedBy = likedBy.filter((id) => id !== uid);
        } else {
          likedBy.push(uid);
        }
        const likesCount = likedBy.length;

        tx.set(
          commentRef,
          {
            likedBy,
            likesCount,
          },
          { merge: true },
        );

        return {
          eventId,
          commentId,
          liked: !alreadyLiked,
          likesCount,
        };
      });

      console.log(
        JSON.stringify({
          action: result.liked
            ? "event_comment_liked"
            : "event_comment_unliked",
          eventId,
          commentId,
          performedBy: uid,
          createdAt: new Date().toISOString(),
        }),
      );

      return {
        success: true,
        ...result,
      };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("Erro toggleEventCommentLike:", e);
      throw new HttpsError("internal", "Could not toggle like.");
    }
  },
);

/**
 * Exclusão lógica de comentário de evento.
 */
exports.deleteEventComment = socialOnCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const uid = request.auth.uid;
    const eventId = (request.data?.eventId || "").toString().trim();
    const commentId = (request.data?.commentId || "").toString().trim();
    if (!eventId || !commentId) {
      throw new HttpsError(
        "invalid-argument",
        "eventId and commentId required.",
      );
    }

    const db = admin.firestore();
    const eventRef = db.collection("events").doc(eventId);
    const commentRef = eventRef.collection("comments").doc(commentId);

    try {
      const result = await db.runTransaction(async (tx) => {
        const eventSnap = await tx.get(eventRef);
        const commentSnap = await tx.get(commentRef);

        if (!eventSnap.exists) {
          throw new HttpsError("not-found", "Event not found.");
        }
        if (!commentSnap.exists) {
          throw new HttpsError("not-found", "Comment not found.");
        }

        const eventData = eventSnap.data() || {};
        const comment = commentSnap.data() || {};
        const authorUid = (
          comment.uid ||
          comment.userId ||
          comment.authorId ||
          ""
        )
          .toString()
          .trim();
        const organizerUid = eventOrganizerUid(eventData);
        const canDelete = authorUid === uid || organizerUid === uid;

        if (!canDelete) {
          throw new HttpsError(
            "permission-denied",
            "Not allowed to delete this comment.",
          );
        }

        if (comment.isDeleted === true) {
          return {
            eventId,
            commentId,
            deleted: true,
            alreadyDeleted: true,
          };
        }

        tx.set(
          commentRef,
          {
            isDeleted: true,
            deletedAt: admin.firestore.FieldValue.serverTimestamp(),
            deletedBy: uid,
          },
          { merge: true },
        );

        return {
          eventId,
          commentId,
          deleted: true,
          alreadyDeleted: false,
        };
      });

      if (!result.alreadyDeleted) {
        console.log(
          JSON.stringify({
            action: "event_comment_deleted",
            eventId,
            commentId,
            performedBy: uid,
            createdAt: new Date().toISOString(),
          }),
        );
      }

      return {
        success: true,
        ...result,
      };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("Erro deleteEventComment:", e);
      throw new HttpsError("internal", "Could not delete comment.");
    }
  },
);

/**
 * Criar evento — ownership e aprovação só no backend.
 */
exports.createEvent = socialOnCall({ region: "us-central1" }, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  const uid = request.auth.uid;
  const dataIn = request.data || {};
  const requestId = asTrimmedString(dataIn.requestId, "requestId", {
    required: true,
    max: 128,
  });
  if (requestId.length < 8 || !/^[A-Za-z0-9_-]+$/.test(requestId)) {
    throw new HttpsError("invalid-argument", "Invalid requestId.");
  }

  const editorial = validateEventEditorial(dataIn, { forUpdate: false });
  const db = admin.firestore();
  const requestRef = db
    .collection("eventCreateRequests")
    .doc(`${uid}_${requestId}`);
  const userRef = db.collection("users").doc(uid);
  const publicRef = db.collection("publicUsers").doc(uid);

  try {
    const result = await db.runTransaction(async (tx) => {
      const requestSnap = await tx.get(requestRef);
      if (requestSnap.exists) {
        const prev = requestSnap.data() || {};
        return {
          eventId: (prev.eventId || "").toString(),
          status: (prev.status || "pending").toString(),
          created: false,
          alreadyCreated: true,
        };
      }

      const userSnap = await tx.get(userRef);
      const publicSnap = await tx.get(publicRef);
      if (!userSnap.exists && !publicSnap.exists) {
        throw new HttpsError("failed-precondition", "User profile not found.");
      }
      const userData = userSnap.exists
        ? userSnap.data() || {}
        : publicSnap.data() || {};
      if (userData.isBanned === true || isAccountDisabledData(userData)) {
        throw new HttpsError("permission-denied", "Account is banned.");
      }

      const eventRef = db.collection("events").doc();
      const payload = {
        ...buildCreateEditorialFields(editorial),
        startAt: admin.firestore.Timestamp.fromMillis(editorial.startAtMs),
        endAt: admin.firestore.Timestamp.fromMillis(editorial.endAtMs),
        archived: false,
        deleted: false,
        createdBy: uid,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        status: "pending",
        isActive: false,
        attendeesCount: 0,
        attendeesUids: [],
        sponsored: false,
        featured: false,
        featuredUntil: null,
      };

      tx.set(eventRef, payload);
      tx.set(requestRef, {
        uid,
        eventId: eventRef.id,
        requestId,
        status: "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        eventId: eventRef.id,
        status: "pending",
        created: true,
        alreadyCreated: false,
      };
    });

    if (result.created) {
      console.log(
        JSON.stringify({
          action: "event_created",
          eventId: result.eventId,
          performedBy: uid,
          createdAt: new Date().toISOString(),
        }),
      );
      // Imagem social: fire-and-forget — falha não desfaz criação.
      scheduleSocialImageJob(result.eventId, "createEvent");
    }

    return {
      success: true,
      eventId: result.eventId,
      status: result.status,
      alreadyCreated: result.alreadyCreated,
    };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("Erro createEvent:", e);
    throw new HttpsError("internal", "Could not create event.");
  }
});

/**
 * Abortar evento pending incompleto (falha de upload/finalize no app).
 * Soft-delete para o Admin não listar documento parcial.
 */
exports.abortIncompleteEvent = socialOnCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const uid = request.auth.uid;
    const dataIn = request.data || {};
    const eventId = asTrimmedString(dataIn.eventId, "eventId", {
      required: true,
      max: 128,
    });
    const reason = asTrimmedString(dataIn.reason, "reason", {
      required: false,
      max: 200,
    });

    const db = admin.firestore();
    const eventRef = db.collection("events").doc(eventId);

    try {
      const result = await db.runTransaction(async (tx) => {
        const snap = await tx.get(eventRef);
        if (!snap.exists) {
          return { aborted: false, reason: "not_found" };
        }

        const data = snap.data() || {};
        if (data.deleted === true) {
          return { aborted: true, reason: "already_deleted" };
        }

        const owner = resolveEventOwnerUid(data);
        if (!owner.ok || owner.uid !== uid) {
          throw new HttpsError(
            "permission-denied",
            "Not allowed to abort this event.",
          );
        }

        const statusNow = (data.status || "").toString().trim().toLowerCase();
        if (statusNow !== "pending" && statusNow !== "rejected") {
          throw new HttpsError(
            "failed-precondition",
            "Only pending/rejected events can be aborted.",
          );
        }

        tx.set(
          eventRef,
          {
            deleted: true,
            isActive: false,
            status: "cancelled",
            abortedAt: admin.firestore.FieldValue.serverTimestamp(),
            abortedBy: uid,
            abortReason: reason || "incomplete_create",
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );

        return { aborted: true, reason: "ok" };
      });

      console.log(
        JSON.stringify({
          action: "event_abort_incomplete",
          eventId,
          performedBy: uid,
          result,
          createdAt: new Date().toISOString(),
        }),
      );

      return { success: true, eventId, ...result };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("Erro abortIncompleteEvent:", e);
      throw new HttpsError("internal", "Could not abort incomplete event.");
    }
  },
);

/**
 * Atualizar campos editoriais do evento — aprovação/ownership só no backend.
 */

exports.updateEvent = socialOnCall({ region: "us-central1" }, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }

  const uid = request.auth.uid;
  const dataIn = request.data || {};
  const eventId = asTrimmedString(dataIn.eventId, "eventId", {
    required: true,
    max: 128,
  });

  const keys = Object.keys(dataIn).filter((k) => k !== "eventId");
  if (keys.length === 0) {
    throw new HttpsError("invalid-argument", "Empty update.");
  }

  const editorial = validateEventEditorial(dataIn, { forUpdate: true });
  const hasEditorialChange = keys.some((k) => EVENT_UPDATE_ALLOWED.has(k));
  if (!hasEditorialChange) {
    throw new HttpsError("invalid-argument", "Empty update.");
  }

  const db = admin.firestore();
  const eventRef = db.collection("events").doc(eventId);
  const userRef = db.collection("users").doc(uid);

  try {
    const result = await db.runTransaction(async (tx) => {
      const eventSnap = await tx.get(eventRef);
      const userSnap = await tx.get(userRef);

      if (!eventSnap.exists) {
        throw new HttpsError("not-found", "Event not found.");
      }

      const data = eventSnap.data() || {};
      if (data.deleted === true) {
        throw new HttpsError("failed-precondition", "Event unavailable.");
      }

      const owner = resolveEventOwnerUid(data);
      if (!owner.ok) {
        console.error(
          JSON.stringify({
            action: "event_owner_inconsistent",
            eventId,
            reason: owner.reason,
            uids: owner.uids || [],
            performedBy: uid,
          }),
        );
        throw new HttpsError(
          "failed-precondition",
          "Event ownership is inconsistent.",
        );
      }
      if (owner.uid !== uid) {
        throw new HttpsError(
          "permission-denied",
          "Not allowed to edit this event.",
        );
      }

      if (userSnap.exists) {
        const userData = userSnap.data() || {};
        if (userData.isBanned === true || isAccountDisabledData(userData)) {
          throw new HttpsError("permission-denied", "Account is banned.");
        }
      }

      const statusNow = (data.status || "").toString().trim().toLowerCase();
      if (statusNow === "cancelled") {
        throw new HttpsError(
          "failed-precondition",
          "Cancelled event cannot be edited.",
        );
      }

      const published = statusNow === "approved" && data.isActive === true;

      const editorialPatch = buildEventEditorialPatch(dataIn, editorial);
      if (Object.keys(editorialPatch).length === 0) {
        throw new HttpsError("invalid-argument", "Empty update.");
      }

      if (published) {
        const pendingChanges = buildPendingChangesMap(
          data,
          editorialPatch,
          uid,
        );
        const patch = {
          pendingChanges,
          hasPendingChanges: true,
          pendingChangesSubmittedAt:
            admin.firestore.FieldValue.serverTimestamp(),
          pendingChangesSubmittedBy: uid,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };
        // Clear previous rejection-of-changes markers if any.
        patch.pendingChangesRejectedAt = admin.firestore.FieldValue.delete();
        patch.pendingChangesRejectedBy = admin.firestore.FieldValue.delete();
        patch.pendingChangesRejectionReason =
          admin.firestore.FieldValue.delete();

        tx.set(eventRef, patch, { merge: true });
        return {
          eventId,
          status: "approved",
          hasPendingChanges: true,
          updateMode: "pending_changes",
          changedFields: Object.keys(editorialPatch),
        };
      }

      // pending / rejected (and approved-but-inactive): direct editorial update
      const patch = {
        ...editorialPatch,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        status: "pending",
        isActive: false,
        hasPendingChanges: false,
        pendingChanges: admin.firestore.FieldValue.delete(),
        pendingChangesSubmittedAt: admin.firestore.FieldValue.delete(),
        pendingChangesSubmittedBy: admin.firestore.FieldValue.delete(),
      };

      if (statusNow === "rejected") {
        patch.rejectedAt = admin.firestore.FieldValue.delete();
        patch.rejectedBy = admin.firestore.FieldValue.delete();
        patch.rejectionReason = admin.firestore.FieldValue.delete();
      }

      tx.set(eventRef, patch, { merge: true });
      return {
        eventId,
        status: "pending",
        hasPendingChanges: false,
        updateMode: "direct_pending",
        changedFields: Object.keys(editorialPatch),
      };
    });

    console.log(
      JSON.stringify({
        action: "event_updated",
        eventId,
        performedBy: uid,
        createdAt: new Date().toISOString(),
        updateMode: result.updateMode,
        changedFields: result.changedFields,
      }),
    );

    // Só regenera quando o patch editorial live mudou campos de social.
    // pending_changes (evento já publicado) não altera capa/título live ainda.
    if (
      result.updateMode === "direct_pending" &&
      Array.isArray(result.changedFields) &&
      result.changedFields.some((k) => SOCIAL_TRIGGER_FIELDS.includes(k))
    ) {
      scheduleSocialImageJob(eventId, "updateEvent");
    }

    return {
      success: true,
      eventId: result.eventId,
      status: result.status,
      hasPendingChanges: result.hasPendingChanges,
      updateMode: result.updateMode,
      changedFields: result.changedFields,
    };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("Erro updateEvent:", e);
    throw new HttpsError("internal", "Could not update event.");
  }
});

function cloneEditorialBaseFromEvent(data) {
  const base = {};
  for (const key of EVENT_PENDING_EDITORIAL_KEYS) {
    if (data[key] !== undefined) {
      base[key] = data[key];
    }
  }
  if (!Array.isArray(base.photoUrls)) {
    base.photoUrls = [];
  }
  if (typeof base.coverUrl !== "string") {
    base.coverUrl = (base.coverUrl || "").toString();
  }
  return base;
}

function buildPendingChangesMap(data, editorialPatch, uid) {
  const existing =
    data.hasPendingChanges === true &&
    data.pendingChanges &&
    typeof data.pendingChanges === "object" &&
    !Array.isArray(data.pendingChanges)
      ? data.pendingChanges
      : null;

  const base = existing ? { ...existing } : cloneEditorialBaseFromEvent(data);

  // Remove previous meta before rebuild.
  delete base.submittedAt;
  delete base.submittedBy;

  for (const [key, value] of Object.entries(editorialPatch)) {
    base[key] = value;
  }

  // Ensure only editorial keys remain (+ meta).
  const cleaned = {};
  for (const key of EVENT_PENDING_EDITORIAL_KEYS) {
    if (base[key] !== undefined) {
      cleaned[key] = base[key];
    }
  }
  cleaned.submittedBy = uid;
  cleaned.submittedAt = admin.firestore.FieldValue.serverTimestamp();
  return cleaned;
}

function pickEditorialFromPendingChanges(pending) {
  const out = {};
  for (const key of EVENT_PENDING_EDITORIAL_KEYS) {
    if (pending[key] !== undefined) {
      out[key] = pending[key];
    }
  }
  return out;
}

async function assertPortalEventAdmin(request) {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }
  const uid = request.auth.uid;
  if (request.auth.token?.admin === true) {
    return uid;
  }
  const db = admin.firestore();
  const userSnap = await db.collection("users").doc(uid).get();
  const userData = userSnap.exists ? userSnap.data() || {} : {};
  if (
    userData.isPlatformAdmin === true ||
    userData.isAdmin === true ||
    (userData.role || "").toString().trim().toLowerCase() === "admin"
  ) {
    return uid;
  }
  const adminSnap = await db.collection("admins").doc(uid).get();
  if (adminSnap.exists) {
    return uid;
  }
  throw new HttpsError("permission-denied", "Admin only.");
}

/**
 * Admin: aprovar pendingChanges de evento publicado.
 * Portal com Admin SDK também pode aplicar o mesmo merge diretamente.
 */
exports.approveEventPendingChanges = onCall(
  { region: "us-central1" },
  async (request) => {
    const adminUid = await assertPortalEventAdmin(request);
    const eventId = asTrimmedString(request.data?.eventId, "eventId", {
      required: true,
      max: 128,
    });
    const db = admin.firestore();
    const eventRef = db.collection("events").doc(eventId);

    try {
      const result = await db.runTransaction(async (tx) => {
        const snap = await tx.get(eventRef);
        if (!snap.exists) {
          throw new HttpsError("not-found", "Event not found.");
        }
        const data = snap.data() || {};
        if (data.deleted === true) {
          throw new HttpsError("failed-precondition", "Event unavailable.");
        }
        const statusNow = (data.status || "").toString().trim().toLowerCase();
        if (statusNow === "cancelled") {
          throw new HttpsError(
            "failed-precondition",
            "Cancelled event cannot be updated.",
          );
        }
        if (data.hasPendingChanges !== true) {
          throw new HttpsError("failed-precondition", "No pending changes.");
        }
        const pending = data.pendingChanges;
        if (!pending || typeof pending !== "object" || Array.isArray(pending)) {
          throw new HttpsError(
            "failed-precondition",
            "Invalid pendingChanges.",
          );
        }

        const editorial = pickEditorialFromPendingChanges(pending);
        const patch = {
          ...editorial,
          hasPendingChanges: false,
          pendingChanges: admin.firestore.FieldValue.delete(),
          pendingChangesSubmittedAt: admin.firestore.FieldValue.delete(),
          pendingChangesSubmittedBy: admin.firestore.FieldValue.delete(),
          pendingChangesRejectedAt: admin.firestore.FieldValue.delete(),
          pendingChangesRejectedBy: admin.firestore.FieldValue.delete(),
          pendingChangesRejectionReason: admin.firestore.FieldValue.delete(),
          pendingChangesApprovedAt:
            admin.firestore.FieldValue.serverTimestamp(),
          pendingChangesApprovedBy: adminUid,
          status: "approved",
          isActive: true,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        tx.set(eventRef, patch, { merge: true });
        return { eventId, approved: true };
      });

      console.log(
        JSON.stringify({
          action: "event_pending_changes_approved",
          eventId,
          performedBy: adminUid,
          createdAt: new Date().toISOString(),
        }),
      );

      return { success: true, ...result };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("Erro approveEventPendingChanges:", e);
      throw new HttpsError("internal", "Could not approve pending changes.");
    }
  },
);

/**
 * Admin: rejeitar pendingChanges — evento publicado permanece no ar.
 */
exports.rejectEventPendingChanges = onCall(
  { region: "us-central1" },
  async (request) => {
    const adminUid = await assertPortalEventAdmin(request);
    const eventId = asTrimmedString(request.data?.eventId, "eventId", {
      required: true,
      max: 128,
    });
    const reason = asTrimmedString(
      request.data?.reason ?? request.data?.rejectionReason,
      "reason",
      { required: false, max: 500 },
    );
    const db = admin.firestore();
    const eventRef = db.collection("events").doc(eventId);

    try {
      const result = await db.runTransaction(async (tx) => {
        const snap = await tx.get(eventRef);
        if (!snap.exists) {
          throw new HttpsError("not-found", "Event not found.");
        }
        const data = snap.data() || {};
        if (data.deleted === true) {
          throw new HttpsError("failed-precondition", "Event unavailable.");
        }
        const statusNow = (data.status || "").toString().trim().toLowerCase();
        if (statusNow === "cancelled") {
          throw new HttpsError(
            "failed-precondition",
            "Cancelled event cannot be updated.",
          );
        }
        if (data.hasPendingChanges !== true) {
          return { eventId, rejected: true, alreadyCleared: true };
        }

        const patch = {
          hasPendingChanges: false,
          pendingChanges: admin.firestore.FieldValue.delete(),
          pendingChangesSubmittedAt: admin.firestore.FieldValue.delete(),
          pendingChangesSubmittedBy: admin.firestore.FieldValue.delete(),
          pendingChangesRejectedAt:
            admin.firestore.FieldValue.serverTimestamp(),
          pendingChangesRejectedBy: adminUid,
          pendingChangesRejectionReason: reason || null,
          // Keep published.
          status: "approved",
          isActive: true,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        };

        tx.set(eventRef, patch, { merge: true });
        return { eventId, rejected: true, alreadyCleared: false };
      });

      if (!result.alreadyCleared) {
        console.log(
          JSON.stringify({
            action: "event_pending_changes_rejected",
            eventId,
            performedBy: adminUid,
            createdAt: new Date().toISOString(),
          }),
        );
      }

      return { success: true, ...result };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("Erro rejectEventPendingChanges:", e);
      throw new HttpsError("internal", "Could not reject pending changes.");
    }
  },
);

/**
 * Registrar visualização única de evento (viewsCount).
 */
exports.registerEventView = socialOnCall(
  { region: "us-central1" },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const uid = request.auth.uid;
    const eventId = (request.data?.eventId || "").toString().trim();
    if (!eventId || eventId.length > 128) {
      throw new HttpsError("invalid-argument", "eventId required.");
    }

    // viewerSessionId aceito mas não é fonte de verdade quando há auth.
    const sessionRaw = request.data?.viewerSessionId;
    if (
      sessionRaw !== undefined &&
      sessionRaw !== null &&
      typeof sessionRaw !== "string"
    ) {
      throw new HttpsError("invalid-argument", "Invalid viewerSessionId.");
    }

    const db = admin.firestore();
    const eventRef = db.collection("events").doc(eventId);
    const viewRef = eventRef.collection("views").doc(uid);
    const userRef = db.collection("users").doc(uid);

    try {
      const result = await db.runTransaction(async (tx) => {
        const eventSnap = await tx.get(eventRef);
        const viewSnap = await tx.get(viewRef);
        const userSnap = await tx.get(userRef);

        if (!eventSnap.exists) {
          throw new HttpsError("not-found", "Event not found.");
        }

        const data = eventSnap.data() || {};
        if (data.deleted === true) {
          throw new HttpsError("failed-precondition", "Event unavailable.");
        }

        const status = (data.status || "").toString().trim().toLowerCase();
        if (status === "cancelled") {
          throw new HttpsError("failed-precondition", "Event unavailable.");
        }
        if (status !== "approved" || data.isActive !== true) {
          throw new HttpsError("failed-precondition", "Event unavailable.");
        }

        if (userSnap.exists) {
          const userData = userSnap.data() || {};
          if (userData.isBanned === true || isAccountDisabledData(userData)) {
            throw new HttpsError("permission-denied", "Account is banned.");
          }
        }

        const owner = resolveEventOwnerUid(data);
        const isOrganizer = owner.ok && owner.uid === uid;

        let viewsCount =
          typeof data.viewsCount === "number" &&
          Number.isFinite(data.viewsCount)
            ? Math.max(0, Math.floor(data.viewsCount))
            : 0;

        // Organizador não infla o contador público.
        if (isOrganizer) {
          if (viewSnap.exists) {
            tx.set(
              viewRef,
              {
                lastViewedAt: admin.firestore.FieldValue.serverTimestamp(),
              },
              { merge: true },
            );
          } else {
            tx.set(viewRef, {
              uid,
              firstViewedAt: admin.firestore.FieldValue.serverTimestamp(),
              lastViewedAt: admin.firestore.FieldValue.serverTimestamp(),
              viewCount: 0,
              isOrganizer: true,
            });
          }
          return {
            eventId,
            counted: false,
            countedUnique: false,
            viewsCount,
            totalOpensCount: viewsCount,
          };
        }

        if (viewSnap.exists) {
          const prev = viewSnap.data() || {};
          const prevOpens =
            typeof prev.viewCount === "number" ? prev.viewCount : 1;
          tx.set(
            viewRef,
            {
              lastViewedAt: admin.firestore.FieldValue.serverTimestamp(),
              viewCount: prevOpens + 1,
            },
            { merge: true },
          );
          return {
            eventId,
            counted: false,
            countedUnique: false,
            viewsCount,
            totalOpensCount: viewsCount,
          };
        }

        viewsCount += 1;
        tx.set(viewRef, {
          uid,
          firstViewedAt: admin.firestore.FieldValue.serverTimestamp(),
          lastViewedAt: admin.firestore.FieldValue.serverTimestamp(),
          viewCount: 1,
          isOrganizer: false,
        });
        tx.set(
          eventRef,
          {
            viewsCount,
          },
          { merge: true },
        );

        return {
          eventId,
          counted: true,
          countedUnique: true,
          viewsCount,
          totalOpensCount: viewsCount,
        };
      });

      if (result.counted) {
        console.log(
          JSON.stringify({
            action: "event_view_registered",
            eventId,
            performedBy: uid,
            createdAt: new Date().toISOString(),
          }),
        );
      }

      return {
        success: true,
        eventId: result.eventId,
        counted: result.counted,
        countedUnique: result.countedUnique,
        viewsCount: result.viewsCount,
        totalOpensCount: result.totalOpensCount,
      };
    } catch (e) {
      if (e instanceof HttpsError) throw e;
      console.error("Erro registerEventView:", e);
      throw new HttpsError("internal", "Could not register view.");
    }
  },
);

/**
 * Cancelar evento — somente organizador (createdBy/ownerUid/organizerId).
 */
exports.cancelEvent = socialOnCall({ region: "us-central1" }, async (request) => {
  if (!request.auth || !request.auth.uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }
  const uid = request.auth.uid;
  const eventId = (request.data?.eventId || "").toString().trim();
  if (!eventId) {
    throw new HttpsError("invalid-argument", "eventId required.");
  }

  const db = admin.firestore();
  const eventRef = db.collection("events").doc(eventId);
  const userRef = db.collection("users").doc(uid);

  try {
    const result = await db.runTransaction(async (tx) => {
      const snap = await tx.get(eventRef);
      const userSnap = await tx.get(userRef);
      if (!snap.exists) {
        throw new HttpsError("not-found", "Event not found.");
      }
      const data = snap.data() || {};
      if (data.deleted === true) {
        throw new HttpsError("failed-precondition", "Event unavailable.");
      }
      if (!userSnap.exists || userSnap.data()?.isBanned === true) {
        throw new HttpsError("permission-denied", "Not allowed.");
      }

      const owner = (
        data.organizerId ||
        data.createdBy ||
        data.ownerUid ||
        data.userId ||
        ""
      )
        .toString()
        .trim();
      if (owner !== uid) {
        throw new HttpsError("permission-denied", "Only organizer can cancel.");
      }

      const statusNow = (data.status || "").toString().trim().toLowerCase();
      if (statusNow === "cancelled") {
        return { eventId, alreadyCancelled: true };
      }

      tx.set(
        eventRef,
        {
          status: "cancelled",
          isActive: false,
          cancelledAt: admin.firestore.FieldValue.serverTimestamp(),
          cancelledBy: uid,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return { eventId, alreadyCancelled: false };
    });

    console.log(
      JSON.stringify({
        action: "event_cancelled",
        eventId,
        performedBy: uid,
        createdAt: new Date().toISOString(),
      }),
    );
    return { success: true, ...result };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("Erro cancelEvent:", e);
    throw new HttpsError("internal", "Could not cancel event.");
  }
});


// ---------------------------------------------------------------------------
// Event lifecycle (local prep — do not deploy without authorization)
// ---------------------------------------------------------------------------

function assertEventOwner(uid, data) {
  const owner = resolveEventOwnerUid(data);
  if (!owner.ok || owner.uid !== uid) {
    throw new HttpsError("permission-denied", "Only organizer can manage.");
  }
  return owner.uid;
}

function eventHasFinancialRetention(data) {
  if (!data || typeof data !== "object") return false;
  if (data.retentionRequired === true) return true;
  if (data.hasPayments === true) return true;
  if (data.paymentRetention === true) return true;
  if (data.disputed === true) return true;
  if (data.ticketSales === true) return true;
  if (Array.isArray(data.orderIds) && data.orderIds.length > 0) return true;
  if (data.boosted === true) return true;
  const boostStatus = (data.boostStatus || "").toString().toLowerCase();
  if (boostStatus && !["none", "expired", "cancelled", "canceled"].includes(boostStatus)) {
    return true;
  }
  for (const key of Object.keys(data)) {
    if (/^stripe/i.test(key) && data[key]) return true;
  }
  return false;
}

exports.archiveEvent = socialOnCall({ region: "us-central1" }, async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Login required.");
  const uid = request.auth.uid;
  const eventId = asTrimmedString(request.data?.eventId, "eventId", { required: true, max: 128 });
  const db = admin.firestore();
  const ref = db.collection("events").doc(eventId);
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Event not found.");
    const data = snap.data() || {};
    assertEventOwner(uid, data);
    if (data.archived === true) return { eventId, alreadyArchived: true };
    tx.set(
      ref,
      {
        archived: true,
        archivedAt: admin.firestore.FieldValue.serverTimestamp(),
        archivedBy: uid,
        isActive: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { eventId, alreadyArchived: false };
  });
  return { success: true, ...result };
});

exports.restoreEvent = socialOnCall({ region: "us-central1" }, async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Login required.");
  const uid = request.auth.uid;
  const eventId = asTrimmedString(request.data?.eventId, "eventId", { required: true, max: 128 });
  const db = admin.firestore();
  const ref = db.collection("events").doc(eventId);
  const result = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Event not found.");
    const data = snap.data() || {};
    assertEventOwner(uid, data);
    if (data.archived !== true) return { eventId, alreadyRestored: true };
    // Não reaprova automaticamente.
    tx.set(
      ref,
      {
        archived: false,
        archivedAt: admin.firestore.FieldValue.delete(),
        archivedBy: admin.firestore.FieldValue.delete(),
        restoredAt: admin.firestore.FieldValue.serverTimestamp(),
        restoredBy: uid,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { eventId, alreadyRestored: false };
  });
  return { success: true, ...result };
});

exports.duplicateEvent = socialOnCall({ region: "us-central1" }, async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Login required.");
  const uid = request.auth.uid;
  const eventId = asTrimmedString(request.data?.eventId, "eventId", { required: true, max: 128 });
  const db = admin.firestore();
  const srcRef = db.collection("events").doc(eventId);
  const srcSnap = await srcRef.get();
  if (!srcSnap.exists) throw new HttpsError("not-found", "Event not found.");
  const src = srcSnap.data() || {};
  assertEventOwner(uid, src);

  // Datas antigas NÃO são copiadas. Placeholder de agenda obrigatório no schema
  // (start/end) — organizador deve editar antes de publicar. needsSchedule=true.
  const startMs = Date.now() + 14 * 24 * 3600 * 1000;
  const endMs = startMs + 2 * 3600 * 1000;
  const tz =
    parseEventTimeZone(src.eventTimeZone, { required: false }) ||
    "America/Toronto";

  const newRef = db.collection("events").doc();
  const payload = {
    title: (src.title || "").toString(),
    description: (src.description || "").toString(),
    category: (src.category || "").toString(),
    city: (src.city || "").toString(),
    cityKey: (src.cityKey || "").toString(),
    stateName: (src.stateName || "").toString(),
    placeName: (src.placeName || "").toString(),
    address: (src.address || "").toString(),
    placeDisplay: (src.placeDisplay || "").toString(),
    lat: src.lat ?? null,
    lng: src.lng ?? null,
    countryCode: (src.countryCode || "").toString(),
    regionKey: (src.regionKey || "").toString(),
    scope: (src.scope || "city").toString(),
    coverUrl: typeof src.coverUrl === "string" ? src.coverUrl : "",
    photoUrls: Array.isArray(src.photoUrls) ? src.photoUrls.slice(0, 5) : [],
    startAt: admin.firestore.Timestamp.fromMillis(startMs),
    endAt: admin.firestore.Timestamp.fromMillis(endMs),
    eventTimeZone: tz,
    needsSchedule: true,
    duplicatedFrom: eventId,
    createdBy: uid,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    status: "pending",
    isActive: false,
    archived: false,
    deleted: false,
    attendeesCount: 0,
    attendeesUids: [],
    sponsorInterested: false,
    sponsorStatus: "none",
    sponsored: false,
    featured: false,
    featuredUntil: null,
  };
  await newRef.set(payload);
  return { success: true, eventId: newRef.id, needsSchedule: true };
});

exports.deleteEventPermanently = socialOnCall({ region: "us-central1" }, async (request) => {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "Login required.");
  const uid = request.auth.uid;
  const eventId = asTrimmedString(request.data?.eventId, "eventId", { required: true, max: 128 });
  const confirm = asTrimmedString(request.data?.confirm, "confirm", { required: true, max: 64 });
  if (confirm !== "DELETE_PERMANENTLY") {
    throw new HttpsError("invalid-argument", "Strong confirmation required.");
  }
  const db = admin.firestore();
  const ref = db.collection("events").doc(eventId);
  const snap = await ref.get();
  if (!snap.exists) {
    return { success: true, eventId, alreadyDeleted: true };
  }
  const data = snap.data() || {};
  assertEventOwner(uid, data);

  if (eventHasFinancialRetention(data)) {
    throw new HttpsError(
      "failed-precondition",
      "retention_required",
    );
  }

  const status = (data.status || "").toString().toLowerCase();
  const endAt = data.endAt;
  let endMs = null;
  if (endAt && typeof endAt.toMillis === "function") endMs = endAt.toMillis();
  const now = Date.now();
  const isPast = endMs != null && endMs < now;
  const isCancelled = status === "cancelled" || status === "canceled";
  const isArchived = data.archived === true;
  if (!(isPast || isCancelled || isArchived)) {
    throw new HttpsError(
      "failed-precondition",
      "Only past, cancelled, or archived events can be permanently deleted.",
    );
  }

  if (data.deleted === true && data.permanentlyDeletedAt) {
    return { success: true, eventId, alreadyDeleted: true };
  }

  // Soft marker + cleanup de subcoleções ligadas ao evento.
  await ref.set(
    {
      deleted: true,
      isActive: false,
      permanentlyDeletedAt: admin.firestore.FieldValue.serverTimestamp(),
      permanentlyDeletedBy: uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );

  async function deleteCollection(path) {
    const col = db.collection(path);
    while (true) {
      const batchSnap = await col.limit(200).get();
      if (batchSnap.empty) break;
      const batch = db.batch();
      for (const d of batchSnap.docs) batch.delete(d.ref);
      await batch.commit();
      if (batchSnap.size < 200) break;
    }
  }

  await deleteCollection(`events/${eventId}/attendees`);
  await deleteCollection(`events/${eventId}/comments`);
  await deleteCollection(`events/${eventId}/likes`);

  // Best-effort Storage cleanup under events/{eventId}/
  try {
    const bucket = admin.storage().bucket();
    await bucket.deleteFiles({ prefix: `events/${eventId}/` });
  } catch (e) {
    console.warn("deleteEventPermanently storage cleanup failed", eventId, e);
  }

  // Remover doc do evento após limpar derivados (sem tocar users/conversations).
  await ref.delete();
  return { success: true, eventId, alreadyDeleted: false };
});
