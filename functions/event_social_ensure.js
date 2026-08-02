/**
 * Garante arte social OG no Storage + campos Firestore.
 * Idempotente por hash. Falhas são logadas — nunca propagar para create/update.
 */
"use strict";

const crypto = require("crypto");
const admin = require("firebase-admin");
const {
  computeSocialContentHash,
  renderSocialJpeg,
  pickCoverSource,
  SOCIAL_MIME,
  SOCIAL_TRIGGER_FIELDS,
  socialInputsChanged,
} = require("./event_social_image");

const STORAGE_PREFIX = "public_social";
const DEFAULT_BUCKET = "socialchatmvp.firebasestorage.app";

function resolveBucketName() {
  if (process.env.GCLOUD_STORAGE_BUCKET) {
    return process.env.GCLOUD_STORAGE_BUCKET;
  }
  if (process.env.FIREBASE_CONFIG) {
    try {
      const cfg = JSON.parse(process.env.FIREBASE_CONFIG);
      if (cfg && cfg.storageBucket) return cfg.storageBucket;
    } catch {
      /* fall through */
    }
  }
  return DEFAULT_BUCKET;
}

const BUCKET = resolveBucketName();

function asTrimmed(v) {
  if (v == null) return "";
  return v.toString().trim();
}

function readDate(value) {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (typeof value.toDate === "function") {
    try {
      return value.toDate();
    } catch {
      return null;
    }
  }
  if (typeof value === "number" && Number.isFinite(value)) return new Date(value);
  if (typeof value._seconds === "number") return new Date(value._seconds * 1000);
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

function formatDateLabel(data) {
  const tz = asTrimmed(data.eventTimeZone) || "America/Sao_Paulo";
  const start = readDate(data.startAt);
  const end = readDate(data.endAt);
  if (!start) return "";
  try {
    const opts = {
      timeZone: tz,
      day: "numeric",
      month: "long",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    };
    const a = new Intl.DateTimeFormat("pt-BR", opts).format(start);
    if (!end) return a;
    const b = new Intl.DateTimeFormat("pt-BR", {
      timeZone: tz,
      hour: "2-digit",
      minute: "2-digit",
    }).format(end);
    return `${a} – ${b}`;
  } catch {
    return start.toISOString();
  }
}

function locationLabel(data) {
  const city = asTrimmed(data.city);
  const state = asTrimmed(data.stateName || data.state);
  if (asTrimmed(data.scope) === "country" || asTrimmed(data.reachScope) === "country") {
    return city || "Brasil";
  }
  return [city, state].filter(Boolean).join(" - ");
}

function buildSocialInput(eventId, data) {
  const coverUrl = asTrimmed(data.coverUrl);
  const photos = Array.isArray(data.photoUrls) ? data.photoUrls : [];
  const galleryFallbackUrl = photos
    .map((u) => asTrimmed(u))
    .find((u) => /^https:\/\//i.test(u));
  return {
    eventId,
    title: asTrimmed(data.title) || "Evento Remdy",
    dateLabel: formatDateLabel(data),
    locationLabel: locationLabel(data),
    category: asTrimmed(data.category),
    coverUrl: /^https:\/\//i.test(coverUrl) ? coverUrl : "",
    galleryFallbackUrl: galleryFallbackUrl || "",
  };
}

async function fetchCoverBytes(url) {
  if (!url) return null;
  try {
    const res = await fetch(url, {
      headers: { "User-Agent": "RemdySocialImage/1.0" },
      signal: AbortSignal.timeout(12000),
    });
    if (!res.ok) return null;
    const ct = (res.headers.get("content-type") || "").toLowerCase();
    if (ct && !ct.startsWith("image/")) return null;
    const buf = Buffer.from(await res.arrayBuffer());
    if (buf.length > 15 * 1024 * 1024) return null;
    return buf;
  } catch {
    return null;
  }
}

function objectPath(eventId, hash) {
  const safe = eventId.replace(/[^A-Za-z0-9_-]/g, "_");
  return `${STORAGE_PREFIX}/${safe}/og_${hash}.jpg`;
}

function publicUrlFor(bucketName, path) {
  return `https://storage.googleapis.com/${bucketName}/${path}`;
}

function firebaseDownloadUrl(bucketName, objectPath, token) {
  const encoded = encodeURIComponent(objectPath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encoded}?alt=media&token=${token}`;
}

function newDownloadToken() {
  return crypto.randomUUID();
}

/**
 * Garante imagem social. Retorna { reused|generated, url, hash } ou { skipped, error }.
 */
async function ensureEventSocialImage(eventId) {
  const db = admin.firestore();
  const ref = db.collection("events").doc(eventId);
  const snap = await ref.get();
  if (!snap.exists) {
    return { skipped: true, reason: "not_found" };
  }
  const data = snap.data() || {};
  if (data.deleted === true) {
    return { skipped: true, reason: "deleted" };
  }

  const input = buildSocialInput(eventId, data);
  const hash = computeSocialContentHash(input);
  const existingHash = asTrimmed(data.socialShareImageHash);
  const existingUrl = asTrimmed(data.socialShareImageUrl);
  if (existingHash === hash && /^https:\/\//i.test(existingUrl)) {
    return { reused: true, generated: false, url: existingUrl, hash };
  }

  const picked = pickCoverSource(input);
  let coverBytes = null;
  if (picked.url) {
    coverBytes = await fetchCoverBytes(picked.url);
  }
  const rendered = await renderSocialJpeg(input, coverBytes);
  const path = objectPath(eventId, hash);
  const bucket = admin.storage().bucket(BUCKET);
  const file = bucket.file(path);
  const downloadToken = newDownloadToken();

  await file.save(rendered.buffer, {
    contentType: SOCIAL_MIME,
    resumable: false,
    metadata: {
      cacheControl: "public, max-age=86400",
      metadata: {
        eventId,
        contentHash: hash,
        source: rendered.source,
        firebaseStorageDownloadTokens: downloadToken,
      },
    },
  });

  let url = firebaseDownloadUrl(bucket.name, path, downloadToken);
  let madePublic = false;
  try {
    await file.makePublic();
    madePublic = true;
    url = publicUrlFor(bucket.name, path);
  } catch (e) {
    console.warn(
      JSON.stringify({
        action: "social_image_make_public_failed",
        eventId,
        message: e && e.message ? e.message : String(e),
        fallback: "firebase_download_token",
      }),
    );
  }

  // Prefer storage.googleapis.com when public; else token URL.
  if (madePublic) {
    url = publicUrlFor(bucket.name, path);
  }

  await ref.set(
    {
      socialShareImageUrl: url,
      socialShareImageHash: hash,
    },
    { merge: true },
  );

  // Delete older og_*.jpg under the same prefix (after new is ready)
  try {
    const prefix = `${STORAGE_PREFIX}/${eventId.replace(/[^A-Za-z0-9_-]/g, "_")}/`;
    const [files] = await bucket.getFiles({ prefix });
    await Promise.all(
      files
        .filter((f) => {
          const name = f.name.split("/").pop() || "";
          return (
            name.startsWith("og_") &&
            name.endsWith(".jpg") &&
            name !== `og_${hash}.jpg`
          );
        })
        .map((f) => f.delete().catch(() => {})),
    );
  } catch (e) {
    console.warn(
      JSON.stringify({
        action: "social_image_cleanup_failed",
        eventId,
        message: e && e.message ? e.message : String(e),
      }),
    );
  }

  console.log(
    JSON.stringify({
      action: "social_image_ensured",
      eventId,
      hash,
      bytes: rendered.bytes,
      url,
      source: rendered.source,
    }),
  );

  return { reused: false, generated: true, url, hash, bytes: rendered.bytes };
}

/**
 * Fire-and-forget seguro — nunca rejeita para o caller de create/update.
 */
function scheduleSocialImageJob(eventId, reason) {
  const id = (eventId || "").toString().trim();
  if (!id) return;
  setImmediate(() => {
    ensureEventSocialImage(id)
      .then((result) => {
        console.log(
          JSON.stringify({
            action: "social_image_job_done",
            eventId: id,
            reason: reason || "",
            result,
          }),
        );
      })
      .catch((err) => {
        console.error(
          JSON.stringify({
            action: "social_image_job_failed",
            eventId: id,
            reason: reason || "",
            message: err && err.message ? err.message : String(err),
          }),
        );
      });
  });
}

module.exports = {
  SOCIAL_TRIGGER_FIELDS,
  socialInputsChanged,
  buildSocialInput,
  ensureEventSocialImage,
  scheduleSocialImageJob,
  objectPath,
  BUCKET,
};
