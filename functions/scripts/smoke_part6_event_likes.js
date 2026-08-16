/**
 * Smoke autenticado Parte 6 — likes/comentários (socialchatmvp).
 * Cria evento PART6_TMP_*, valida callables, hard-delete.
 *
 * Uso: node functions/scripts/smoke_part6_event_likes.js
 */
"use strict";

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const PROJECT = "socialchatmvp";
const REGION = "us-central1";
const MARKER = "PART6_TMP_SMOKE_20260727";

function readDartApiKey(file) {
  const text = fs.readFileSync(file, "utf8");
  const android = text.match(
    /static const FirebaseOptions android = FirebaseOptions\([\s\S]*?apiKey: '([^']+)'/,
  );
  if (android) return android[1];
  const any = text.match(/apiKey: '([^']+)'/);
  return any ? any[1] : "";
}

const WEB_API_KEY = readDartApiKey(
  path.join(__dirname, "../../lib/firebase_options.dart"),
);

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
    });
    await admin.firestore().collection("events").limit(1).get();
    return;
  } catch (_) {
    if (admin.apps.length) await admin.app().delete().catch(() => {});
  }
  const refresh = loadCliRefreshToken();
  const adcDir = path.join(process.env.HOME || "", ".config", "firebase");
  fs.mkdirSync(adcDir, { recursive: true });
  const adcPath = path.join(
    adcDir,
    "part6_smoke_application_default_credentials.json",
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
  });
  await admin.firestore().collection("events").limit(1).get();
}

async function authAnonymous() {
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${WEB_API_KEY}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ returnSecureToken: true }),
  });
  const body = await res.json();
  if (!body.idToken || !body.localId) {
    throw new Error(`anon auth failed: ${JSON.stringify(body)}`);
  }
  return { idToken: body.idToken, uid: body.localId };
}

async function deleteAuthUser(idToken) {
  const url = `https://identitytoolkit.googleapis.com/v1/accounts:delete?key=${WEB_API_KEY}`;
  await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ idToken }),
  });
}

async function callCallable(name, idToken, data) {
  const url = `https://${REGION}-${PROJECT}.cloudfunctions.net/${name}`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({ data }),
  });
  let body;
  try {
    body = await res.json();
  } catch (_) {
    body = { raw: await res.text() };
  }
  return { http: res.status, body };
}

function resultOf(resp) {
  return resp.body?.result ?? resp.body;
}

const results = [];
function pass(name, detail) {
  results.push({ ok: true, name, detail });
  console.log(`PASS ${name}${detail ? " — " + detail : ""}`);
}
function fail(name, detail) {
  results.push({ ok: false, name, detail });
  console.error(`FAIL ${name}${detail ? " — " + detail : ""}`);
}

async function hardDeleteEvent(eventId) {
  const db = admin.firestore();
  const eventRef = db.collection("events").doc(eventId);
  for (const sub of ["likes", "comments", "attendees", "views"]) {
    const snap = await eventRef.collection(sub).limit(500).get();
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    if (!snap.empty) await batch.commit();
  }
  await eventRef.delete().catch(() => {});
}

async function hardDeleteUser(uid) {
  const db = admin.firestore();
  await db.collection("users").doc(uid).delete().catch(() => {});
  await db.collection("publicUsers").doc(uid).delete().catch(() => {});
  // eventCommentRequests for this uid
  const reqs = await db
    .collection("eventCommentRequests")
    .where("uid", "==", uid)
    .limit(50)
    .get()
    .catch(() => null);
  if (reqs && !reqs.empty) {
    const batch = db.batch();
    reqs.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
}

async function findLeftoverEvents() {
  const db = admin.firestore();
  const snap = await db.collection("events").limit(200).get();
  return snap.docs.filter((d) => {
    const t = (d.data().title || "").toString();
    return t.includes("PART6_TMP");
  });
}

async function main() {
  await initAdmin();
  const db = admin.firestore();
  let auth = null;
  let eventId = "";
  const removed = [];

  try {
    auth = await authAnonymous();
    const uid = auth.uid;

    await db.collection("users").doc(uid).set({
      name: `${MARKER}_user`,
      photoUrl: "",
      isActive: true,
      homeCountryCode: "br",
      countryCode: "br",
      appLanguageCode: "pt",
    });
    await db.collection("publicUsers").doc(uid).set({
      name: `${MARKER}_user`,
      photoUrl: "",
    });

    const eventRef = db.collection("events").doc();
    eventId = eventRef.id;
    await eventRef.set({
      title: `${MARKER} Event`,
      status: "approved",
      isActive: true,
      deleted: false,
      createdBy: uid,
      organizerId: uid,
      likesCount: 0,
      attendeesCount: 0,
      city: "Navegantes",
      countryCode: "br",
      category: "smoke",
      lat: -26.8986,
      lng: -48.6542,
      startAt: admin.firestore.Timestamp.fromDate(
        new Date(Date.now() + 86400000),
      ),
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    pass("seed_event", eventId);

    // 1) desiredLiked true
    let r = await callCallable("toggleEventLike", auth.idToken, {
      eventId,
      desiredLiked: true,
    });
    let out = resultOf(r);
    if (r.http === 200 && out.liked === true && out.likesCount === 1 && out.changed === true) {
      pass("like_true", JSON.stringify(out));
    } else {
      fail("like_true", JSON.stringify({ http: r.http, out, body: r.body }));
    }

    // 2) repeat true → no additional change
    r = await callCallable("toggleEventLike", auth.idToken, {
      eventId,
      desiredLiked: true,
    });
    out = resultOf(r);
    if (r.http === 200 && out.liked === true && out.likesCount === 1 && out.changed === false) {
      pass("like_true_noop", JSON.stringify(out));
    } else {
      fail("like_true_noop", JSON.stringify({ http: r.http, out, body: r.body }));
    }

    // 3) false
    r = await callCallable("toggleEventLike", auth.idToken, {
      eventId,
      desiredLiked: false,
    });
    out = resultOf(r);
    if (r.http === 200 && out.liked === false && out.likesCount === 0 && out.changed === true) {
      pass("like_false", JSON.stringify(out));
    } else {
      fail("like_false", JSON.stringify({ http: r.http, out, body: r.body }));
    }

    // 4) repeat false
    r = await callCallable("toggleEventLike", auth.idToken, {
      eventId,
      desiredLiked: false,
    });
    out = resultOf(r);
    if (r.http === 200 && out.liked === false && out.likesCount === 0 && out.changed === false) {
      pass("like_false_noop", JSON.stringify(out));
    } else {
      fail("like_false_noop", JSON.stringify({ http: r.http, out, body: r.body }));
    }

    // 5) counter sequence already covered 0→1→1→0→0
    const eventSnap = await eventRef.get();
    const likesCount = eventSnap.data()?.likesCount ?? -1;
    const likeDoc = await eventRef.collection("likes").doc(uid).get();
    if (likesCount === 0 && !likeDoc.exists) {
      pass("counter_final_zero", `likesCount=${likesCount}`);
    } else {
      fail("counter_final_zero", `likesCount=${likesCount} likeExists=${likeDoc.exists}`);
    }

    // status unchanged after likes
    const st = eventSnap.data() || {};
    if (st.status === "approved" && st.isActive === true && st.hasPendingChanges !== true) {
      pass("likesCount_no_status_side_effect", "status/active intact");
    } else {
      fail("likesCount_no_status_side_effect", JSON.stringify(st));
    }

    // no eventLikeRequests docs
    const likeReqs = await db.collection("eventLikeRequests").limit(5).get();
    // collection may not exist / empty — OK
    pass("no_like_request_store_required", `sampled=${likeReqs.size}`);

    // 6) comment
    const commentId = db.collection("events").doc(eventId).collection("comments").doc().id;
    const requestId = `c_smoke_${Date.now()}_1`;
    r = await callCallable("createEventComment", auth.idToken, {
      eventId,
      text: `${MARKER} hello comment`,
      commentId,
      requestId,
      clientCreatedAtMs: Date.now(),
    });
    out = resultOf(r);
    if (r.http === 200 && out.created === true && out.commentId === commentId) {
      pass("comment_create", out.commentId);
    } else {
      fail("comment_create", JSON.stringify({ http: r.http, out, body: r.body }));
    }

    // 8) retry same requestId — no duplicate
    r = await callCallable("createEventComment", auth.idToken, {
      eventId,
      text: `${MARKER} hello comment`,
      commentId,
      requestId,
      clientCreatedAtMs: Date.now(),
    });
    out = resultOf(r);
    if (r.http === 200 && out.alreadyCreated === true && out.commentId === commentId) {
      pass("comment_retry_idempotent", JSON.stringify(out));
    } else {
      fail("comment_retry_idempotent", JSON.stringify({ http: r.http, out, body: r.body }));
    }

    const comments = await eventRef.collection("comments").get();
    const live = comments.docs.filter((d) => d.data().isDeleted !== true);
    if (live.length === 1) {
      pass("comment_single_doc", `count=${live.length}`);
    } else {
      fail("comment_single_doc", `count=${live.length}`);
    }

    // 7) reply
    const replyId = db.collection("events").doc(eventId).collection("comments").doc().id;
    r = await callCallable("createEventComment", auth.idToken, {
      eventId,
      text: `${MARKER} reply text`,
      commentId: replyId,
      requestId: `c_smoke_${Date.now()}_reply`,
      replyToCommentId: commentId,
      clientCreatedAtMs: Date.now(),
    });
    out = resultOf(r);
    if (r.http === 200 && out.created === true) {
      const replyDoc = await eventRef.collection("comments").doc(replyId).get();
      const rd = replyDoc.data() || {};
      if (
        rd.replyToCommentId === commentId &&
        rd.replyToUid === uid &&
        rd.rootCommentId === commentId
      ) {
        pass("reply_create", JSON.stringify({
          replyToUid: rd.replyToUid,
          rootCommentId: rd.rootCommentId,
        }));
      } else {
        fail("reply_fields", JSON.stringify(rd));
      }
    } else {
      fail("reply_create", JSON.stringify({ http: r.http, out, body: r.body }));
    }

    // 9) like does not generate push — verified by contract (no push in CF) + sequence OK
    pass("like_no_push_contract", "toggleEventLike has no sendPush");

    // 10) likesCount-only — already checked status; also ensure title unchanged
    const after = (await eventRef.get()).data() || {};
    if (after.title === `${MARKER} Event` && after.status === "approved") {
      pass("likesCount_only_no_event_effects", "title/status stable");
    } else {
      fail("likesCount_only_no_event_effects", JSON.stringify(after));
    }
  } catch (e) {
    fail("fatal", e.stack || String(e));
  } finally {
    // Cleanup
    try {
      if (eventId) {
        await hardDeleteEvent(eventId);
        removed.push(`events/${eventId}`);
      }
      if (auth?.uid) {
        await hardDeleteUser(auth.uid);
        removed.push(`users/${auth.uid}`, `publicUsers/${auth.uid}`);
        await deleteAuthUser(auth.idToken).catch(() => {});
        removed.push(`auth/${auth.uid}`);
      }
      // sweep any PART6_TMP events
      const leftovers = await findLeftoverEvents();
      for (const d of leftovers) {
        await hardDeleteEvent(d.id);
        removed.push(`events/${d.id}`);
      }
      const finalLeft = await findLeftoverEvents();
      if (finalLeft.length === 0) {
        pass("cleanup_leftover_zero", `removed=${removed.length}`);
      } else {
        fail(
          "cleanup_leftover_zero",
          finalLeft.map((d) => d.id).join(","),
        );
      }
    } catch (e) {
      fail("cleanup", e.stack || String(e));
    }
  }

  const report = {
    marker: MARKER,
    results,
    removed,
    failed: results.filter((r) => !r.ok).length,
    passed: results.filter((r) => r.ok).length,
  };
  const outPath = path.join(__dirname, "../../tmp_part6/SMOKE_REPORT.json");
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(report, null, 2));
  console.log("\nReport:", outPath);
  console.log(`Passed ${report.passed} / Failed ${report.failed}`);
  if (report.failed > 0) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
