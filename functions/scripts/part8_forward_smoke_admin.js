/**
 * Admin seed/cleanup helper for PART8_FORWARD_TMP group paths.
 * Uses Application Default Credentials / Firebase CLI environment.
 */
"use strict";

const admin = require("firebase-admin");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const PROJECT = "socialchatmvp";
const REGION = "us-central1";
const MARKER = "PART8_FORWARD_TMP";
const RUN = `${MARKER}_ADMIN_${Date.now()}`;

function readApiKey() {
  const text = fs.readFileSync(
    path.join(__dirname, "../../lib/firebase_options.dart"),
    "utf8",
  );
  const m = text.match(
    /static const FirebaseOptions android = FirebaseOptions\([\s\S]*?apiKey: '([^']+)'/,
  );
  return m ? m[1] : text.match(/apiKey: '([^']+)'/)[1];
}

async function exchangeCustomToken(customToken) {
  const key = readApiKey();
  const res = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${key}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token: customToken, returnSecureToken: true }),
    },
  );
  const body = await res.json();
  if (!body.idToken) throw new Error(JSON.stringify(body));
  return body;
}

async function callForward(idToken, payload) {
  const res = await fetch(
    `https://${REGION}-${PROJECT}.cloudfunctions.net/forwardMessage`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${idToken}`,
      },
      body: JSON.stringify({ data: payload }),
    },
  );
  return { status: res.status, body: await res.json() };
}

async function main() {
  admin.initializeApp({ projectId: PROJECT });
  const db = admin.firestore();
  const auth = admin.auth();

  const uids = [];
  const createdAuth = [];
  const paths = [];

  console.log("RUN", RUN);
  try {
    for (let i = 0; i < 3; i++) {
      const email = `${RUN.toLowerCase()}_${i}@tmp.invalid`;
      const user = await auth.createUser({
        email,
        password: crypto.randomBytes(12).toString("hex") + "Aa1!",
        displayName: `${RUN}_${i}`,
      });
      uids.push(user.uid);
      createdAuth.push(user.uid);
      await db.collection("users").doc(user.uid).set({
        uid: user.uid,
        email,
        name: `${RUN}_${i}`,
        homeCountryCode: "br",
        countryCode: "br",
        isPremium: false,
        isBanned: false,
        marker: RUN,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      paths.push(`users/${user.uid}`);
    }
    const [a, b, c] = uids;
    const convId = [a, b].sort().join("_");
    await db.collection("conversations").doc(convId).set({
      participants: [a, b].sort(),
      pairKey: convId,
      marker: RUN,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      unread: { [a]: 0, [b]: 0 },
    });
    paths.push(`conversations/${convId}`);

    const msgId = `${RUN}_src`;
    await db
      .collection("conversations")
      .doc(convId)
      .collection("messages")
      .doc(msgId)
      .set({
        type: "text",
        text: `${RUN} admin smoke https://example.com/y`,
        senderId: a,
        fromUid: a,
        toUid: b,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        deleted: false,
        deletedBy: "",
        deletedText: "",
        replyToMessageId: "orig",
        replyToText: "should vanish",
        replyToType: "text",
        replyToIsMe: false,
        replyToImageUrl: "",
        marker: RUN,
      });
    paths.push(`conversations/${convId}/messages/${msgId}`);

    const groupId = `${RUN}_g`;
    await db.collection("groups").doc(groupId).set({
      name: `${RUN}_group`,
      members: [a, c],
      ownerId: a,
      admins: [a],
      countryCode: "br",
      isActive: true,
      marker: RUN,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    paths.push(`groups/${groupId}`);

    const gMsgId = `${RUN}_gsrc`;
    await db
      .collection("groups")
      .doc(groupId)
      .collection("messages")
      .doc(gMsgId)
      .set({
        id: gMsgId,
        type: "text",
        text: `${RUN} from group`,
        senderId: a,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        deleted: false,
        replyToMessageId: null,
        replyToText: "",
        replyToType: "text",
        replyToIsMe: false,
        replyToImageUrl: "",
        marker: RUN,
      });
    paths.push(`groups/${groupId}/messages/${gMsgId}`);

    const tokenA = await exchangeCustomToken(
      await auth.createCustomToken(a),
    );

    // DM → group
    const intent1 = `intent_${crypto.randomBytes(8).toString("hex")}`;
    const r1 = await callForward(tokenA.idToken, {
      intentId: intent1,
      source: { kind: "dm", conversationId: convId, messageId: msgId },
      destinations: [{ kind: "group", groupId }],
    });
    const body1 = r1.body.result || r1.body;
    console.log(
      "DM→group",
      r1.status,
      body1.successCount,
      JSON.stringify(body1.results || body1.error).slice(0, 200),
    );
    if (body1.results) {
      for (const x of body1.results) {
        if (x.ok && x.messageId) {
          paths.push(
            x.kind === "group"
              ? `groups/${x.destinationId}/messages/${x.messageId}`
              : `conversations/${x.destinationId}/messages/${x.messageId}`,
          );
        }
      }
    }

    // group → DM
    const intent2 = `intent_${crypto.randomBytes(8).toString("hex")}`;
    const r2 = await callForward(tokenA.idToken, {
      intentId: intent2,
      source: { kind: "group", groupId, messageId: gMsgId },
      destinations: [{ kind: "dm", conversationId: convId }],
    });
    const body2 = r2.body.result || r2.body;
    console.log(
      "group→DM",
      r2.status,
      body2.successCount,
      JSON.stringify(body2.results || body2.error).slice(0, 200),
    );
    if (body2.results) {
      for (const x of body2.results) {
        if (x.ok && x.messageId) {
          paths.push(`conversations/${x.destinationId}/messages/${x.messageId}`);
          const snap = await db
            .collection("conversations")
            .doc(x.destinationId)
            .collection("messages")
            .doc(x.messageId)
            .get();
          const d = snap.data() || {};
          console.log("forwarded fields", {
            forwarded: d.forwarded,
            senderId: d.senderId === a,
            replyToText: d.replyToText,
            text: (d.text || "").slice(0, 40),
          });
        }
      }
    }

    // group → group (same)
    const intent3 = `intent_${crypto.randomBytes(8).toString("hex")}`;
    const r3 = await callForward(tokenA.idToken, {
      intentId: intent3,
      source: { kind: "group", groupId, messageId: gMsgId },
      destinations: [{ kind: "group", groupId }],
    });
    const body3 = r3.body.result || r3.body;
    console.log("group→group", r3.status, body3.successCount);
    if (body3.results) {
      for (const x of body3.results) {
        if (x.ok && x.messageId) {
          paths.push(`groups/${groupId}/messages/${x.messageId}`);
        }
      }
    }

    // Clean idempotency docs for this uid
    const idem = await db
      .collection("forwardIdempotency")
      .where("uid", "==", a)
      .limit(20)
      .get();
    for (const doc of idem.docs) {
      if (String(doc.id).includes("fwd_")) {
        await doc.ref.delete();
        console.log("deleted idem", doc.id.slice(0, 24));
      }
    }
  } finally {
    console.log("cleanup paths", paths.length);
    for (const p of paths.reverse()) {
      try {
        await db.doc(p).delete();
      } catch (e) {
        console.log("del fail", p, e.message);
      }
    }
    for (const uid of createdAuth) {
      try {
        await auth.deleteUser(uid);
      } catch (_) {}
    }
    // Sweep any leftover by marker query where possible
    console.log("done", RUN);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
