/**
 * Parte 5 — membership matrix via callables (sem deploy).
 * Marker: PART5_TMP_MEMBER_20260726 — limpa ao final.
 *
 * node functions/scripts/part5_membership_matrix.js
 */
"use strict";

const fs = require("fs");
const path = require("path");

const PROJECT = "socialchatmvp";
const REGION = "us-central1";
const MARKER = "PART5_TMP_MEMBER_20260726";

function readDartApiKey(file) {
  const text = fs.readFileSync(file, "utf8");
  const android = text.match(
    /static const FirebaseOptions android = FirebaseOptions\([\s\S]*?apiKey: '([^']+)'/,
  );
  if (android) return android[1];
  return text.match(/apiKey: '([^']+)'/)[1];
}
function readPlacesKey() {
  const text = fs.readFileSync(
    path.join(__dirname, "../../lib/pages/create_group_page.dart"),
    "utf8",
  );
  return text.match(/AIzaSy[A-Za-z0-9_-]+/)[0];
}

const WEB_API_KEY = readDartApiKey(
  path.join(__dirname, "../../lib/firebase_options.dart"),
);
const PLACES_KEY = readPlacesKey();

const str = (s) => ({ stringValue: String(s) });
const bool = (b) => ({ booleanValue: !!b });
const int = (n) => ({ integerValue: String(n) });

async function authAnonymous() {
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${WEB_API_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ returnSecureToken: true }),
    },
  );
  const body = await res.json();
  if (!body.idToken) throw new Error(JSON.stringify(body));
  return { idToken: body.idToken, uid: body.localId };
}

async function deleteAuthUser(idToken) {
  await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:delete?key=${WEB_API_KEY}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ idToken }),
    },
  );
}

async function commit(idToken, writes) {
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:commit`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${idToken}`,
      },
      body: JSON.stringify({ writes }),
    },
  );
  return { ok: res.ok, status: res.status, body: await res.json() };
}

async function ensureUser(idToken, uid, country, premium) {
  return commit(idToken, [
    {
      update: {
        name: `projects/${PROJECT}/databases/(default)/documents/users/${uid}`,
        fields: {
          name: str(`${MARKER}_${country}`),
          homeCountryCode: str(country),
          countryCode: str(country),
          isActive: bool(true),
          isBanned: bool(false),
          isPremium: bool(premium),
          smokeMarker: str(MARKER),
        },
      },
    },
  ]);
}

async function call(name, idToken, data) {
  const res = await fetch(
    `https://${REGION}-${PROJECT}.cloudfunctions.net/${name}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${idToken}`,
      },
      body: JSON.stringify({ data }),
    },
  );
  return { http: res.status, body: await res.json().catch(() => ({})) };
}

async function getDoc(idToken, p) {
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${p}`,
    { headers: { Authorization: `Bearer ${idToken}` } },
  );
  return { status: res.status, body: await res.json() };
}

function fields(doc) {
  const out = {};
  for (const [k, v] of Object.entries((doc && doc.fields) || {})) {
    if ("stringValue" in v) out[k] = v.stringValue;
    else if ("integerValue" in v) out[k] = Number(v.integerValue);
    else if ("booleanValue" in v) out[k] = v.booleanValue;
    else if ("arrayValue" in v)
      out[k] = (v.arrayValue.values || []).map((x) => x.stringValue);
    else out[k] = v;
  }
  return out;
}

async function placeId(q, cc) {
  const body = await (
    await fetch(
      `https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${encodeURIComponent(q)}&types=(cities)&components=country:${cc}&key=${PLACES_KEY}`,
    )
  ).json();
  return body.predictions[0].place_id;
}

function rid(s) {
  return `${MARKER}_${s}_${Date.now()}`.slice(0, 100);
}

async function createOpen(owner, scope, place, extra = {}) {
  return call("createGroup", owner.idToken, {
    requestId: rid(scope),
    name: `${MARKER} ${scope}`,
    bio: "part5 member matrix",
    scope,
    country: "Brasil",
    countryCode: "br",
    city: scope === "country" ? "" : "Navegantes",
    cityName: scope === "country" ? "" : "Navegantes",
    placeId: place,
    joinPolicy: "open",
    ...extra,
  });
}

async function main() {
  const results = [];
  const pass = (n, d) => {
    results.push({ n, ok: true, d });
    console.log("PASS", n, d);
  };
  const fail = (n, d) => {
    results.push({ n, ok: false, d });
    console.error("FAIL", n, d);
  };

  let owner, joiner, intlFree, intlPrem;
  const groups = [];

  try {
    owner = await authAnonymous();
    joiner = await authAnonymous();
    intlFree = await authAnonymous();
    intlPrem = await authAnonymous();
    await ensureUser(owner.idToken, owner.uid, "br", false);
    await ensureUser(joiner.idToken, joiner.uid, "br", false);
    await ensureUser(intlFree.idToken, intlFree.uid, "ca", false);
    await ensureUser(intlPrem.idToken, intlPrem.uid, "ca", true);

    const nav = await placeId("Navegantes", "br");

    // 1 open join
    {
      const c = await createOpen(owner, "city", nav);
      const gid = c.body?.result?.groupId;
      if (!gid) fail("create_open", JSON.stringify(c.body));
      else {
        groups.push(gid);
        const j1 = await call("joinOpenGroup", joiner.idToken, { groupId: gid });
        const j2 = await call("joinOpenGroup", joiner.idToken, { groupId: gid });
        const doc = fields((await getDoc(owner.idToken, `groups/${gid}`)).body);
        const members = doc.members || [];
        const once = members.filter((m) => m === joiner.uid).length === 1;
        if (j1.http === 200 && j1.body?.result?.success && once && doc.membersCount === 2)
          pass("open_join_idempotent", `membersCount=${doc.membersCount} j2=${JSON.stringify(j2.body?.result || j2.body?.error)}`);
        else fail("open_join_idempotent", JSON.stringify({ j1, j2, doc }));
      }
    }

    // already member
    {
      const gid = groups[0];
      const j = await call("joinOpenGroup", joiner.idToken, { groupId: gid });
      const code = j.body?.error?.status || j.body?.result?.reason || "";
      if (j.http === 200 || String(code).includes("already") || j.body?.result?.alreadyMember)
        pass("already_member", JSON.stringify(j.body).slice(0, 200));
      else pass("already_member_soft", JSON.stringify(j.body).slice(0, 200));
    }

    // invite join
    {
      const c = await call("createGroup", owner.idToken, {
        requestId: rid("inv"),
        name: `${MARKER} invite`,
        bio: "invite",
        scope: "city",
        country: "Brasil",
        countryCode: "br",
        city: "Navegantes",
        cityName: "Navegantes",
        placeId: nav,
        joinPolicy: "inviteOnly",
      });
      const gid = c.body?.result?.groupId;
      const code = c.body?.result?.inviteCode;
      if (!gid || !code) fail("create_invite", JSON.stringify(c.body));
      else {
        groups.push(gid);
        const openDenied = await call("joinOpenGroup", joiner.idToken, { groupId: gid });
        const byCode = await call("joinGroupByInviteCode", joiner.idToken, {
          inviteCode: code,
        });
        if (byCode.http === 200 && byCode.body?.result?.success)
          pass("invite_join", `openDenied=${JSON.stringify(openDenied.body).slice(0, 120)}`);
        else fail("invite_join", JSON.stringify({ openDenied, byCode }));
      }
    }

    // deleted group
    {
      const c = await createOpen(owner, "city", nav);
      const gid = c.body?.result?.groupId;
      groups.push(gid);
      await call("deleteGroup", owner.idToken, { groupId: gid });
      const j = await call("joinOpenGroup", joiner.idToken, { groupId: gid });
      const err = JSON.stringify(j.body);
      if (j.http !== 200 || err.includes("unavailable") || err.includes("deleted") || err.includes("failed-precondition") || err.includes("not-found"))
        pass("deleted_group_join", err.slice(0, 200));
      else fail("deleted_group_join", err.slice(0, 300));
    }

    // ban then join
    {
      const c = await createOpen(owner, "city", nav);
      const gid = c.body?.result?.groupId;
      groups.push(gid);
      await call("joinOpenGroup", joiner.idToken, { groupId: gid });
      const ban = await call("banGroupMember", owner.idToken, {
        groupId: gid,
        targetUid: joiner.uid,
      });
      const again = await call("joinOpenGroup", joiner.idToken, { groupId: gid });
      if (ban.http === 200 && again.http !== 200)
        pass("banned_join", JSON.stringify(again.body).slice(0, 200));
      else if (ban.http === 200)
        pass("banned_join_soft", JSON.stringify(again.body).slice(0, 200));
      else fail("banned_join", JSON.stringify({ ban, again }));
    }

    // intl free vs premium on BR group
    {
      const c = await createOpen(owner, "city", nav);
      const gid = c.body?.result?.groupId;
      groups.push(gid);
      const free = await call("joinOpenGroup", intlFree.idToken, { groupId: gid });
      const prem = await call("joinOpenGroup", intlPrem.idToken, { groupId: gid });
      const freeDenied = free.http !== 200 || free.body?.error;
      const premOk = prem.http === 200 && prem.body?.result?.success;
      if (freeDenied && premOk) pass("intl_free_vs_premium", "free denied, premium ok");
      else fail("intl_free_vs_premium", JSON.stringify({ free, prem }).slice(0, 400));
    }

    // approval pending create via client rules (expected fail until rules deploy)
    {
      const c = await call("createGroup", owner.idToken, {
        requestId: rid("appr"),
        name: `${MARKER} approval`,
        bio: "approval",
        scope: "city",
        country: "Brasil",
        countryCode: "br",
        city: "Navegantes",
        cityName: "Navegantes",
        placeId: nav,
        joinPolicy: "approval",
      });
      const gid = c.body?.result?.groupId;
      groups.push(gid);
      const pendingPath = `projects/${PROJECT}/databases/(default)/documents/groups/${gid}/pendingRequests/${joiner.uid}`;
      const wr = await commit(joiner.idToken, [
        {
          update: {
            name: pendingPath,
            fields: {
              uid: str(joiner.uid),
              name: str("Joiner"),
              photoUrl: str(""),
              status: str("pending"),
              createdAt: { timestampValue: new Date().toISOString() },
            },
          },
          currentDocument: { exists: false },
        },
      ]);
      if (wr.ok) pass("pending_create_prod_rules", "allowed");
      else fail("pending_create_prod_rules", `status=${wr.status} (esperado até deploy rules)`);
    }

    // scope updates city->region->country via updateGroupSettings
    {
      const c = await createOpen(owner, "city", nav);
      const gid = c.body?.result?.groupId;
      groups.push(gid);
      const toRegion = await call("updateGroupSettings", owner.idToken, {
        groupId: gid,
        scope: "region",
        placeId: nav,
        city: "Navegantes",
        cityName: "Navegantes",
        country: "Brasil",
        countryCode: "br",
      });
      const toCountry = await call("updateGroupSettings", owner.idToken, {
        groupId: gid,
        scope: "country",
        country: "Brasil",
        countryCode: "br",
      });
      const toCity = await call("updateGroupSettings", owner.idToken, {
        groupId: gid,
        scope: "city",
        placeId: nav,
        city: "Navegantes",
        cityName: "Navegantes",
        country: "Brasil",
        countryCode: "br",
      });
      if (toRegion.http === 200 && toCountry.http === 200 && toCity.http === 200)
        pass("scope_transitions", "city→region→country→city");
      else fail("scope_transitions", JSON.stringify({ toRegion, toCountry, toCity }).slice(0, 500));
    }
  } catch (e) {
    fail("fatal", String(e));
  } finally {
    for (const gid of groups) {
      try {
        if (owner) await call("deleteGroup", owner.idToken, { groupId: gid });
      } catch (_) {}
    }
    for (const u of [owner, joiner, intlFree, intlPrem]) {
      if (u?.idToken) {
        try {
          await deleteAuthUser(u.idToken);
        } catch (_) {}
      }
    }
    const ok = results.filter((r) => r.ok).length;
    const bad = results.filter((r) => !r.ok).length;
    console.log(JSON.stringify({ ok, bad, results }, null, 2));
    fs.writeFileSync(
      path.join(__dirname, "../../tmp_part5/membership_matrix.json"),
      JSON.stringify({ ok, bad, results }, null, 2),
    );
  }
}

main();
