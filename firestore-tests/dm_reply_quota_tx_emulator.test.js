/**
 * Transação real no Firestore Emulator — franquia 300.
 * used=299, dois envios simultâneos, retry requestId, uma msg + uma idempotência.
 *
 * Requer: FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 e Admin SDK.
 */
const assert = require("assert");
const admin = require("firebase-admin");
const { executeSendDmMessage } = require("../functions/send_dm_message_core");

const PROJECT_ID = "remdy-dm-quota-tx";

describe("sendDmMessage transaction concurrency (emulator)", function () {
  this.timeout(60000);
  let db;

  before(function () {
    if (!process.env.FIRESTORE_EMULATOR_HOST) {
      this.skip();
    }
    if (!admin.apps.length) {
      admin.initializeApp({ projectId: PROJECT_ID });
    }
    db = admin.firestore();
  });

  beforeEach(async () => {
    // Delete nested messages BEFORE parent conv docs (orphans survive otherwise).
    const convs = await db.collection("conversations").get();
    for (const c of convs.docs) {
      const msgs = await c.ref.collection("messages").get();
      const batch = db.batch();
      msgs.docs.forEach((d) => batch.delete(d.ref));
      if (!msgs.empty) await batch.commit();
      await c.ref.delete();
    }
    for (const name of ["users", "dmSendIdempotency"]) {
      const snap = await db.collection(name).get();
      const batch = db.batch();
      snap.docs.forEach((d) => batch.delete(d.ref));
      if (!snap.empty) await batch.commit();
    }

    await db.doc("users/free1").set({
      uid: "free1",
      homeCountryCode: "br",
      isPremium: false,
    });
    await db.doc("users/prem1").set({
      uid: "prem1",
      homeCountryCode: "us",
      isPremium: true,
      premiumUntil: admin.firestore.Timestamp.fromMillis(
        Date.now() + 86400000,
      ),
    });
    await db.doc("conversations/c_tx").set({
      participants: ["free1", "prem1"],
      pairKey: "free1_prem1",
      replyQuota: {
        version: 1,
        enabled: true,
        freeUid: "free1",
        initiatorUid: "prem1",
        limit: 300,
        used: 299,
      },
    });
  });

  it("two concurrent sends with used=299 — only one accepted, final used=300", async () => {
    const payloadA = {
      conversationId: "c_tx",
      otherUid: "prem1",
      text: "A",
      requestId: "req_concurrent_A_12345",
      messageId: "msg_concurrent_A",
    };
    const payloadB = {
      conversationId: "c_tx",
      otherUid: "prem1",
      text: "B",
      requestId: "req_concurrent_B_12345",
      messageId: "msg_concurrent_B",
    };

    const results = await Promise.allSettled([
      executeSendDmMessage(db, "free1", payloadA),
      executeSendDmMessage(db, "free1", payloadB),
    ]);

    const fulfilled = results.filter((r) => r.status === "fulfilled");
    const rejected = results.filter((r) => r.status === "rejected");
    assert.equal(fulfilled.length, 1, "exactly one send must succeed");
    assert.equal(rejected.length, 1, "exactly one send must fail");

    const err = rejected[0].reason;
    assert.ok(
      err.code === "resource-exhausted" ||
        (err.details && err.details.code === "quota-exceeded") ||
        String(err.message || "").toLowerCase().includes("allowance") ||
        String(err.message || "").toLowerCase().includes("quota"),
      `expected quota error, got ${err.code} ${err.message}`,
    );

    const conv = (await db.doc("conversations/c_tx").get()).data();
    assert.equal(conv.replyQuota.used, 300);

    const msgs = await db.collection("conversations/c_tx/messages").get();
    assert.equal(msgs.size, 1, "exactly one message document");

    const idem = await db.collection("dmSendIdempotency").get();
    assert.equal(idem.size, 1, "exactly one idempotency document");
  });

  it("retry same requestId does not consume again", async () => {
    await db.doc("conversations/c_tx").set(
      {
        replyQuota: {
          version: 1,
          enabled: true,
          freeUid: "free1",
          initiatorUid: "prem1",
          limit: 300,
          used: 290,
        },
      },
      { merge: true },
    );

    const payload = {
      conversationId: "c_tx",
      otherUid: "prem1",
      text: "hello!!", // 7 code points → 297
      requestId: "req_retry_same_id_001",
      messageId: "msg_retry_same",
    };

    const first = await executeSendDmMessage(db, "free1", payload);
    assert.equal(first.ok, true);
    assert.equal(first.idempotentReplay, false);
    assert.equal(first.replyQuota.used, 297);

    const second = await executeSendDmMessage(db, "free1", payload);
    assert.equal(second.ok, true);
    assert.equal(second.idempotentReplay, true);
    assert.equal(second.messageId, first.messageId);

    const conv = (await db.doc("conversations/c_tx").get()).data();
    assert.equal(conv.replyQuota.used, 297);

    const msgs = await db.collection("conversations/c_tx/messages").get();
    assert.equal(msgs.size, 1);

    const idem = await db.collection("dmSendIdempotency").get();
    assert.equal(idem.size, 1);
  });
});
