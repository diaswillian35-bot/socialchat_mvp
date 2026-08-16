/**
 * Limpeza definitiva SMOKE_TMP_GROUPS_20260726 via OAuth do Firebase CLI
 * (owner — bypass Rules). Sem curingas amplos.
 *
 *   node scripts/cleanup_smoke_groups_20260726.js --dry-run
 *   node scripts/cleanup_smoke_groups_20260726.js --execute
 */
"use strict";

const fs = require("fs");
const path = require("path");

const PROJECT = "socialchatmvp";
const MARKER = "SMOKE_TMP_GROUPS_20260726";
const KNOWN_GROUPS = [
  "fnzGBYKl10L49KTEuU0m",
  "jnwQSykcJqVWRkH6Utmt",
  "5yV4etIjkeD4hAfS7SeC",
];
const GROUP_SUBS = [
  "messages",
  "pendingRequests",
  "bannedUsers",
  "reads",
  "moderators",
];
const USER_SUBS = ["fcmTokens", "systemInbox"];

const DRY = process.argv.includes("--dry-run");
const EXECUTE = process.argv.includes("--execute");

function loadAccessToken() {
  const p = path.join(
    process.env.HOME || "",
    ".config/configstore/firebase-tools.json",
  );
  const tokens = JSON.parse(fs.readFileSync(p, "utf8")).tokens || {};
  if (!tokens.access_token) throw new Error("No Firebase CLI access_token");
  const exp = Number(tokens.expires_at || 0);
  if (exp && Date.now() > exp - 30_000) {
    throw new Error(
      "Firebase CLI access_token expired — run `firebase login --reauth`",
    );
  }
  return tokens.access_token;
}

async function fsFetch(token, method, docPath, bodyObj) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents${docPath}`;
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: bodyObj ? JSON.stringify(bodyObj) : undefined,
  });
  const text = await res.text();
  let json = {};
  try {
    json = text ? JSON.parse(text) : {};
  } catch (_) {
    json = { raw: text };
  }
  return { ok: res.ok, status: res.status, json };
}

async function runQuery(token, structuredQuery) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:runQuery`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ structuredQuery }),
  });
  const json = await res.json();
  if (!res.ok) throw new Error("runQuery: " + JSON.stringify(json));
  return (json || []).filter((r) => r.document).map((r) => r.document);
}

function fieldsToObj(doc) {
  const out = {};
  for (const [k, v] of Object.entries((doc && doc.fields) || {})) {
    if ("stringValue" in v) out[k] = v.stringValue;
    else if ("integerValue" in v) out[k] = Number(v.integerValue);
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

async function listCollection(token, parentPath, collectionId) {
  const urlPath = `${parentPath}/${collectionId}?pageSize=200`;
  const page = await fsFetch(token, "GET", urlPath);
  if (page.status === 404) return [];
  if (!page.ok) {
    // empty collection often 200 with no documents; permission errors bubble
    if (page.status === 400) return [];
    throw new Error(
      `list ${urlPath}: ${page.status} ${JSON.stringify(page.json)}`,
    );
  }
  return page.json.documents || [];
}

async function deletePath(token, docPath) {
  const r = await fsFetch(token, "DELETE", docPath);
  if (!r.ok && r.status !== 404) {
    throw new Error(`DELETE ${docPath}: ${r.status} ${JSON.stringify(r.json)}`);
  }
  return r.status !== 404;
}

async function main() {
  if (!DRY && !EXECUTE) {
    console.error("Use --dry-run or --execute");
    process.exit(2);
  }

  const token = loadAccessToken();
  const confirmed = [];
  const smokeUids = new Set();

  console.log("=== CONFIRM", MARKER, "===");

  for (const gid of KNOWN_GROUPS) {
    const r = await fsFetch(token, "GET", `/groups/${gid}`);
    if (r.status === 404) {
      console.log("already gone groups/" + gid);
      continue;
    }
    if (!r.ok) throw new Error(JSON.stringify(r.json));
    const data = fieldsToObj(r.json);
    if (!(data.name || "").includes(MARKER)) {
      console.error("REFUSE groups/" + gid + " name=" + data.name);
      process.exit(1);
    }
    console.log("OK groups/" + gid, {
      name: data.name,
      deleted: data.deleted,
      ownerId: data.ownerId,
    });
    confirmed.push({ kind: "group", id: gid, path: `groups/${gid}` });
    if (data.ownerId) smokeUids.add(data.ownerId);

    for (const sub of GROUP_SUBS) {
      const docs = await listCollection(token, `/groups/${gid}`, sub);
      for (const d of docs) {
        const rel = d.name.split("/documents/")[1];
        console.log("OK sub", rel);
        confirmed.push({ kind: "groupSub", path: rel });
      }
    }
  }

  const users = await runQuery(token, {
    from: [{ collectionId: "users" }],
    where: {
      fieldFilter: {
        field: { fieldPath: "smokeMarker" },
        op: "EQUAL",
        value: { stringValue: MARKER },
      },
    },
    limit: 50,
  });
  for (const doc of users) {
    const rel = doc.name.split("/documents/")[1];
    const data = fieldsToObj(doc);
    if (data.smokeMarker !== MARKER) {
      console.error("REFUSE", rel, data.smokeMarker);
      process.exit(1);
    }
    const uid = rel.split("/")[1];
    smokeUids.add(uid);
    console.log("OK", rel, { name: data.name });
    confirmed.push({ kind: "user", id: uid, path: rel });
    for (const sub of USER_SUBS) {
      const docs = await listCollection(token, `/users/${uid}`, sub);
      for (const d of docs) {
        const srel = d.name.split("/documents/")[1];
        console.log("OK sub", srel);
        confirmed.push({ kind: "userSub", path: srel });
      }
    }
  }

  for (const uid of smokeUids) {
    const pub = await fsFetch(token, "GET", `/publicUsers/${uid}`);
    if (pub.ok) {
      const data = fieldsToObj(pub.json);
      const userConfirmed = confirmed.some(
        (c) => c.kind === "user" && c.id === uid,
      );
      if (!userConfirmed) {
        console.log("SKIP publicUsers/" + uid + " (uid not marker-confirmed)");
        continue;
      }
      console.log("OK publicUsers/" + uid, {
        name: data.name || data.displayName,
      });
      confirmed.push({ kind: "publicUser", path: `publicUsers/${uid}` });
    }

    for (const aux of [`presence/${uid}`, `publicUserSessions/${uid}`]) {
      const r = await fsFetch(token, "GET", `/${aux}`);
      if (r.ok) {
        console.log("OK", aux);
        confirmed.push({ kind: "aux", path: aux });
      }
    }

    const reqs = await runQuery(token, {
      from: [{ collectionId: "groupCreationRequests" }],
      where: {
        fieldFilter: {
          field: { fieldPath: "createdBy" },
          op: "EQUAL",
          value: { stringValue: uid },
        },
      },
      limit: 30,
    });
    for (const doc of reqs) {
      const rel = doc.name.split("/documents/")[1];
      const id = rel.split("/")[1];
      if (!id.includes(MARKER)) {
        console.log("SKIP " + rel + " (id lacks marker)");
        continue;
      }
      console.log("OK", rel);
      confirmed.push({ kind: "creationRequest", path: rel });
    }
  }

  for (const gid of KNOWN_GROUPS) {
    const codes = await runQuery(token, {
      from: [{ collectionId: "groupInviteCodes" }],
      where: {
        fieldFilter: {
          field: { fieldPath: "groupId" },
          op: "EQUAL",
          value: { stringValue: gid },
        },
      },
      limit: 10,
    });
    for (const doc of codes) {
      const rel = doc.name.split("/documents/")[1];
      console.log("OK", rel, "(invite for confirmed smoke group)");
      confirmed.push({ kind: "inviteCode", path: rel });
    }
  }

  // Deduplicate paths
  const byPath = new Map();
  for (const c of confirmed) byPath.set(c.path, c);
  const unique = [...byPath.values()];
  console.log("\nConfirmed unique paths:", unique.length);
  unique.forEach((c) => console.log(" -", c.path));

  if (DRY) {
    console.log("\nDRY-RUN — nothing deleted.");
    return;
  }

  console.log("\n=== DELETE ===");
  const removed = [];
  // children first: subs, then parents
  const order = (a, b) => b.path.split("/").length - a.path.split("/").length;
  const sorted = unique.slice().sort(order);
  for (const c of sorted) {
    const ok = await deletePath(token, "/" + c.path);
    if (ok) {
      removed.push(c.path);
      console.log("REMOVED", c.path);
    }
  }

  console.log("\n=== VERIFY ===");
  let leftover = 0;
  for (const gid of KNOWN_GROUPS) {
    const r = await fsFetch(token, "GET", `/groups/${gid}`);
    if (r.ok && (fieldsToObj(r.json).name || "").includes(MARKER)) {
      leftover += 1;
      console.error("LEFTOVER groups/" + gid);
    } else console.log("GONE groups/" + gid);
  }
  const usersAfter = await runQuery(token, {
    from: [{ collectionId: "users" }],
    where: {
      fieldFilter: {
        field: { fieldPath: "smokeMarker" },
        op: "EQUAL",
        value: { stringValue: MARKER },
      },
    },
    limit: 10,
  });
  leftover += usersAfter.length;
  if (usersAfter.length) {
    console.error(
      "LEFTOVER users",
      usersAfter.map((d) => d.name.split("/documents/")[1]),
    );
  }

  console.log(
    JSON.stringify(
      {
        marker: MARKER,
        confirmed: unique.length,
        removed: removed.length,
        removedPaths: removed,
        leftover,
      },
      null,
      2,
    ),
  );
  if (leftover) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
