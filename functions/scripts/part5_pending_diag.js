/**
 * Diagnóstico: create pendingRequests + collectionGroup (sem deploy).
 * Cria owner+joiner anônimos, grupo approval, tenta pending create via Rules.
 * Marker: PART5_TMP_PENDING_DIAG_20260726 — limpa ao final.
 */
"use strict";

const fs = require("fs");
const path = require("path");

const PROJECT = "socialchatmvp";
const REGION = "us-central1";
const MARKER = "PART5_TMP_PENDING_DIAG_20260726";

function readDartApiKey(file) {
  const text = fs.readFileSync(file, "utf8");
  const android = text.match(
    /static const FirebaseOptions android = FirebaseOptions\([\s\S]*?apiKey: '([^']+)'/,
  );
  if (android) return android[1];
  const any = text.match(/apiKey: '([^']+)'/);
  return any ? any[1] : "";
}

function readPlacesKey() {
  const text = fs.readFileSync(
    path.join(__dirname, "../../lib/pages/create_group_page.dart"),
    "utf8",
  );
  const m = text.match(/AIzaSy[A-Za-z0-9_-]+/);
  if (!m) throw new Error("Places key not found");
  return m[0];
}

const WEB_API_KEY = readDartApiKey(
  path.join(__dirname, "../../lib/firebase_options.dart"),
);
const PLACES_KEY = readPlacesKey();

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

async function firestoreCommit(idToken, writes) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:commit`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({ writes }),
  });
  const body = await res.json();
  return { ok: res.ok, status: res.status, body };
}

function strVal(s) {
  return { stringValue: String(s) };
}
function boolVal(b) {
  return { booleanValue: !!b };
}

async function ensureUserProfile(idToken, uid, countryCode, opts = {}) {
  const name = `projects/${PROJECT}/databases/(default)/documents/users/${uid}`;
  const fields = {
    name: strVal(`${MARKER}_user`),
    homeCountryCode: strVal(countryCode),
    countryCode: strVal(countryCode),
    isActive: boolVal(true),
    isBanned: boolVal(false),
    isPremium: boolVal(!!opts.premium),
    smokeMarker: strVal(MARKER),
  };
  return firestoreCommit(idToken, [{ update: { name, fields } }]);
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
  const body = await res.json().catch(() => ({}));
  return { http: res.status, body };
}

async function getDoc(idToken, collection, id) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${collection}/${id}`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${idToken}` },
  });
  const body = await res.json();
  if (!res.ok) {
    throw new Error(`getDoc ${collection}/${id}: ${JSON.stringify(body)}`);
  }
  return body;
}

function fieldsToObject(doc) {
  const out = {};
  const fields = (doc && doc.fields) || {};
  for (const [k, v] of Object.entries(fields)) {
    if ("stringValue" in v) out[k] = v.stringValue;
    else if ("integerValue" in v) out[k] = Number(v.integerValue);
    else if ("doubleValue" in v) out[k] = v.doubleValue;
    else if ("booleanValue" in v) out[k] = v.booleanValue;
    else if ("nullValue" in v) out[k] = null;
    else if ("arrayValue" in v) {
      out[k] = (v.arrayValue.values || []).map((x) =>
        x.stringValue !== undefined ? x.stringValue : x,
      );
    } else out[k] = v;
  }
  return out;
}

async function findCityPlaceId(query, countryCode) {
  const url =
    "https://maps.googleapis.com/maps/api/place/autocomplete/json" +
    `?input=${encodeURIComponent(query)}` +
    `&types=(cities)` +
    `&components=country:${countryCode}` +
    `&key=${PLACES_KEY}`;
  const res = await fetch(url);
  const body = await res.json();
  if (body.status !== "OK" || !body.predictions?.length) {
    throw new Error(`Places autocomplete failed: ${body.status}`);
  }
  return body.predictions[0].place_id;
}

async function createPending(idToken, groupId, uid, mode) {
  const name = `projects/${PROJECT}/databases/(default)/documents/groups/${groupId}/pendingRequests/${uid}`;
  const fields = {
    uid: strVal(uid),
    name: strVal("Joiner"),
    photoUrl: strVal(""),
    status: strVal("pending"),
  };
  if (mode === "withTimestamp") {
    // omit timestamp — client uses serverTimestamp; REST uses current time
    fields.createdAt = { timestampValue: new Date().toISOString() };
  }
  // Try pure create (update without exists → create via update transforms)
  if (mode === "create") {
    return firestoreCommit(idToken, [
      {
        update: { name, fields },
        currentDocument: { exists: false },
      },
    ]);
  }
  if (mode === "merge") {
    return firestoreCommit(idToken, [
      {
        update: { name, fields: { ...fields, createdAt: { timestampValue: new Date().toISOString() } } },
      },
    ]);
  }
  return firestoreCommit(idToken, [
    {
      update: {
        name,
        fields: {
          ...fields,
          createdAt: { timestampValue: new Date().toISOString() },
        },
      },
      currentDocument: { exists: false },
    },
  ]);
}

async function runCollectionGroup(idToken, uid) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:runQuery`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId: "pendingRequests", allDescendants: true }],
        where: {
          compositeFilter: {
            op: "AND",
            filters: [
              {
                fieldFilter: {
                  field: { fieldPath: "uid" },
                  op: "EQUAL",
                  value: strVal(uid),
                },
              },
              {
                fieldFilter: {
                  field: { fieldPath: "status" },
                  op: "EQUAL",
                  value: strVal("pending"),
                },
              },
            ],
          },
        },
        limit: 10,
      },
    }),
  });
  const body = await res.json();
  return { ok: res.ok, status: res.status, body };
}

async function deleteGroupHard(adminToken, groupId) {
  // Soft delete via callable if available; else leave for cleanup script with admin
  return callCallable("deleteGroup", adminToken, { groupId });
}

async function main() {
  const created = [];
  let owner;
  let joiner;
  try {
    owner = await authAnonymous();
    joiner = await authAnonymous();
    console.log("owner", owner.uid);
    console.log("joiner", joiner.uid);

    const upO = await ensureUserProfile(owner.idToken, owner.uid, "br");
    const upJ = await ensureUserProfile(joiner.idToken, joiner.uid, "br");
    console.log("profile owner", upO.ok, upO.status, JSON.stringify(upO.body).slice(0, 200));
    console.log("profile joiner", upJ.ok, upJ.status, JSON.stringify(upJ.body).slice(0, 200));

    const placeId = await findCityPlaceId("Navegantes", "br");
    const createdG = await callCallable("createGroup", owner.idToken, {
      requestId: `${MARKER}_${Date.now()}`,
      name: `${MARKER} Approval`,
      bio: "diag approval",
      scope: "city",
      country: "Brasil",
      countryCode: "br",
      city: "Navegantes",
      cityName: "Navegantes",
      placeId,
      joinPolicy: "approval",
    });
    console.log("createGroup", createdG.http, JSON.stringify(createdG.body).slice(0, 400));
    const groupId = createdG.body?.result?.groupId;
    if (!groupId) throw new Error("no groupId");
    created.push(groupId);

    {
      const gDoc = await getDoc(owner.idToken, "groups", groupId);
      const gObj = fieldsToObject(gDoc);
      console.log(
        "GROUP_FIELDS",
        JSON.stringify({
          joinPolicy: gObj.joinPolicy,
          deleted: gObj.deleted,
          countryCode: gObj.countryCode,
          isPremiumGroup: gObj.isPremiumGroup,
          ownerId: gObj.ownerId,
          members: gObj.members,
          admins: gObj.admins,
          scope: gObj.scope,
        }),
      );
      const uDoc = await getDoc(joiner.idToken, "users", joiner.uid);
      console.log("JOINER_USER", JSON.stringify(fieldsToObject(uDoc)));
    }

    for (const mode of ["create", "withTimestamp", "merge"]) {
      const r = await createPending(joiner.idToken, groupId, joiner.uid, mode);
      console.log(
        `pending_${mode}`,
        r.ok,
        r.status,
        JSON.stringify(r.body).slice(0, 500),
      );
    }

    const cg = await runCollectionGroup(joiner.idToken, joiner.uid);
    console.log(
      "collectionGroup",
      cg.ok,
      cg.status,
      JSON.stringify(cg.body).slice(0, 600),
    );

    // Direct get of own pending (path read)
    const getUrl = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/groups/${groupId}/pendingRequests/${joiner.uid}`;
    const getRes = await fetch(getUrl, {
      headers: { Authorization: `Bearer ${joiner.idToken}` },
    });
    console.log(
      "getOwnPending",
      getRes.status,
      (await getRes.text()).slice(0, 400),
    );

    // Soft-delete as owner
    const del = await deleteGroupHard(owner.idToken, groupId);
    console.log("deleteGroup", del.http, JSON.stringify(del.body).slice(0, 300));
  } catch (e) {
    console.error("FATAL", e);
  } finally {
    for (const u of [owner, joiner]) {
      if (u?.idToken) {
        try {
          await deleteAuthUser(u.idToken);
        } catch (_) {}
      }
    }
    console.log("createdGroups", created.join(","));
  }
}

main();
