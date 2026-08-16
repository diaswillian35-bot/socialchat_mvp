/**
 * Publica a imagem social aprovada do Festival Remdy Navegantes.
 * Escreve SOMENTE socialShareImageUrl + socialShareImageHash.
 *
 * Uso: node functions/scripts/publish_navegantes_social_image.js
 */
"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const admin = require("firebase-admin");

const PROJECT = "socialchatmvp";
const EVENT_ID = "3H5UwiBpNsAwHc3xdGZR";
const EXPECTED_TITLE = "Festival Remdy Navegantes";
const HASH = "2e16a80291335cc02330";
const OBJECT_PATH = `public_social/${EVENT_ID}/og_${HASH}.jpg`;
const LOCAL_JPEG =
  "/Users/macbookairm1/Documents/remdy-events-web/tmp_public_landing_20260731/social/festival_navegantes_og_1200x630.jpg";
const BUCKET = "socialchatmvp.firebasestorage.app";
const REPORT =
  "/Users/macbookairm1/Documents/remdy-events-web/tmp_public_landing_20260731/reports/SOCIAL_IMAGE_PUBLISH.json";

const FIREBASE_CLI_CLIENT_ID =
  "563584335869-fgrhgmd47bqnekij5i8b5pr03ho849e6.apps.googleusercontent.com";
const FIREBASE_CLI_CLIENT_SECRET = "j9iVZfS8kkCEFUPaAeJV0sAi";

function loadCliRefreshToken() {
  const p = path.join(
    process.env.HOME || "",
    ".config/configstore/firebase-tools.json",
  );
  const tokens = JSON.parse(fs.readFileSync(p, "utf8")).tokens || {};
  if (!tokens.refresh_token) {
    throw new Error("No Firebase CLI refresh_token. Run: firebase login --reauth");
  }
  return tokens.refresh_token;
}

async function initAdmin() {
  if (admin.apps.length) return;
  try {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: PROJECT,
      storageBucket: BUCKET,
    });
    await admin.firestore().collection("events").doc(EVENT_ID).get();
    return;
  } catch (_) {
    if (admin.apps.length) await admin.app().delete().catch(() => {});
  }
  const refresh = loadCliRefreshToken();
  const adcDir = path.join(process.env.HOME || "", ".config", "firebase");
  fs.mkdirSync(adcDir, { recursive: true });
  const adcPath = path.join(
    adcDir,
    "social_image_publish_application_default_credentials.json",
  );
  fs.writeFileSync(
    adcPath,
    JSON.stringify({
      client_id: FIREBASE_CLI_CLIENT_ID,
      client_secret: FIREBASE_CLI_CLIENT_SECRET,
      refresh_token: refresh,
      type: "authorized_user",
    }),
  );
  process.env.GOOGLE_APPLICATION_CREDENTIALS = adcPath;
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT,
    storageBucket: BUCKET,
  });
  await admin.firestore().collection("events").doc(EVENT_ID).get();
}

function firebaseDownloadUrl(bucketName, objectPath, token) {
  const encoded = encodeURIComponent(objectPath);
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encoded}?alt=media&token=${token}`;
}

async function main() {
  const buf = fs.readFileSync(LOCAL_JPEG);
  if (buf.length < 50_000 || buf.length > 200_000) {
    throw new Error(`Unexpected JPEG size: ${buf.length}`);
  }
  // JPEG SOI
  if (buf[0] !== 0xff || buf[1] !== 0xd8) {
    throw new Error("Not a JPEG");
  }

  await initAdmin();
  const ref = admin.firestore().collection("events").doc(EVENT_ID);
  const beforeSnap = await ref.get();
  if (!beforeSnap.exists) throw new Error("Event not found");
  const before = beforeSnap.data() || {};
  if ((before.title || "").toString().trim() !== EXPECTED_TITLE) {
    throw new Error(
      `Title mismatch: got "${before.title}" expected "${EXPECTED_TITLE}"`,
    );
  }

  const beforeKeys = Object.keys(before).sort();
  const beforeSocial = {
    socialShareImageUrl: before.socialShareImageUrl || null,
    socialShareImageHash: before.socialShareImageHash || null,
  };

  const token = crypto.randomUUID();
  const bucket = admin.storage().bucket(BUCKET);
  const file = bucket.file(OBJECT_PATH);
  await file.save(buf, {
    contentType: "image/jpeg",
    resumable: false,
    metadata: {
      cacheControl: "public, max-age=86400",
      metadata: {
        eventId: EVENT_ID,
        contentHash: HASH,
        source: "approved_manual_publish",
        firebaseStorageDownloadTokens: token,
      },
    },
  });

  let url = firebaseDownloadUrl(BUCKET, OBJECT_PATH, token);
  let acl = "token";
  try {
    await file.makePublic();
    url = `https://storage.googleapis.com/${BUCKET}/${OBJECT_PATH}`;
    acl = "public";
  } catch (e) {
    console.warn("makePublic failed, keeping token URL:", e.message || e);
  }

  await ref.set(
    {
      socialShareImageUrl: url,
      socialShareImageHash: HASH,
    },
    { merge: true },
  );

  const afterSnap = await ref.get();
  const after = afterSnap.data() || {};
  const afterKeys = Object.keys(after).sort();
  const extraKeys = afterKeys.filter((k) => !beforeKeys.includes(k));
  const allowedExtra = new Set(["socialShareImageUrl", "socialShareImageHash"]);
  const unexpectedExtra = extraKeys.filter((k) => !allowedExtra.has(k));
  if (unexpectedExtra.length) {
    throw new Error(`Unexpected new fields: ${unexpectedExtra.join(",")}`);
  }

  // Verify only social fields changed among all top-level keys present before
  for (const k of beforeKeys) {
    if (k === "socialShareImageUrl" || k === "socialShareImageHash") continue;
    const a = JSON.stringify(before[k] ?? null);
    const b = JSON.stringify(after[k] ?? null);
    if (a !== b) {
      throw new Error(`Field ${k} changed unexpectedly`);
    }
  }

  const http = await fetch(url, { method: "GET", redirect: "follow" });
  const ct = http.headers.get("content-type") || "";
  const cc = http.headers.get("cache-control") || "";
  const body = Buffer.from(await http.arrayBuffer());

  const report = {
    eventId: EVENT_ID,
    title: after.title,
    hash: HASH,
    objectPath: OBJECT_PATH,
    url,
    acl,
    beforeSocial,
    afterSocial: {
      socialShareImageUrl: after.socialShareImageUrl,
      socialShareImageHash: after.socialShareImageHash,
    },
    http: {
      status: http.status,
      contentType: ct,
      cacheControl: cc,
      bytes: body.length,
    },
    localBytes: buf.length,
    unexpectedExtra,
    ok:
      http.status === 200 &&
      ct.toLowerCase().includes("image/jpeg") &&
      body.length === buf.length &&
      after.socialShareImageHash === HASH &&
      after.socialShareImageUrl === url,
  };

  fs.mkdirSync(path.dirname(REPORT), { recursive: true });
  fs.writeFileSync(REPORT, JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
  if (!report.ok) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
