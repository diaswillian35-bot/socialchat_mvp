/**
 * Parte 5 — pending/approve/reject + updateGroupSettings(changes) após Rules deploy.
 * Marker: PART5_FIX_20260726 — limpa ao final.
 *
 * node functions/scripts/part5_pending_revalidate.js
 */
"use strict";

const fs = require("fs");
const path = require("path");

const PROJECT = "socialchatmvp";
const REGION = "us-central1";
const MARKER = "PART5_FIX_20260726";

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

async function ensureUser(idToken, uid) {
  return commit(idToken, [
    {
      update: {
        name: `projects/${PROJECT}/databases/(default)/documents/users/${uid}`,
        fields: {
          name: str(`${MARKER}_user`),
          homeCountryCode: str("br"),
          countryCode: str("br"),
          isActive: bool(true),
          isBanned: bool(false),
          isPremium: bool(false),
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
  }
  return out;
}

async function placeId(q) {
  const body = await (
    await fetch(
      `https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${encodeURIComponent(q)}&types=(cities)&components=country:br&key=${PLACES_KEY}`,
    )
  ).json();
  return body.predictions[0].place_id;
}

async function createPending(idToken, groupId, uid) {
  const name = `projects/${PROJECT}/databases/(default)/documents/groups/${groupId}/pendingRequests/${uid}`;
  return commit(idToken, [
    {
      update: {
        name,
        fields: {
          uid: str(uid),
          name: str("Joiner"),
          photoUrl: str(""),
          status: str("pending"),
          createdAt: { timestampValue: new Date().toISOString() },
        },
      },
      currentDocument: { exists: false },
    },
  ]);
}

async function collectionGroupPending(idToken, uid) {
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:runQuery`,
    {
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
                    value: str(uid),
                  },
                },
                {
                  fieldFilter: {
                    field: { fieldPath: "status" },
                    op: "EQUAL",
                    value: str("pending"),
                  },
                },
              ],
            },
          },
          limit: 20,
        },
      }),
    },
  );
  const body = await res.json();
  return { ok: res.ok, status: res.status, body };
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

  let owner, joiner, stranger;
  const groups = [];
  try {
    owner = await authAnonymous();
    joiner = await authAnonymous();
    stranger = await authAnonymous();
    await ensureUser(owner.idToken, owner.uid);
    await ensureUser(joiner.idToken, joiner.uid);
    await ensureUser(stranger.idToken, stranger.uid);
    const nav = await placeId("Navegantes");
    const itajai = await placeId("Itajai");

    // --- approval group A (approve flow)
    {
      const c = await call("createGroup", owner.idToken, {
        requestId: `${MARKER}_appr_${Date.now()}`,
        name: `${MARKER} approve`,
        bio: "approve flow",
        scope: "city",
        country: "Brasil",
        countryCode: "br",
        city: "Navegantes",
        cityName: "Navegantes",
        placeId: nav,
        joinPolicy: "approval",
      });
      const gid = c.body?.result?.groupId;
      if (!gid) throw new Error("no approve group");
      groups.push(gid);

      const p1 = await createPending(joiner.idToken, gid, joiner.uid);
      const p2 = await createPending(joiner.idToken, gid, joiner.uid);
      if (p1.ok) pass("pending_create", "ok");
      else fail("pending_create", JSON.stringify(p1.body).slice(0, 300));
      // double create on existing → update or deny; should not duplicate docs
      const getP = await getDoc(
        joiner.idToken,
        `groups/${gid}/pendingRequests/${joiner.uid}`,
      );
      if (getP.status === 200 && fields(getP.body).status === "pending")
        pass("pending_read_own", "ok");
      else fail("pending_read_own", String(getP.status));

      const cg = await collectionGroupPending(joiner.idToken, joiner.uid);
      const docs = (Array.isArray(cg.body) ? cg.body : []).filter((r) => r.document);
      if (cg.ok && docs.length >= 1) pass("collectionGroup_own", `n=${docs.length}`);
      else fail("collectionGroup_own", JSON.stringify(cg.body).slice(0, 300));

      const strangerGet = await getDoc(
        stranger.idToken,
        `groups/${gid}/pendingRequests/${joiner.uid}`,
      );
      if (strangerGet.status === 403)
        pass("stranger_denied_pending", "403");
      else fail("stranger_denied_pending", String(strangerGet.status));

      const ownerList = await fetch(
        `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/groups/${gid}/pendingRequests`,
        { headers: { Authorization: `Bearer ${owner.idToken}` } },
      );
      if (ownerList.ok) pass("owner_lists_pending", "ok");
      else fail("owner_lists_pending", String(ownerList.status));

      const appr = await call("approveGroupJoinRequest", owner.idToken, {
        groupId: gid,
        requestUid: joiner.uid,
      });
      const gAfter = fields((await getDoc(owner.idToken, `groups/${gid}`)).body);
      const isMember = (gAfter.members || []).includes(joiner.uid);
      if (appr.http === 200 && isMember && gAfter.membersCount >= 2)
        pass("approve_join", `membersCount=${gAfter.membersCount}`);
      else fail("approve_join", JSON.stringify({ appr, gAfter }).slice(0, 400));
    }

    // --- approval group B (reject flow)
    {
      const c = await call("createGroup", owner.idToken, {
        requestId: `${MARKER}_rej_${Date.now()}`,
        name: `${MARKER} reject`,
        bio: "reject flow",
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
      await createPending(joiner.idToken, gid, joiner.uid);
      const rej = await call("rejectGroupJoinRequest", owner.idToken, {
        groupId: gid,
        requestUid: joiner.uid,
      });
      const pend = await getDoc(
        joiner.idToken,
        `groups/${gid}/pendingRequests/${joiner.uid}`,
      );
      const status = fields(pend.body).status;
      const g = fields((await getDoc(owner.idToken, `groups/${gid}`)).body);
      const notMember = !(g.members || []).includes(joiner.uid);
      if (rej.http === 200 && notMember && status !== "pending")
        pass("reject_join", `status=${status}`);
      else fail("reject_join", JSON.stringify({ rej, status, notMember }).slice(0, 400));
    }

    // --- scope transitions with changes:{}
    {
      const c = await call("createGroup", owner.idToken, {
        requestId: `${MARKER}_scope_${Date.now()}`,
        name: `${MARKER} scope`,
        bio: "scope",
        scope: "city",
        country: "Brasil",
        countryCode: "br",
        city: "Navegantes",
        cityName: "Navegantes",
        placeId: nav,
        joinPolicy: "open",
      });
      const gid = c.body?.result?.groupId;
      groups.push(gid);

      const toRegion = await call("updateGroupSettings", owner.idToken, {
        groupId: gid,
        changes: {
          scope: "region",
          placeId: itajai,
          city: "Itajaí",
          cityName: "Itajaí",
          country: "Brasil",
          countryCode: "br",
        },
      });
      const afterRegion = fields((await getDoc(owner.idToken, `groups/${gid}`)).body);
      const toCountry = await call("updateGroupSettings", owner.idToken, {
        groupId: gid,
        changes: {
          scope: "country",
          country: "Brasil",
          countryCode: "br",
        },
      });
      const afterCountry = fields((await getDoc(owner.idToken, `groups/${gid}`)).body);
      const toCity = await call("updateGroupSettings", owner.idToken, {
        groupId: gid,
        changes: {
          scope: "city",
          placeId: nav,
          city: "Navegantes",
          cityName: "Navegantes",
          country: "Brasil",
          countryCode: "br",
        },
      });
      const afterCity = fields((await getDoc(owner.idToken, `groups/${gid}`)).body);

      const nameEdit = await call("updateGroupSettings", owner.idToken, {
        groupId: gid,
        changes: { name: `${MARKER} renamed`, bio: "edited bio" },
      });
      const denied = await call("updateGroupSettings", joiner.idToken, {
        groupId: gid,
        changes: { name: "hack" },
      });

      if (
        toRegion.http === 200 &&
        afterRegion.scope === "region" &&
        Number(afterRegion.regionRadiusKm) === 110 &&
        toCountry.http === 200 &&
        afterCountry.scope === "country" &&
        toCity.http === 200 &&
        afterCity.scope === "city" &&
        nameEdit.http === 200 &&
        denied.http !== 200
      ) {
        pass(
          "scope_and_edit",
          `regionRadius=${afterRegion.regionRadiusKm} countryClearsCity=${!afterCountry.city || afterCountry.city === ""} denied=${denied.http}`,
        );
      } else {
        fail(
          "scope_and_edit",
          JSON.stringify({
            toRegion,
            afterRegion,
            toCountry,
            afterCountry,
            toCity,
            afterCity,
            nameEdit,
            denied,
          }).slice(0, 800),
        );
      }
    }
  } catch (e) {
    fail("fatal", String(e));
  } finally {
    for (const gid of groups) {
      try {
        if (owner) await call("deleteGroup", owner.idToken, { groupId: gid });
      } catch (_) {}
    }
    // hard-delete soft leftovers via admin token
    try {
      const token = JSON.parse(
        fs.readFileSync(
          path.join(process.env.HOME, ".config/configstore/firebase-tools.json"),
          "utf8",
        ),
      ).tokens.access_token;
      for (const gid of groups) {
        await fetch(
          `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/groups/${gid}`,
          { method: "DELETE", headers: { Authorization: `Bearer ${token}` } },
        );
      }
    } catch (_) {}
    for (const u of [owner, joiner, stranger]) {
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
      path.join(__dirname, "../../tmp_part5/pending_revalidate.json"),
      JSON.stringify({ ok, bad, results }, null, 2),
    );
  }
}

main();
