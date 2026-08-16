/**
 * Limpeza PART5_* leftovers via Firestore Admin (Google OAuth), NÃO via
 * access_token cru do Firebase CLI (retorna ACCESS_TOKEN_TYPE_UNSUPPORTED).
 *
 * Credencial (nesta ordem):
 *   1. GOOGLE_APPLICATION_CREDENTIALS / ADC → firebase-admin
 *   2. refresh_token do Firebase CLI → OAuth Google (cloud-platform)
 *
 * Uso:
 *   node functions/scripts/cleanup_part5_tmp.js --dry-run
 *   node functions/scripts/cleanup_part5_tmp.js --execute
 */
"use strict";

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const PROJECT = "socialchatmvp";
const MARKERS = [
  "PART5_TMP_PENDING_DIAG_20260726",
  "PART5_TMP_PENDING_DIAG2_20260726",
  "PART5_TMP_GROUPS_20260726",
  "PART5_TMP_MEMBER_20260726",
  "PART5_FIX_20260726",
  "PART5_FIX_UI_20260726",
  "PART5_FIX_UI_CITY_20260726",
  "PART5_FIX_UI_REGION_20260726",
  "PART5_FIX_UI_COUNTRY_20260726",
  "SMOKE_TMP_GROUPS_20260726",
];

// IDs conhecidos de sessões de validação (somente temporários PART5/SMOKE).
const KNOWN_GROUPS = [
  "eWbCHlxvSySx5DyNMFAg",
  "3C8q0LJ4DKp74yq2NUpl",
  "m4AHSkTFFNHkHS0FWNXi",
  "XGZKf3QO206zUXwGlgEZ",
  "GvWZgEjGNdGyJiZDoMHv",
  "oWRSfkvku6FOpji1lRC9",
  "2hQIWToiLSFQjcNHx2yh",
  "5HXZN0hyAOH17GlC5SNI",
  "30ROwCF6qbE9ExNLbD2N",
  "RTAmCkSQUxZB5cNqWjaz",
  "utkcNR6uWLSA6lSCO3Y3",
  "CAeIBy9IbqVkfPHkXNN8",
  "1RoVdsdVMKlBe5FEFnYq",
  "S7O6rrPQiavExNzswMa6",
  "yg309NIssHGTlVrNAasm",
  "Pya8MVzmjzwv0B5p21Fp",
  "NtVq1fN0e2D1rGWiQ4RW",
  "kIEpbHLk1s73JASDePpL",
  "JTdGCIRbxxXLAUrwk2oc",
  "msvpaMMe3JHWN6wqdTcY",
  "fDj1v7laDoiCU07BE3LP",
  "QCxn6ymGNIJs3gowe3v1",
  "X3vVNJKvVLvXxfhPe7qT",
  "IA3sqPfnZG24oLJu3gvr",
  "Zmujq1DTCEB57rTzED5V",
  "VbptBurgVPUhhFVaU767",
  "J7BdNMWySaYpSJf1OLpM",
  "MkUtDANdz5X3c9ERDLPn",
  "dBRao3cAD9NkpjGhMEUh",
  "cq5Rfvjz7ZlC7WGCx2Ua",
];

const GROUP_SUBS = [
  "messages",
  "pendingRequests",
  "bannedUsers",
  "reads",
  "moderators",
  "members",
];

const DRY = process.argv.includes("--dry-run");
const EXECUTE = process.argv.includes("--execute");

// Client público atual do Firebase CLI (firebase-tools/lib/api.js).
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
    throw new Error(
      "No Firebase CLI refresh_token. Run: firebase login --reauth",
    );
  }
  return tokens.refresh_token;
}

async function refreshGoogleAccessToken(refreshToken) {
  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: refreshToken,
    client_id: FIREBASE_CLI_CLIENT_ID,
    client_secret: FIREBASE_CLI_CLIENT_SECRET,
  });
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });
  const json = await res.json();
  if (!json.access_token) {
    throw new Error(
      "OAuth refresh failed: " + JSON.stringify(json).slice(0, 400),
    );
  }
  return json.access_token;
}

async function initAdmin() {
  if (admin.apps.length) return { mode: "existing" };

  // 1) ADC / service account já existente
  try {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: PROJECT,
    });
    await admin.firestore().collection("groups").limit(1).get();
    return { mode: "adc" };
  } catch (_) {
    if (admin.apps.length) {
      await admin.app().delete().catch(() => {});
    }
  }

  // 2) Escrever ADC a partir do refresh_token do Firebase CLI
  //    (mesmo formato de firebase-tools/lib/defaultCredentials.js).
  //    O access_token cru do CLI NÃO funciona na API Admin do Firestore.
  const refresh = loadCliRefreshToken();
  // Probe OAuth refresh first so we fail early with a clear message.
  await refreshGoogleAccessToken(refresh);

  const adcDir = path.join(process.env.HOME || "", ".config", "firebase");
  fs.mkdirSync(adcDir, { recursive: true });
  const adcPath = path.join(
    adcDir,
    "part5_cleanup_application_default_credentials.json",
  );
  fs.writeFileSync(
    adcPath,
    JSON.stringify(
      {
        client_id: FIREBASE_CLI_CLIENT_ID,
        client_secret: FIREBASE_CLI_CLIENT_SECRET,
        refresh_token: refresh,
        type: "authorized_user",
      },
      null,
      2,
    ),
  );
  process.env.GOOGLE_APPLICATION_CREDENTIALS = adcPath;

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT,
  });
  await admin.firestore().collection("groups").limit(1).get();
  return { mode: "cli-refresh-adc", adcPath };
}

function isTempName(name) {
  const n = (name || "").toString();
  return (
    n.includes("PART5_") ||
    n.includes("SMOKE_TMP") ||
    n.startsWith("PART5")
  );
}

function isTempUser(data) {
  const marker = (data.smokeMarker || "").toString();
  const name = (data.name || "").toString();
  return (
    MARKERS.some((m) => marker === m || marker.includes("PART5")) ||
    name.includes("PART5_") ||
    name.includes("SMOKE_TMP")
  );
}

async function collectByNamePrefix(db, prefix) {
  const snap = await db
    .collection("groups")
    .orderBy("name")
    .startAt(prefix)
    .endAt(prefix + "\uf8ff")
    .limit(200)
    .get();
  return snap.docs.filter((d) => isTempName(d.get("name")));
}

async function collectUsersByMarker(db, marker) {
  const snap = await db
    .collection("users")
    .where("smokeMarker", "==", marker)
    .limit(200)
    .get();
  return snap.docs;
}

async function deleteSubcollections(db, groupId, removed) {
  for (const sub of GROUP_SUBS) {
    const snap = await db
      .collection("groups")
      .doc(groupId)
      .collection(sub)
      .limit(500)
      .get();
    for (const doc of snap.docs) {
      const p = `groups/${groupId}/${sub}/${doc.id}`;
      console.log(DRY ? "DRY sub" : "DEL sub", p);
      removed.push(p);
      if (EXECUTE) await doc.ref.delete();
    }
  }
}

async function deleteInviteCodes(db, inviteCode, removed) {
  const code = (inviteCode || "").toString().trim().toUpperCase();
  if (!code) return;
  const ref = db.collection("groupInviteCodes").doc(code);
  const snap = await ref.get();
  if (!snap.exists) return;
  const p = `groupInviteCodes/${code}`;
  console.log(DRY ? "DRY invite" : "DEL invite", p);
  removed.push(p);
  if (EXECUTE) await ref.delete();
}

async function main() {
  if (!DRY && !EXECUTE) {
    console.log("Use --dry-run or --execute");
    process.exit(1);
  }

  const auth = await initAdmin();
  console.log("auth_mode", auth.mode);
  const db = admin.firestore();

  const groupIds = new Set(KNOWN_GROUPS);
  const groupMeta = new Map(); // id -> {name, inviteCode}
  const userIds = new Set();
  const removed = [];

  // Load known IDs from visual_seed_state.json if present
  try {
    const statePath = path.join(__dirname, "../../tmp_part5/visual_seed_state.json");
    const state = JSON.parse(fs.readFileSync(statePath, "utf8"));
    for (const key of ["city", "region", "country", "approve", "reject"]) {
      if (state[key]?.groupId) groupIds.add(state[key].groupId);
    }
  } catch (_) {}

  for (const marker of MARKERS) {
    const docs = await collectByNamePrefix(db, marker);
    for (const d of docs) {
      groupIds.add(d.id);
      groupMeta.set(d.id, {
        name: d.get("name") || "",
        inviteCode: d.get("inviteCode") || "",
      });
    }
    const users = await collectUsersByMarker(db, marker);
    for (const u of users) {
      if (isTempUser(u.data() || {})) userIds.add(u.id);
    }
  }

  // Also scan name prefixes PART5_ / SMOKE_
  for (const prefix of ["PART5_", "SMOKE_TMP"]) {
    const docs = await collectByNamePrefix(db, prefix);
    for (const d of docs) {
      groupIds.add(d.id);
      groupMeta.set(d.id, {
        name: d.get("name") || "",
        inviteCode: d.get("inviteCode") || "",
      });
    }
  }

  // Hydrate meta for known IDs
  for (const gid of [...groupIds]) {
    if (groupMeta.has(gid)) continue;
    const snap = await db.collection("groups").doc(gid).get();
    if (!snap.exists) {
      // still try delete invite / confirm gone
      groupMeta.set(gid, { name: "(missing)", inviteCode: "" });
      continue;
    }
    const name = snap.get("name") || "";
    if (!isTempName(name) && name !== "(missing)") {
      // Safety: never delete non-temp known ID if name doesn't match PART5
      console.warn("SKIP non-temp group", gid, name);
      groupIds.delete(gid);
      continue;
    }
    groupMeta.set(gid, {
      name,
      inviteCode: snap.get("inviteCode") || "",
    });
  }

  console.log("=== CANDIDATES (temp only) ===");
  for (const gid of [...groupIds]) {
    const m = groupMeta.get(gid) || {};
    console.log("group", gid, m.name, m.inviteCode || "");
  }
  console.log("users", [...userIds]);

  for (const gid of [...groupIds]) {
    const meta = groupMeta.get(gid) || {};
    await deleteSubcollections(db, gid, removed);
    await deleteInviteCodes(db, meta.inviteCode, removed);
    const gpath = `groups/${gid}`;
    console.log(DRY ? "DRY group" : "DEL group", gpath, meta.name || "");
    removed.push(gpath);
    if (EXECUTE) {
      await db.collection("groups").doc(gid).delete().catch(() => {});
    }
  }

  for (const uid of userIds) {
    const upath = `users/${uid}`;
    console.log(DRY ? "DRY user" : "DEL user", upath);
    removed.push(upath);
    if (EXECUTE) {
      await db.collection("users").doc(uid).delete().catch(() => {});
    }
  }

  // Verify leftover zero for PART5_ name prefix
  const leftoverGroups = await collectByNamePrefix(db, "PART5_");
  const leftoverSmoke = await collectByNamePrefix(db, "SMOKE_TMP");
  const leftoverUsers = [];
  for (const marker of MARKERS) {
    leftoverUsers.push(...(await collectUsersByMarker(db, marker)));
  }

  console.log("=== VERIFY ===");
  console.log(
    "leftover_groups",
    leftoverGroups.map((d) => `${d.id}:${d.get("name")}`),
  );
  console.log(
    "leftover_smoke",
    leftoverSmoke.map((d) => `${d.id}:${d.get("name")}`),
  );
  console.log(
    "leftover_users",
    leftoverUsers.map((d) => d.id),
  );
  console.log("removed_count", removed.length);
  if (EXECUTE) {
    fs.writeFileSync(
      path.join(__dirname, "../../tmp_part5/cleanup_removed_paths.json"),
      JSON.stringify({ removed, at: new Date().toISOString() }, null, 2),
    );
  }
  console.log(DRY ? "dry-run done" : `deleted done removed=${removed.length}`);

  if (
    EXECUTE &&
    (leftoverGroups.length || leftoverSmoke.length || leftoverUsers.length)
  ) {
    process.exit(3);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
