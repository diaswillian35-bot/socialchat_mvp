/**
 * PART8 — smoke autenticado de forwardMessage (produção socialchatmvp).
 * Marker: PART8_FORWARD_TMP_* — limpa ao final (mensagens/contas reais preservadas).
 *
 * node functions/scripts/part8_forward_smoke.js
 */
"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const PROJECT = "socialchatmvp";
const REGION = "us-central1";
const MARKER = "PART8_FORWARD_TMP";
const RUN = `${MARKER}_${Date.now()}`;

function readDartApiKey(file) {
  const text = fs.readFileSync(file, "utf8");
  const android = text.match(
    /static const FirebaseOptions android = FirebaseOptions\([\s\S]*?apiKey: '([^']+)'/,
  );
  if (android) return android[1];
  return text.match(/apiKey: '([^']+)'/)[1];
}

const WEB_API_KEY = readDartApiKey(
  path.join(__dirname, "../../lib/firebase_options.dart"),
);

const results = [];
function ok(name, pass, detail) {
  results.push({ name, pass: !!pass, detail: detail || "" });
  console.log(pass ? "PASS" : "FAIL", name, detail || "");
}

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
  if (!body.idToken) throw new Error("anon auth failed: " + JSON.stringify(body));
  return { idToken: body.idToken, uid: body.localId, refreshToken: body.refreshToken };
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

async function callForward(idToken, payload) {
  const url = `https://${REGION}-${PROJECT}.cloudfunctions.net/forwardMessage`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({ data: payload }),
  });
  const body = await res.json();
  return { status: res.status, body };
}

async function fsGet(idToken, docPath) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${docPath}`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${idToken}` },
  });
  return { ok: res.ok, status: res.status, body: await res.json() };
}

async function fsPatch(idToken, docPath, fields, mask) {
  const qs = (mask || Object.keys(fields))
    .map((f) => `updateMask.fieldPaths=${encodeURIComponent(f)}`)
    .join("&");
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${docPath}?${qs}`;
  const res = await fetch(url, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({ fields }),
  });
  return { ok: res.ok, status: res.status, body: await res.json() };
}

async function fsCreate(idToken, docPath, fields) {
  // Use commit for create with name
  const name = `projects/${PROJECT}/databases/(default)/documents/${docPath}`;
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents:commit`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${idToken}`,
      },
      body: JSON.stringify({
        writes: [{ update: { name, fields } }],
      }),
    },
  );
  return { ok: res.ok, status: res.status, body: await res.json() };
}

async function fsDelete(idToken, docPath) {
  const url = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${docPath}`;
  const res = await fetch(url, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${idToken}` },
  });
  return { ok: res.ok || res.status === 404, status: res.status };
}

function str(v) {
  return { stringValue: String(v) };
}
function bool(v) {
  return { booleanValue: !!v };
}
function tsNow() {
  const d = new Date().toISOString();
  return { timestampValue: d };
}
function arr(strs) {
  return { arrayValue: { values: strs.map(str) } };
}
function map(fields) {
  return { mapValue: { fields } };
}

async function main() {
  console.log("RUN", RUN);
  const a = await authAnonymous();
  const b = await authAnonymous();
  const c = await authAnonymous(); // group peer / second dest
  console.log("uids", a.uid.slice(0, 6), b.uid.slice(0, 6), c.uid.slice(0, 6));

  const pair = [a.uid, b.uid].sort();
  const convId = `${pair[0]}_${pair[1]}`;
  const groupId = `${RUN}_g1`;
  const msgId = `${RUN}_m1`;
  const created = [];

  try {
    // Minimal user profiles (same country BR → Free OK)
    for (const u of [a, b, c]) {
      const r = await fsCreate(u.idToken, `users/${u.uid}`, {
        uid: str(u.uid),
        email: str(`${RUN}_${u.uid.slice(0, 6)}@tmp.invalid`),
        name: str(`${RUN}_user`),
        homeCountryCode: str("br"),
        countryCode: str("br"),
        isPremium: bool(false),
        isBanned: bool(false),
        marker: str(RUN),
        createdAt: tsNow(),
        updatedAt: tsNow(),
      });
      ok(`seed user ${u.uid.slice(0, 6)}`, r.ok, `status=${r.status}`);
      created.push({ token: u.idToken, path: `users/${u.uid}`, auth: u });
    }

    // Conversation A-B
    const conv = await fsCreate(a.idToken, `conversations/${convId}`, {
      participants: arr(pair),
      pairKey: str(convId),
      marker: str(RUN),
      createdAt: tsNow(),
      updatedAt: tsNow(),
      lastMessage: str(""),
      unread: map({ [a.uid]: { integerValue: "0" }, [b.uid]: { integerValue: "0" } }),
    });
    ok("seed conversation", conv.ok, `status=${conv.status}`);
    created.push({ token: a.idToken, path: `conversations/${convId}` });

    // Source text message from A
    const src = await fsCreate(
      a.idToken,
      `conversations/${convId}/messages/${msgId}`,
      {
        type: str("text"),
        text: str(`${RUN} hello https://example.com/x`),
        senderId: str(a.uid),
        fromUid: str(a.uid),
        toUid: str(b.uid),
        createdAt: tsNow(),
        deleted: bool(false),
        deletedBy: str(""),
        deletedText: str(""),
        replyToMessageId: str("should_not_copy"),
        replyToText: str("old reply"),
        replyToType: str("text"),
        replyToIsMe: bool(false),
        replyToImageUrl: str(""),
        marker: str(RUN),
      },
    );
    ok("seed source message", src.ok, `status=${src.status}`);
    created.push({
      token: a.idToken,
      path: `conversations/${convId}/messages/${msgId}`,
    });

    // Group with A+C members
    const grp = await fsCreate(a.idToken, `groups/${groupId}`, {
      name: str(`${RUN}_group`),
      members: arr([a.uid, c.uid]),
      ownerId: str(a.uid),
      admins: arr([a.uid]),
      countryCode: str("br"),
      isActive: bool(true),
      marker: str(RUN),
      createdAt: tsNow(),
      updatedAt: tsNow(),
    });
    ok("seed group", grp.ok, `status=${grp.status}`);
    created.push({ token: a.idToken, path: `groups/${groupId}` });

    // Deny: client cannot read forwardIdempotency
    const deny = await fsGet(a.idToken, `forwardIdempotency/fwd_${a.uid}_x`);
    ok("client cannot read forwardIdempotency", deny.status === 403 || deny.status === 404 || !deny.ok, `status=${deny.status}`);

    // Forward DM → DM (same conversation) + group
    const intent1 = `intent_${crypto.randomBytes(8).toString("hex")}`;
    const fwd1 = await callForward(a.idToken, {
      intentId: intent1,
      source: { kind: "dm", conversationId: convId, messageId: msgId },
      destinations: [
        { kind: "dm", conversationId: convId },
        { kind: "group", groupId },
      ],
    });
    const r1 = fwd1.body?.result || fwd1.body?.error || fwd1.body;
    ok(
      "forward DM→DM+group",
      fwd1.status === 200 && r1 && r1.successCount >= 1,
      `status=${fwd1.status} body=${JSON.stringify(r1).slice(0, 240)}`,
    );

    // Double-tap / idempotency
    const fwdDup = await callForward(a.idToken, {
      intentId: intent1,
      source: { kind: "dm", conversationId: convId, messageId: msgId },
      destinations: [
        { kind: "dm", conversationId: convId },
        { kind: "group", groupId },
      ],
    });
    const rDup = fwdDup.body?.result || fwdDup.body;
    ok(
      "idempotent double-tap",
      fwdDup.status === 200 && rDup && rDup.duplicate === true,
      `duplicate=${rDup && rDup.duplicate}`,
    );

    // Verify forwarded message fields in DM (list via REST runQuery is heavy — get by known ids from result)
    const dmResult = (r1.results || []).find((x) => x.kind === "dm" && x.ok);
    if (dmResult?.messageId) {
      const got = await fsGet(
        a.idToken,
        `conversations/${convId}/messages/${dmResult.messageId}`,
      );
      const f = got.body?.fields || {};
      ok("forwarded true", f.forwarded?.booleanValue === true);
      ok("sender is current user", f.senderId?.stringValue === a.uid);
      ok(
        "reply cleared",
        !f.replyToMessageId?.stringValue ||
          f.replyToMessageId?.nullValue !== undefined ||
          f.replyToMessageId?.stringValue === "" ||
          f.replyToMessageId?.stringValue == null,
      );
      ok(
        "no original reply text",
        (f.replyToText?.stringValue || "") === "",
      );
      ok(
        "text preserved",
        (f.text?.stringValue || "").includes("hello"),
      );
      created.push({
        token: a.idToken,
        path: `conversations/${convId}/messages/${dmResult.messageId}`,
      });
    } else {
      ok("forwarded dm messageId present", false, "missing");
    }

    const gResult = (r1.results || []).find((x) => x.kind === "group" && x.ok);
    if (gResult?.messageId) {
      created.push({
        token: a.idToken,
        path: `groups/${groupId}/messages/${gResult.messageId}`,
      });
      const gotG = await fsGet(
        a.idToken,
        `groups/${groupId}/messages/${gResult.messageId}`,
      );
      ok(
        "group forwarded true",
        gotG.body?.fields?.forwarded?.booleanValue === true,
      );
    }

    // Deleted source cannot forward
    await fsPatch(a.idToken, `conversations/${convId}/messages/${msgId}`, {
      deleted: bool(true),
      deletedBy: str(a.uid),
      deletedText: str("x"),
    });
    const intentDel = `intent_${crypto.randomBytes(8).toString("hex")}`;
    const fwdDel = await callForward(a.idToken, {
      intentId: intentDel,
      source: { kind: "dm", conversationId: convId, messageId: msgId },
      destinations: [{ kind: "group", groupId }],
    });
    ok(
      "deleted source denied",
      fwdDel.status >= 400 ||
        (fwdDel.body?.error && true) ||
        fwdDel.body?.result?.successCount === 0,
      `status=${fwdDel.status}`,
    );

    // Non-member group denied
    const foreignGroup = `${RUN}_g_foreign`;
    const g2 = await fsCreate(c.idToken, `groups/${foreignGroup}`, {
      name: str(`${RUN}_foreign`),
      members: arr([c.uid]),
      ownerId: str(c.uid),
      admins: arr([c.uid]),
      countryCode: str("br"),
      isActive: bool(true),
      marker: str(RUN),
      createdAt: tsNow(),
      updatedAt: tsNow(),
    });
    ok("seed foreign group", g2.ok, `status=${g2.status}`);
    created.push({ token: c.idToken, path: `groups/${foreignGroup}` });

    // Restore source for membership test — recreate undeleted msg
    const msgId2 = `${RUN}_m2`;
    await fsCreate(a.idToken, `conversations/${convId}/messages/${msgId2}`, {
      type: str("text"),
      text: str(`${RUN} second`),
      senderId: str(a.uid),
      fromUid: str(a.uid),
      toUid: str(b.uid),
      createdAt: tsNow(),
      deleted: bool(false),
      marker: str(RUN),
      replyToText: str(""),
      replyToType: str("text"),
      replyToIsMe: bool(false),
      replyToImageUrl: str(""),
      deletedBy: str(""),
      deletedText: str(""),
    });
    created.push({
      token: a.idToken,
      path: `conversations/${convId}/messages/${msgId2}`,
    });

    const intentNm = `intent_${crypto.randomBytes(8).toString("hex")}`;
    const fwdNm = await callForward(a.idToken, {
      intentId: intentNm,
      source: { kind: "dm", conversationId: convId, messageId: msgId2 },
      destinations: [{ kind: "group", groupId: foreignGroup }],
    });
    const rNm = fwdNm.body?.result || fwdNm.body;
    const nmFail =
      fwdNm.status >= 400 ||
      (rNm && rNm.successCount === 0) ||
      (rNm?.results || []).every((x) => !x.ok);
    ok("non-member group denied", nmFail, `status=${fwdNm.status}`);

    // Max destinations > 5
    const intentMax = `intent_${crypto.randomBytes(8).toString("hex")}`;
    const tooMany = Array.from({ length: 6 }, (_, i) => ({
      kind: "group",
      groupId: `${groupId}_x${i}`,
    }));
    const fwdMax = await callForward(a.idToken, {
      intentId: intentMax,
      source: { kind: "dm", conversationId: convId, messageId: msgId2 },
      destinations: tooMany,
    });
    ok(
      "max 5 destinations enforced",
      fwdMax.status >= 400 || !!fwdMax.body?.error,
      `status=${fwdMax.status}`,
    );
  } catch (e) {
    ok("smoke threw", false, e.message || String(e));
  }

  // Cleanup TMP docs (best-effort; Auth users deleted)
  console.log("cleanup…");
  for (const item of created.reverse()) {
    try {
      await fsDelete(item.token, item.path);
    } catch (_) {}
  }
  for (const u of [a, b, c]) {
    try {
      await deleteAuthUser(u.idToken);
    } catch (_) {}
  }

  const failed = results.filter((r) => !r.pass);
  console.log(
    JSON.stringify(
      {
        run: RUN,
        passed: results.filter((r) => r.pass).length,
        failed: failed.length,
        failures: failed,
      },
      null,
      2,
    ),
  );
  process.exit(failed.length ? 1 : 0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
