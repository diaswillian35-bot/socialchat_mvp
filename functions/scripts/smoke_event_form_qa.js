/**
 * Smoke controlado — createEvent / updateEvent (socialchatmvp).
 * Marker: EVENT_FORM_QA_*
 *
 * Uso: node functions/scripts/smoke_event_form_qa.js
 */
"use strict";

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const PROJECT = "socialchatmvp";
const REGION = "us-central1";
const MARKER = `EVENT_FORM_QA_${Date.now()}`;
const REPORT_DIR =
  "/Users/macbookairm1/Documents/remdy-events-web/tmp_public_landing_20260731/reports";

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
    "event_form_qa_application_default_credentials.json",
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
  const headers = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const res = await fetch(url, {
    method: "POST",
    headers,
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

function errorCode(resp) {
  return (
    resp.body?.error?.status ||
    resp.body?.error?.message ||
    resp.body?.error ||
    ""
  );
}

const results = [];
function pass(name, detail) {
  results.push({ ok: true, name, detail: detail || "" });
  console.log(`PASS ${name}${detail ? " — " + detail : ""}`);
}
function fail(name, detail) {
  results.push({ ok: false, name, detail: detail || "" });
  console.error(`FAIL ${name}${detail ? " — " + detail : ""}`);
}

async function hardDeleteEvent(eventId) {
  if (!eventId) return;
  const db = admin.firestore();
  const eventRef = db.collection("events").doc(eventId);
  for (const sub of ["likes", "comments", "attendees", "views"]) {
    const snap = await eventRef.collection(sub).limit(500).get();
    if (snap.empty) continue;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
  await eventRef.delete().catch(() => {});
}

async function hardDeleteUser(uid) {
  if (!uid) return;
  const db = admin.firestore();
  await db.collection("users").doc(uid).delete().catch(() => {});
  await db.collection("publicUsers").doc(uid).delete().catch(() => {});
}

async function deleteCreateRequests(uid) {
  if (!uid) return;
  const db = admin.firestore();
  const snap = await db
    .collection("eventCreateRequests")
    .where("uid", "==", uid)
    .limit(50)
    .get()
    .catch(() => null);
  if (!snap || snap.empty) return;
  const batch = db.batch();
  snap.docs.forEach((d) => batch.delete(d.ref));
  await batch.commit();
}

function futureMs(days, hourUtc = 20) {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + days);
  d.setUTCHours(hourUtc, 0, 0, 0);
  return d.getTime();
}

function minimalPayload(titleSuffix) {
  const startAtMs = futureMs(14, 20);
  const endAtMs = futureMs(14, 23);
  return {
    title: `${MARKER} ${titleSuffix}`,
    description: `${MARKER} descrição mínima do evento de QA.`,
    category: "Show",
    startAtMs,
    endAtMs,
    eventTimeZone: "America/Sao_Paulo",
    city: "Navegantes",
    placeName: "Arena QA Remdy",
    countryCode: "br",
  };
}

function fullPayload(titleSuffix) {
  const startAtMs = futureMs(21, 19);
  const endAtMs = futureMs(21, 23);
  return {
    ...minimalPayload(titleSuffix),
    startAtMs,
    endAtMs,
    shortDescription: "Resumo curto do evento QA.",
    subcategories: ["Rock", "Ao vivo"],
    primaryLanguage: "pt",
    cityKey: "navegantes_sc_br",
    stateName: "Santa Catarina",
    address: "Av. QA, 100",
    placeDisplay: "Arena QA Remdy — Navegantes",
    lat: -26.8986,
    lng: -48.6542,
    regionKey: "sc_br",
    scope: "city",
    placeId: "qa_place_event_form",
    sponsorInterested: false,
    coverUrl: "https://storage.googleapis.com/socialchatmvp.appspot.com/qa/cover.jpg",
    photoUrls: [
      "https://storage.googleapis.com/socialchatmvp.appspot.com/qa/g1.jpg",
      "https://storage.googleapis.com/socialchatmvp.appspot.com/qa/g2.jpg",
    ],
    logoUrl: "https://storage.googleapis.com/socialchatmvp.appspot.com/qa/logo.png",
    ticketType: "paid",
    isFree: false,
    price: "80",
    priceCurrency: "BRL",
    ticketUrl: "https://example.com/tickets/event-form-qa",
    ticketInfo: "Meia entrada disponível.",
    expectedAudience: 1200,
    schedule: [
      {
        id: "s1",
        day: "Dia 1",
        startTime: "19:00",
        endTime: "20:00",
        title: "Abertura",
        description: "Portões abertos",
        tag: "info",
        order: 0,
      },
      {
        id: "s2",
        day: "Dia 1",
        startTime: "20:00",
        endTime: "23:00",
        title: "Show principal",
        description: "",
        tag: "main",
        order: 1,
      },
    ],
    attractions: [
      {
        id: "a1",
        name: "Banda QA",
        role: "Headliner",
        bio: "Atração principal do smoke.",
        photoUrl: "https://storage.googleapis.com/socialchatmvp.appspot.com/qa/a1.jpg",
        order: 0,
      },
    ],
    accessibility: "Acesso com rampa",
    parking: "Estacionamento pago no local",
    foodInfo: "Food trucks",
    ageRating: "18+",
    entryPolicy: "Documento com foto",
    publicContact: "qa@remdy.app",
    publicContactConsent: true,
    websiteUrl: "https://example.com/event-form-qa",
    publicNotes: "Chegue com 30 minutos de antecedência.",
  };
}

async function assertEventFields(eventId, checks) {
  const snap = await admin.firestore().collection("events").doc(eventId).get();
  if (!snap.exists) {
    fail("event_exists", eventId);
    return null;
  }
  const data = snap.data() || {};
  for (const [k, expected] of Object.entries(checks)) {
    const actual = data[k];
    const ok =
      typeof expected === "function"
        ? expected(actual, data)
        : JSON.stringify(actual) === JSON.stringify(expected);
    if (!ok) {
      fail(`field_${k}`, `expected=${JSON.stringify(expected)} actual=${JSON.stringify(actual)}`);
    }
  }
  return data;
}

async function main() {
  fs.mkdirSync(REPORT_DIR, { recursive: true });
  await initAdmin();
  const db = admin.firestore();

  let owner = null;
  let other = null;
  const eventIds = [];
  const cleanupNotes = [];

  try {
    // 1) Unauthenticated
    {
      const r = await callCallable("createEvent", null, {
        requestId: `${MARKER}_unauth`,
        ...minimalPayload("unauth"),
      });
      const code = String(errorCode(r));
      if (
        r.http === 401 ||
        /UNAUTHENTICATED/i.test(code) ||
        /UNAUTHENTICATED/i.test(JSON.stringify(r.body))
      ) {
        pass("unauth_createEvent", code || `http=${r.http}`);
      } else {
        fail("unauth_createEvent", JSON.stringify(r.body));
      }
    }
    {
      const r = await callCallable("updateEvent", null, {
        eventId: "does_not_matter",
        title: "x",
      });
      const code = String(errorCode(r));
      if (
        r.http === 401 ||
        /UNAUTHENTICATED/i.test(code) ||
        /UNAUTHENTICATED/i.test(JSON.stringify(r.body))
      ) {
        pass("unauth_updateEvent", code || `http=${r.http}`);
      } else {
        fail("unauth_updateEvent", JSON.stringify(r.body));
      }
    }

    owner = await authAnonymous();
    other = await authAnonymous();

    await db.collection("users").doc(owner.uid).set({
      name: `${MARKER}_owner`,
      photoUrl: "",
      isActive: true,
      homeCountryCode: "br",
      countryCode: "br",
      appLanguageCode: "pt",
    });
    await db.collection("publicUsers").doc(owner.uid).set({
      name: `${MARKER}_owner`,
      photoUrl: "",
    });
    await db.collection("users").doc(other.uid).set({
      name: `${MARKER}_other`,
      photoUrl: "",
      isActive: true,
      homeCountryCode: "br",
      countryCode: "br",
    });

    // 2) Minimal create
    const minReq = `${MARKER}_min`.replace(/[^A-Za-z0-9_-]/g, "_");
    let r = await callCallable("createEvent", owner.idToken, {
      requestId: minReq,
      ...minimalPayload("MIN"),
    });
    let out = resultOf(r);
    if (r.http === 200 && out.success && out.eventId) {
      pass("create_minimal", out.eventId);
      eventIds.push(out.eventId);
    } else {
      fail("create_minimal", JSON.stringify({ http: r.http, out, body: r.body }));
    }
    const minId = out.eventId;
    if (minId) {
      const data = await assertEventFields(minId, {
        title: `${MARKER} MIN`,
        eventTimeZone: "America/Sao_Paulo",
        createdBy: owner.uid,
        status: "pending",
        isActive: false,
        deleted: false,
        archived: false,
        attendeesCount: 0,
        sponsored: false,
        featured: false,
      });
      if (data) {
        if (data.status === "pending" && data.createdBy === owner.uid) {
          pass("create_minimal_server_fields", "owner/status/counters ok");
        }
        if (data.startAt && data.endAt) {
          pass(
            "create_minimal_times",
            `tz=${data.eventTimeZone} start=${data.startAt.toDate?.() || data.startAt}`,
          );
        } else {
          fail("create_minimal_times", "missing startAt/endAt");
        }
      }
    }

    // 3) Full create
    const fullReq = `${MARKER}_full`.replace(/[^A-Za-z0-9_-]/g, "_");
    const fullBody = fullPayload("FULL");
    r = await callCallable("createEvent", owner.idToken, {
      requestId: fullReq,
      ...fullBody,
    });
    out = resultOf(r);
    let fullId = "";
    if (r.http === 200 && out.success && out.eventId) {
      pass("create_full", out.eventId);
      fullId = out.eventId;
      eventIds.push(fullId);
    } else {
      fail("create_full", JSON.stringify({ http: r.http, out, body: r.body }));
    }

    if (fullId) {
      const data = await assertEventFields(fullId, {
        ticketType: "paid",
        expectedAudience: 1200,
        logoUrl: fullBody.logoUrl,
        websiteUrl: fullBody.websiteUrl,
        publicContact: "qa@remdy.app",
      });
      if (data) {
        const schedOk =
          Array.isArray(data.schedule) &&
          data.schedule.length === 2 &&
          data.schedule[0].title === "Abertura";
        const attrOk =
          Array.isArray(data.attractions) &&
          data.attractions.length === 1 &&
          data.attractions[0].name === "Banda QA";
        const galleryOk =
          Array.isArray(data.photoUrls) && data.photoUrls.length === 2;
        if (schedOk) pass("create_full_schedule", `${data.schedule.length} items`);
        else fail("create_full_schedule", JSON.stringify(data.schedule));
        if (attrOk) pass("create_full_attractions", data.attractions[0].name);
        else fail("create_full_attractions", JSON.stringify(data.attractions));
        if (galleryOk) pass("create_full_gallery", `${data.photoUrls.length}`);
        else fail("create_full_gallery", JSON.stringify(data.photoUrls));
        if (data.logoUrl) pass("create_full_logo", data.logoUrl);
        else fail("create_full_logo", "missing");
        if (data.accessibility === "Acesso com rampa" && data.parking) {
          pass("create_full_extras", "accessibility/parking/food/notes");
        } else {
          fail("create_full_extras", JSON.stringify({
            accessibility: data.accessibility,
            parking: data.parking,
          }));
        }
        if (data.isFree === false && String(data.price) === "80") {
          pass("create_full_ticket", `paid ${data.price} ${data.priceCurrency}`);
        } else {
          fail("create_full_ticket", JSON.stringify({
            isFree: data.isFree,
            price: data.price,
            ticketType: data.ticketType,
          }));
        }
      }
    }

    // 4) Partial update without data loss
    if (fullId) {
      const before = (await db.collection("events").doc(fullId).get()).data() || {};
      r = await callCallable("updateEvent", owner.idToken, {
        eventId: fullId,
        title: `${MARKER} FULL edited`,
      });
      out = resultOf(r);
      if (r.http === 200 && out.success) {
        pass("update_partial", JSON.stringify(out.changedFields || out));
      } else {
        fail("update_partial", JSON.stringify({ http: r.http, out, body: r.body }));
      }
      const after = (await db.collection("events").doc(fullId).get()).data() || {};
      const preserved =
        after.description === before.description &&
        after.ticketType === before.ticketType &&
        after.expectedAudience === before.expectedAudience &&
        JSON.stringify(after.schedule) === JSON.stringify(before.schedule) &&
        JSON.stringify(after.attractions) === JSON.stringify(before.attractions) &&
        JSON.stringify(after.photoUrls) === JSON.stringify(before.photoUrls) &&
        after.logoUrl === before.logoUrl &&
        after.createdBy === before.createdBy &&
        after.attendeesCount === before.attendeesCount &&
        after.deleted === before.deleted &&
        after.archived === before.archived;
      if (after.title === `${MARKER} FULL edited` && preserved) {
        pass("update_partial_no_wipe", "title changed; rest preserved");
      } else {
        fail(
          "update_partial_no_wipe",
          JSON.stringify({
            title: after.title,
            preserved,
            ticketType: after.ticketType,
            scheduleLen: (after.schedule || []).length,
          }),
        );
      }
    }

    // 5) Tampered payload
    if (fullId) {
      r = await callCallable("updateEvent", owner.idToken, {
        eventId: fullId,
        title: `${MARKER} tamper`,
        status: "approved",
        createdBy: "hacker",
        attendeesCount: 999,
        deleted: true,
        archived: true,
        sponsored: true,
        likesCount: 50,
      });
      const code = String(errorCode(r));
      if (
        r.http !== 200 &&
        (/Field not allowed/i.test(JSON.stringify(r.body)) ||
          /INVALID_ARGUMENT/i.test(code))
      ) {
        pass("reject_tampered_fields", code || JSON.stringify(r.body).slice(0, 200));
      } else {
        fail("reject_tampered_fields", JSON.stringify(r.body));
      }
      const after = (await db.collection("events").doc(fullId).get()).data() || {};
      if (
        after.createdBy === owner.uid &&
        after.attendeesCount === 0 &&
        after.deleted === false &&
        after.archived === false &&
        after.status !== "approved"
      ) {
        pass("tamper_no_effect", `status=${after.status}`);
      } else {
        fail("tamper_no_effect", JSON.stringify({
          createdBy: after.createdBy,
          attendeesCount: after.attendeesCount,
          deleted: after.deleted,
          status: after.status,
        }));
      }
    }

    // 6) Unauthorized user
    if (fullId) {
      r = await callCallable("updateEvent", other.idToken, {
        eventId: fullId,
        title: `${MARKER} stolen`,
      });
      const code = String(errorCode(r));
      if (
        r.http !== 200 &&
        (/PERMISSION_DENIED/i.test(code) ||
          /Not allowed/i.test(JSON.stringify(r.body)))
      ) {
        pass("reject_non_owner", code || JSON.stringify(r.body).slice(0, 200));
      } else {
        fail("reject_non_owner", JSON.stringify(r.body));
      }
    }

    // Detail-shaped read (Firestore document used by app detail / landing mapper)
    if (fullId) {
      const data = (await db.collection("events").doc(fullId).get()).data() || {};
      const detailOk =
        data.title &&
        data.description &&
        data.eventTimeZone === "America/Sao_Paulo" &&
        data.startAt &&
        data.endAt &&
        data.ticketType === "paid" &&
        Array.isArray(data.schedule) &&
        Array.isArray(data.attractions) &&
        Array.isArray(data.photoUrls);
      if (detailOk) {
        pass(
          "detail_shape",
          `tz=${data.eventTimeZone} schedule=${data.schedule.length} attractions=${data.attractions.length} photos=${data.photoUrls.length}`,
        );
      } else {
        fail("detail_shape", "missing canonical fields");
      }
      // Local landing confirmation is offline mapper check — dump fixture for local preview
      const fixturePath = path.join(
        REPORT_DIR,
        `EVENT_FORM_QA_FIXTURE_${MARKER}.json`,
      );
      fs.writeFileSync(
        fixturePath,
        JSON.stringify({ id: fullId, ...data, startAt: data.startAt?.toDate?.()?.toISOString?.() || data.startAt, endAt: data.endAt?.toDate?.()?.toISOString?.() || data.endAt }, null, 2),
      );
      pass("local_landing_fixture", fixturePath);
      cleanupNotes.push(`fixture_kept_for_report:${fixturePath}`);
    }
  } catch (e) {
    fail("smoke_exception", e && e.stack ? e.stack : String(e));
  } finally {
    // Cleanup ONLY EVENT_FORM_QA_* created in this run
    for (const id of eventIds) {
      await hardDeleteEvent(id);
      cleanupNotes.push(`deleted_event:${id}`);
    }
    // Also sweep any leftover title marker from this run
    try {
      const snap = await admin.firestore().collection("events").limit(300).get();
      for (const doc of snap.docs) {
        const t = (doc.data().title || "").toString();
        if (t.includes(MARKER) || t.includes("EVENT_FORM_QA_")) {
          // Only delete docs whose title contains this run marker OR orphan QA with our owner
          if (t.includes(MARKER) || (owner && doc.data().createdBy === owner.uid && t.includes("EVENT_FORM_QA_"))) {
            await hardDeleteEvent(doc.id);
            cleanupNotes.push(`swept_event:${doc.id}`);
          }
        }
      }
    } catch (e) {
      cleanupNotes.push(`sweep_error:${e.message}`);
    }

    if (owner) {
      await deleteCreateRequests(owner.uid);
      await hardDeleteUser(owner.uid);
      await deleteAuthUser(owner.idToken).catch(() => {});
      cleanupNotes.push(`deleted_owner:${owner.uid}`);
    }
    if (other) {
      await hardDeleteUser(other.uid);
      await deleteAuthUser(other.idToken).catch(() => {});
      cleanupNotes.push(`deleted_other:${other.uid}`);
    }
  }

  const failed = results.filter((x) => !x.ok);
  const reportPath = path.join(
    REPORT_DIR,
    `EVENT_FORM_CF_SMOKE_${new Date().toISOString().replace(/[:.]/g, "-")}.md`,
  );
  const lines = [
    "# Smoke report — createEvent / updateEvent",
    "",
    `- Marker: \`${MARKER}\``,
    `- Project: \`${PROJECT}\``,
    `- UTC: \`${new Date().toISOString()}\``,
    `- Pass: ${results.filter((x) => x.ok).length}`,
    `- Fail: ${failed.length}`,
    "",
    "## Results",
    "",
  ];
  for (const r of results) {
    lines.push(`- ${r.ok ? "PASS" : "FAIL"} \`${r.name}\`${r.detail ? ` — ${r.detail}` : ""}`);
  }
  lines.push("", "## Cleanup", "");
  for (const n of cleanupNotes) lines.push(`- ${n}`);
  lines.push("");
  fs.writeFileSync(reportPath, lines.join("\n"));
  console.log("REPORT", reportPath);
  console.log("MARKER", MARKER);
  console.log(failed.length ? `SMOKE_FAIL=${failed.length}` : "SMOKE_OK");
  process.exit(failed.length ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
