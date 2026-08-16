/**
 * RevenueCat webhook + sync server-side do entitlement Premium.
 * Cliente Flutter NÃO concede isPremium.
 */
const { onRequest } = require("firebase-functions/v2/https");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");

const REVENUECAT_WEBHOOK_SECRET = defineSecret("REVENUECAT_WEBHOOK_SECRET");
const REVENUECAT_SECRET_API_KEY = defineSecret("REVENUECAT_SECRET_API_KEY");

/** Entitlement oficial no RevenueCat (mesmo ID do app). */
const PREMIUM_ENTITLEMENT_ID = "premium";

const STORE_MAP = {
  APP_STORE: "ios",
  MAC_APP_STORE: "ios",
  PLAY_STORE: "android",
  STRIPE: "stripe",
  PROMOTIONAL: "promotional",
  AMAZON: "amazon",
  RC_BILLING: "rc_billing",
  ROKU: "roku",
};

function authHeaderMatches(req, secret) {
  const expected = (secret || "").toString();
  if (!expected) return false;

  const header = (req.get("authorization") || req.get("Authorization") || "")
    .toString()
    .trim();
  if (!header) return false;

  // RevenueCat envia o valor configurado no dashboard (pode ou não ter "Bearer ")
  if (header === expected) return true;
  if (header === `Bearer ${expected}`) return true;
  if (expected.startsWith("Bearer ") && header === expected.slice(7).trim()) {
    return true;
  }
  return false;
}

function looksLikeFirebaseUid(value) {
  const s = (value || "").toString().trim();
  return /^[A-Za-z0-9]{20,128}$/.test(s);
}

async function resolveFirebaseUid(event) {
  const candidates = [];
  const appUserId = (event.app_user_id || "").toString().trim();
  const original = (event.original_app_user_id || "").toString().trim();
  const aliases = Array.isArray(event.aliases) ? event.aliases : [];

  if (appUserId) candidates.push(appUserId);
  if (original) candidates.push(original);
  for (const a of aliases) {
    const v = (a || "").toString().trim();
    if (v) candidates.push(v);
  }

  const db = admin.firestore();
  const tried = new Set();

  for (const id of candidates) {
    if (tried.has(id)) continue;
    tried.add(id);
    if (!looksLikeFirebaseUid(id)) continue;

    const snap = await db.collection("users").doc(id).get();
    if (snap.exists) {
      const data = snap.data() || {};
      if (data.accountDeleted === true) continue;
      return id;
    }
  }

  return null;
}

function hasPremiumEntitlement(event) {
  const ids = Array.isArray(event.entitlement_ids)
    ? event.entitlement_ids.map((x) => (x || "").toString())
    : [];
  if (ids.includes(PREMIUM_ENTITLEMENT_ID)) return true;
  if ((event.entitlement_id || "").toString() === PREMIUM_ENTITLEMENT_ID) {
    return true;
  }
  // Projetos com um único entitlement de assinatura: se o evento não trouxer
  // entitlement_ids, ainda processamos ciclo de vida da assinatura.
  if (ids.length === 0 && !event.entitlement_id) return null;
  return false;
}

function expirationDate(event) {
  const ms = event.expiration_at_ms;
  if (typeof ms === "number" && Number.isFinite(ms) && ms > 0) {
    return new Date(ms);
  }
  return null;
}

function platformFromStore(store) {
  const key = (store || "").toString().toUpperCase();
  return STORE_MAP[key] || (store || "").toString().toLowerCase() || "unknown";
}

/**
 * Decide estado da assinatura paga com base no evento.
 * Nunca altera premiumUntil (convite).
 */
function buildSubscriptionPatchFromEvent(event, now = new Date()) {
  const type = (event.type || "").toString();
  const expiresAt = expirationDate(event);
  const expiresFuture = expiresAt ? expiresAt.getTime() > now.getTime() : false;
  const productId = (event.product_id || "").toString() || null;
  const platform = platformFromStore(event.store);
  const entitlementCheck = hasPremiumEntitlement(event);

  // TRANSFER: não atribuir assinatura automaticamente
  if (type === "TRANSFER") {
    return { skip: true, reason: "transfer_skipped" };
  }

  const base = {
    subscriptionProductId: productId,
    subscriptionPlatform: platform,
    subscriptionUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    revenueCatAppUserId: (event.app_user_id || "").toString() || null,
  };

  if (expiresAt) {
    base.subscriptionExpiresAt = admin.firestore.Timestamp.fromDate(expiresAt);
  }

  // EXPIRATION / revoke access
  if (type === "EXPIRATION") {
    return {
      skip: false,
      patch: {
        ...base,
        isPremium: false,
        subscriptionStatus: "expired",
        premiumSource: admin.firestore.FieldValue.delete(),
      },
    };
  }

  // Refund often arrives as CANCELLATION with cancel_reason
  const cancelReason = (event.cancel_reason || "").toString().toUpperCase();
  if (type === "CANCELLATION") {
    const refundLike =
      cancelReason === "CUSTOMER_SUPPORT" ||
      cancelReason.includes("REFUND");

    // Ainda no período pago → acesso permanece
    if (expiresFuture) {
      return {
        skip: false,
        patch: {
          ...base,
          isPremium: true,
          subscriptionStatus: "canceled",
          premiumSource: "store",
        },
      };
    }

    // Já expirou / reembolso imediato
    return {
      skip: false,
      patch: {
        ...base,
        isPremium: false,
        subscriptionStatus: refundLike ? "refunded" : "expired",
        premiumSource: admin.firestore.FieldValue.delete(),
      },
    };
  }

  if (type === "BILLING_ISSUE") {
    return {
      skip: false,
      patch: {
        ...base,
        // Não revogar imediatamente
        isPremium: entitlementCheck === false ? false : true,
        subscriptionStatus: "billing_issue",
        ...(entitlementCheck === false
          ? { premiumSource: admin.firestore.FieldValue.delete() }
          : { premiumSource: "store" }),
      },
    };
  }

  if (type === "SUBSCRIPTION_PAUSED") {
    return {
      skip: false,
      patch: {
        ...base,
        isPremium: true,
        subscriptionStatus: "paused",
        premiumSource: "store",
      },
    };
  }

  const activateTypes = new Set([
    "INITIAL_PURCHASE",
    "RENEWAL",
    "UNCANCELLATION",
    "NON_RENEWING_PURCHASE",
    "SUBSCRIPTION_EXTENDED",
    "PRODUCT_CHANGE",
    "REFUND_REVERSED",
    "TEST",
  ]);

  if (activateTypes.has(type)) {
    if (entitlementCheck === false) {
      return {
        skip: false,
        patch: {
          ...base,
          isPremium: false,
          subscriptionStatus: "inactive",
          premiumSource: admin.firestore.FieldValue.delete(),
        },
      };
    }

    const active = expiresAt ? expiresFuture : true;
    return {
      skip: false,
      patch: {
        ...base,
        isPremium: active,
        subscriptionStatus: active ? "active" : "expired",
        ...(active
          ? { premiumSource: "store" }
          : { premiumSource: admin.firestore.FieldValue.delete() }),
      },
    };
  }

  return { skip: true, reason: `ignored_type_${type || "unknown"}` };
}

async function alreadyProcessed(eventId) {
  if (!eventId) return false;
  const ref = admin.firestore().collection("revenueCatEvents").doc(eventId);
  const snap = await ref.get();
  return snap.exists;
}

async function markProcessed(eventId, meta) {
  if (!eventId) return;
  await admin
    .firestore()
    .collection("revenueCatEvents")
    .doc(eventId)
    .set(
      {
        ...meta,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
}

async function applyPatchToUser(uid, patch, eventId, eventType) {
  const db = admin.firestore();
  const userRef = db.collection("users").doc(uid);

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    if (!snap.exists) {
      throw new Error("USER_NOT_FOUND");
    }

    // Idempotência dentro da transaction do evento
    if (eventId) {
      const eventRef = db.collection("revenueCatEvents").doc(eventId);
      const eventSnap = await tx.get(eventRef);
      if (eventSnap.exists) {
        return;
      }
      tx.set(eventRef, {
        uid,
        type: eventType || null,
        processedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }

    // Nunca tocar campos de convite
    const safePatch = { ...patch };
    delete safePatch.premiumUntil;
    delete safePatch.premiumType;
    delete safePatch.inviteRewardLevel;
    delete safePatch.isAmbassador;
    delete safePatch.invitesCount;

    // Se assinatura paga acaba, preservar premiumUntil de convite
    if (safePatch.isPremium === false) {
      const data = snap.data() || {};
      const until = data.premiumUntil;
      let inviteActive = false;
      if (until && until.toDate) {
        try {
          inviteActive = until.toDate().getTime() > Date.now();
        } catch (_) {}
      }
      if (inviteActive) {
        // Não apagar premiumSource se for invite; marcar origem do benefício ativo
        safePatch.premiumSource = "invite";
      }
    }

    tx.set(userRef, safePatch, { merge: true });
  });
}

async function handleWebhookEvent(event) {
  const eventId = (event.id || "").toString().trim();
  const type = (event.type || "").toString();

  if (eventId && (await alreadyProcessed(eventId))) {
    return { ok: true, duplicate: true, eventId };
  }

  const built = buildSubscriptionPatchFromEvent(event);
  if (built.skip) {
    if (eventId) {
      await markProcessed(eventId, {
        uid: null,
        type,
        skipped: true,
        reason: built.reason || null,
      });
    }
    return { ok: true, skipped: true, reason: built.reason, eventId };
  }

  const uid = await resolveFirebaseUid(event);
  if (!uid) {
    console.warn(
      JSON.stringify({
        action: "revenuecat_webhook_uid_not_found",
        type,
        eventId: eventId ? eventId.slice(0, 12) : null,
        appUserPrefix: (event.app_user_id || "").toString().slice(0, 6),
      })
    );
    // 200 para evitar retry infinito de UID inválido/anônimo
    if (eventId) {
      await markProcessed(eventId, {
        uid: null,
        type,
        skipped: true,
        reason: "uid_not_found",
      });
    }
    return { ok: true, skipped: true, reason: "uid_not_found", eventId };
  }

  try {
    if (eventId) {
      built.patch.revenueCatLastEventId = eventId;
    }
    await applyPatchToUser(uid, built.patch, eventId, type);
  } catch (e) {
    if ((e && e.message) === "USER_NOT_FOUND") {
      if (eventId) {
        await markProcessed(eventId, {
          uid: null,
          type,
          skipped: true,
          reason: "uid_not_found",
        });
      }
      return { ok: true, skipped: true, reason: "uid_not_found", eventId };
    }
    throw e;
  }

  console.log(
    JSON.stringify({
      action: "revenuecat_webhook_applied",
      type,
      uidPrefix: uid.slice(0, 6),
      isPremium: built.patch.isPremium === true,
      status: built.patch.subscriptionStatus || null,
      eventId: eventId ? eventId.slice(0, 12) : null,
    })
  );

  return { ok: true, applied: true, uidPrefix: uid.slice(0, 6), eventId };
}

/**
 * HTTPS webhook — Authorization header = REVENUECAT_WEBHOOK_SECRET
 */
exports.revenueCatWebhook = onRequest(
  {
    region: "us-central1",
    secrets: [REVENUECAT_WEBHOOK_SECRET],
    timeoutSeconds: 60,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    let secret = "";
    try {
      secret = REVENUECAT_WEBHOOK_SECRET.value();
    } catch (_) {
      secret = "";
    }

    if (!secret) {
      console.error("REVENUECAT_WEBHOOK_SECRET missing");
      res.status(500).send("Server misconfigured");
      return;
    }

    if (!authHeaderMatches(req, secret)) {
      res.status(401).send("Unauthorized");
      return;
    }

    const body = req.body || {};
    const event = body.event || body;
    if (!event || typeof event !== "object" || !event.type) {
      res.status(400).send("Invalid payload");
      return;
    }

    try {
      const result = await handleWebhookEvent(event);
      res.status(200).json(result);
    } catch (e) {
      console.error(
        JSON.stringify({
          action: "revenuecat_webhook_error",
          message: (e && e.message) || "unknown",
        })
      );
      res.status(500).send("Internal error");
    }
  }
);

/**
 * Consulta API secreta do RevenueCat e sincroniza entitlement no Firestore.
 */
async function fetchSubscriber(appUserId, apiKey) {
  const encoded = encodeURIComponent(appUserId);
  const url = `https://api.revenuecat.com/v1/subscribers/${encoded}`;
  const response = await fetch(url, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
  });

  if (response.status === 404) {
    return null;
  }
  if (!response.ok) {
    const text = await response.text();
    throw new Error(`RC_API_${response.status}:${text.slice(0, 120)}`);
  }
  return response.json();
}

function patchFromSubscriber(subscriberPayload) {
  const subscriber = subscriberPayload?.subscriber || subscriberPayload || {};
  const entitlements = subscriber.entitlements || {};
  const premium = entitlements[PREMIUM_ENTITLEMENT_ID];

  if (!premium) {
    return {
      isPremium: false,
      subscriptionStatus: "inactive",
      subscriptionUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      premiumSource: admin.firestore.FieldValue.delete(),
    };
  }

  const expiresRaw = premium.expires_date || premium.expires_date_ms;
  let expiresAt = null;
  if (typeof expiresRaw === "string") {
    const d = new Date(expiresRaw);
    if (!Number.isNaN(d.getTime())) expiresAt = d;
  } else if (typeof expiresRaw === "number") {
    expiresAt = new Date(expiresRaw);
  }

  const active =
    !expiresAt || expiresAt.getTime() > Date.now() || premium.expires_date === null;

  // product identifier from entitlement
  const productId =
    (premium.product_identifier || premium.product_id || "").toString() || null;

  const patch = {
    isPremium: active === true,
    subscriptionStatus: active ? "active" : "expired",
    subscriptionProductId: productId,
    subscriptionUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
    revenueCatAppUserId: (subscriber.original_app_user_id || "").toString() || null,
  };

  if (expiresAt) {
    patch.subscriptionExpiresAt = admin.firestore.Timestamp.fromDate(expiresAt);
  }

  if (active) {
    patch.premiumSource = "store";
  } else {
    patch.premiumSource = admin.firestore.FieldValue.delete();
  }

  return patch;
}

exports.syncRevenueCatEntitlement = onCall(
  {
    region: "us-central1",
    secrets: [REVENUECAT_SECRET_API_KEY],
    timeoutSeconds: 30,
  },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const uid = request.auth.uid;
    let apiKey = "";
    try {
      apiKey = REVENUECAT_SECRET_API_KEY.value();
    } catch (_) {
      apiKey = "";
    }

    if (!apiKey) {
      return {
        success: false,
        configured: false,
        message: "RevenueCat secret API key not configured.",
      };
    }

    try {
      const payload = await fetchSubscriber(uid, apiKey);
      if (!payload) {
        await admin.firestore().collection("users").doc(uid).set(
          {
            isPremium: false,
            subscriptionStatus: "inactive",
            subscriptionUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        );
        return { success: true, configured: true, isPremium: false };
      }

      const patch = patchFromSubscriber(payload);
      // Preserve invite fields
      delete patch.premiumUntil;
      delete patch.premiumType;

      const userRef = admin.firestore().collection("users").doc(uid);
      const snap = await userRef.get();
      if (!snap.exists) {
        throw new HttpsError("not-found", "User not found.");
      }

      if (patch.isPremium === false) {
        const data = snap.data() || {};
        const until = data.premiumUntil;
        if (until && until.toDate && until.toDate().getTime() > Date.now()) {
          patch.premiumSource = "invite";
        }
      }

      await userRef.set(patch, { merge: true });

      return {
        success: true,
        configured: true,
        isPremium: patch.isPremium === true,
        subscriptionStatus: patch.subscriptionStatus || null,
      };
    } catch (e) {
      console.error(
        JSON.stringify({
          action: "sync_revenuecat_failed",
          uidPrefix: uid.slice(0, 6),
          message: (e && e.message) || "unknown",
        })
      );
      throw new HttpsError("internal", "Could not sync entitlement.");
    }
  }
);

exports.PREMIUM_ENTITLEMENT_ID = PREMIUM_ENTITLEMENT_ID;
exports._buildSubscriptionPatchFromEvent = buildSubscriptionPatchFromEvent;
