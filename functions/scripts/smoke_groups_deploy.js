/**
 * Smoke autenticado temporário — grupos Remdy (socialchatmvp).
 * Cria usuários anônimos + grupos marcados SMOKE_TMP_, valida, apaga.
 *
 * Uso:
 *   node functions/scripts/smoke_groups_deploy.js
 */
"use strict";

const fs = require("fs");
const path = require("path");

const PROJECT = "socialchatmvp";
const REGION = "us-central1";
const MARKER = "SMOKE_TMP_GROUPS_20260726";

function readDartApiKey(file, platformHint) {
  const text = fs.readFileSync(file, "utf8");
  // Prefer android options block
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
  if (!m) throw new Error("Places key not found in create_group_page.dart");
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
  return { idToken: body.idToken, uid: body.localId, refreshToken: body.refreshToken };
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
  if (!res.ok) {
    throw new Error(`firestore commit ${res.status}: ${JSON.stringify(body)}`);
  }
  return body;
}

function strVal(s) {
  return { stringValue: String(s) };
}
function boolVal(b) {
  return { booleanValue: !!b };
}
function intVal(n) {
  return { integerValue: String(n) };
}

async function ensureUserProfile(idToken, uid, countryCode) {
  const name = `projects/${PROJECT}/databases/(default)/documents/users/${uid}`;
  await firestoreCommit(idToken, [
    {
      update: {
        name,
        fields: {
          name: strVal(`${MARKER}_user`),
          homeCountryCode: strVal(countryCode),
          countryCode: strVal(countryCode),
          isActive: boolVal(true),
          isBanned: boolVal(false),
          isPremium: boolVal(false),
          smokeMarker: strVal(MARKER),
        },
      },
    },
  ]);
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
  if (!res.ok) throw new Error(`getDoc ${collection}/${id}: ${JSON.stringify(body)}`);
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
    throw new Error(`Places autocomplete failed for ${query}: ${body.status}`);
  }
  return body.predictions[0].place_id;
}

function requestId(suffix) {
  return `${MARKER}_${suffix}_${Date.now()}`.replace(/[^A-Za-z0-9_-]/g, "_").slice(0, 100);
}

async function main() {
  const results = [];
  const createdGroupIds = [];
  let owner;
  let joiner;
  let nonOwner;

  const pass = (name, detail) => {
    results.push({ name, ok: true, detail });
    console.log(`PASS ${name}: ${detail}`);
  };
  const fail = (name, detail) => {
    results.push({ name, ok: false, detail });
    console.error(`FAIL ${name}: ${detail}`);
  };

  try {
    owner = await authAnonymous();
    joiner = await authAnonymous();
    nonOwner = await authAnonymous();
    await ensureUserProfile(owner.idToken, owner.uid, "br");
    await ensureUserProfile(joiner.idToken, joiner.uid, "br");
    await ensureUserProfile(nonOwner.idToken, nonOwner.uid, "br");

    const navegantesPlaceId = await findCityPlaceId("Navegantes", "br");
    const itajaiPlaceId = await findCityPlaceId("Itajai", "br");

    // 1) Cidade
    {
      const r = await callCallable("createGroup", owner.idToken, {
        requestId: requestId("city"),
        name: `${MARKER} City`,
        bio: "smoke city",
        scope: "city",
        country: "Brasil",
        countryCode: "br",
        city: "Navegantes",
        cityName: "Navegantes",
        placeId: navegantesPlaceId,
        joinPolicy: "open",
      });
      const groupId = r.body?.result?.groupId;
      if (r.http === 200 && groupId) {
        createdGroupIds.push(groupId);
        const doc = fieldsToObject(await getDoc(owner.idToken, "groups", groupId));
        if (
          doc.scope === "city" &&
          doc.countryCode === "br" &&
          doc.placeId === navegantesPlaceId &&
          (doc.regionRadiusKm == null || doc.regionRadiusKm === "")
        ) {
          pass("create_city", `${groupId} placeId ok`);
        } else {
          fail("create_city", JSON.stringify(doc));
        }
      } else {
        fail("create_city", JSON.stringify(r.body));
      }
    }

    // 2) Região 110 km
    let regionGroupId = "";
    {
      const r = await callCallable("createGroup", owner.idToken, {
        requestId: requestId("region"),
        name: `${MARKER} Region`,
        bio: "smoke region",
        scope: "region",
        country: "Brasil",
        countryCode: "br",
        city: "Itajaí",
        cityName: "Itajaí",
        placeId: itajaiPlaceId,
        // cliente envia coords forjadas — servidor deve rejeitar OU sobrescrever.
        // Implementação atual rejeita se divergirem; enviamos sem coords.
        joinPolicy: "open",
        regionRadiusKm: 110,
      });
      regionGroupId = r.body?.result?.groupId || "";
      if (r.http === 200 && regionGroupId) {
        createdGroupIds.push(regionGroupId);
        const doc = fieldsToObject(await getDoc(owner.idToken, "groups", regionGroupId));
        if (
          doc.scope === "region" &&
          doc.regionRadiusKm === 110 &&
          typeof doc.regionCenterLat === "number" &&
          doc.regionCenterGeohash &&
          doc.regionCenterCountryCode === "br"
        ) {
          pass(
            "create_region",
            `${regionGroupId} radius=${doc.regionRadiusKm} geohash=${doc.regionCenterGeohash}`,
          );
        } else {
          fail("create_region_fields", JSON.stringify(doc));
        }
      } else {
        fail("create_region", JSON.stringify(r.body));
      }
    }

    // 3) País
    let countryGroupId = "";
    {
      const r = await callCallable("createGroup", owner.idToken, {
        requestId: requestId("country"),
        name: `${MARKER} Country`,
        bio: "smoke country",
        scope: "country",
        country: "Brasil",
        countryCode: "br",
        joinPolicy: "open",
      });
      countryGroupId = r.body?.result?.groupId || "";
      if (r.http === 200 && countryGroupId) {
        createdGroupIds.push(countryGroupId);
        const doc = fieldsToObject(await getDoc(owner.idToken, "groups", countryGroupId));
        if (
          doc.scope === "country" &&
          !doc.city &&
          !doc.regionCenterCity &&
          doc.countryCode === "br"
        ) {
          pass("create_country", `${countryGroupId} country-only card fields`);
        } else {
          fail("create_country_fields", JSON.stringify(doc));
        }
      } else {
        fail("create_country", JSON.stringify(r.body));
      }
    }

    // 5) Forjados
    {
      const r = await callCallable("createGroup", owner.idToken, {
        requestId: requestId("forged"),
        name: `${MARKER} Forged`,
        bio: "should fail",
        scope: "region",
        country: "Brasil",
        countryCode: "br",
        placeId: itajaiPlaceId,
        regionCenterLat: 0,
        regionCenterLng: 0,
        regionCenterGeohash: "zzz",
        regionRadiusKm: 500,
        joinPolicy: "open",
      });
      const status = r.body?.error?.status || "";
      const msg = (r.body?.error?.message || "").toLowerCase();
      if (
        r.http >= 400 &&
        (status === "INVALID_ARGUMENT" ||
          msg.includes("radius") ||
          msg.includes("forged") ||
          msg.includes("invalid"))
      ) {
        pass("reject_forged", `${status} ${r.body?.error?.message}`);
      } else if (r.body?.result?.groupId) {
        createdGroupIds.push(r.body.result.groupId);
        fail("reject_forged", "accepted forged payload: " + JSON.stringify(r.body));
      } else {
        fail("reject_forged", JSON.stringify(r.body));
      }
    }

    // 6-7) joinOpenGroup
    if (regionGroupId) {
      const before = fieldsToObject(await getDoc(owner.idToken, "groups", regionGroupId));
      const r = await callCallable("joinOpenGroup", joiner.idToken, {
        groupId: regionGroupId,
      });
      if (r.http === 200 && (r.body?.result?.success || r.body?.result?.joined !== false)) {
        const after = fieldsToObject(await getDoc(owner.idToken, "groups", regionGroupId));
        const members = after.members || [];
        const unique = new Set(members);
        if (
          members.includes(joiner.uid) &&
          unique.size === members.length &&
          after.membersCount === members.length
        ) {
          pass(
            "join_open",
            `membersCount ${before.membersCount}->${after.membersCount} unique=${unique.size}`,
          );
        } else {
          fail("join_open_count", JSON.stringify(after));
        }
      } else {
        fail("join_open", JSON.stringify(r.body));
      }
    } else {
      fail("join_open", "no region group");
    }

    // 8) Free internacional bloqueado
    {
      const foreign = await authAnonymous();
      await ensureUserProfile(foreign.idToken, foreign.uid, "us");
      if (regionGroupId) {
        const r = await callCallable("joinOpenGroup", foreign.idToken, {
          groupId: regionGroupId,
        });
        const status = r.body?.error?.status || "";
        const msg = (r.body?.error?.message || "").toLowerCase();
        if (
          r.http >= 400 &&
          (status === "PERMISSION_DENIED" || msg.includes("premium"))
        ) {
          pass("free_intl_blocked", `${status} ${r.body?.error?.message}`);
        } else {
          fail("free_intl_blocked", JSON.stringify(r.body));
        }
      }
      await deleteAuthUser(foreign.idToken);
    }

    // 9) owner ok / non-owner denied
    if (regionGroupId) {
      const okOwner = await callCallable("updateGroupSettings", owner.idToken, {
        groupId: regionGroupId,
        changes: { bio: `${MARKER} bio owner` },
      });
      if (okOwner.http === 200 && okOwner.body?.result?.success) {
        pass("owner_edit", "bio updated");
      } else {
        fail("owner_edit", JSON.stringify(okOwner.body));
      }

      const denied = await callCallable("updateGroupSettings", nonOwner.idToken, {
        groupId: regionGroupId,
        changes: { bio: "hack", scope: "country", country: "Brasil", countryCode: "br" },
      });
      const status = denied.body?.error?.status || "";
      if (denied.http >= 400 && status === "PERMISSION_DENIED") {
        pass("non_owner_denied", status);
      } else {
        fail("non_owner_denied", JSON.stringify(denied.body));
      }
    }

    // 10) card nacional — já validado em create_country (sem cidade)
  } catch (e) {
    fail("smoke_exception", e && e.stack ? e.stack : String(e));
  }

  // Cleanup groups
  let removed = 0;
  const paths = [];
  if (owner) {
    for (const gid of createdGroupIds) {
      try {
        const r = await callCallable("deleteGroup", owner.idToken, { groupId: gid });
        if (r.http === 200) {
          removed += 1;
          paths.push(`groups/${gid}`);
        } else {
          console.error("cleanup deleteGroup failed", gid, JSON.stringify(r.body));
        }
      } catch (e) {
        console.error("cleanup error", gid, e.message || e);
      }
    }
  }

  // Delete auth users
  for (const u of [owner, joiner, nonOwner]) {
    if (u?.idToken) {
      try {
        await deleteAuthUser(u.idToken);
      } catch (_) {}
    }
  }

  console.log("\n=== SUMMARY ===");
  console.log(
    JSON.stringify(
      {
        marker: MARKER,
        passed: results.filter((r) => r.ok).length,
        failed: results.filter((r) => !r.ok).length,
        results,
        removedGroups: removed,
        removedPaths: paths,
      },
      null,
      2,
    ),
  );

  if (results.some((r) => !r.ok)) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
