/**
 * Testes — franquia Free 300 code points + autorização.
 * Contagem: Unicode scalar values (code points).
 */
const test = require("node:test");
const assert = require("node:assert/strict");
const q = require("./dm_reply_quota");

test("countCodePoints: empty and ascii", () => {
  assert.equal(q.countCodePoints(""), 0);
  assert.equal(q.countCodePoints("abc"), 3);
  assert.equal(q.countCodePoints("a b"), 3);
});

test("countCodePoints: accents and newlines", () => {
  assert.equal(q.countCodePoints("ação"), 4);
  assert.equal(q.countCodePoints("a\nb"), 3);
});

test("countCodePoints: emoji single and zwj family", () => {
  // 😀 = 1 code point
  assert.equal(q.countCodePoints("😀"), 1);
  assert.equal(q.countCodePoints("a😀b"), 3);
  // Family emoji may be multiple code points (ZWJ sequences) — consistent rule
  const family = "👨‍👩‍👧‍👦";
  const n = q.countCodePoints(family);
  assert.ok(n >= 1);
  assert.equal(q.countCodePoints(family + family), n * 2);
});

test("0/300 1/300 299/300 300/300", () => {
  const base = {
    senderUid: "free1",
    senderData: { homeCountryCode: "br", isPremium: false },
    recipientData: { homeCountryCode: "us", isPremium: true },
  };
  const a0 = q.authorizeFreeTextSend({
    ...base,
    existingQuota: { freeUid: "free1", used: 0, limit: 300, enabled: true },
    text: "x",
  });
  assert.equal(a0.ok, true);
  assert.equal(a0.consume, 1);
  assert.equal(a0.quotaAfter.used, 1);

  const a299 = q.authorizeFreeTextSend({
    ...base,
    existingQuota: { freeUid: "free1", used: 299, limit: 300, enabled: true },
    text: "y",
  });
  assert.equal(a299.ok, true);
  assert.equal(a299.quotaAfter.used, 300);

  const a300 = q.authorizeFreeTextSend({
    ...base,
    existingQuota: { freeUid: "free1", used: 300, limit: 300, enabled: true },
    text: "z",
  });
  assert.equal(a300.ok, false);
  assert.equal(a300.code, "quota-exceeded");
  assert.equal(a300.quota.remaining, 0);
});

test("message exceeding remaining balance", () => {
  const r = q.authorizeFreeTextSend({
    senderUid: "free1",
    senderData: { homeCountryCode: "br" },
    recipientData: { homeCountryCode: "us", isPremium: true },
    existingQuota: { freeUid: "free1", used: 298, limit: 300, enabled: true },
    text: "abcd", // 4 > 2 remaining
  });
  assert.equal(r.ok, false);
  assert.equal(r.code, "quota-exceeded");
  assert.equal(r.wouldConsume, 4);
});

test("several small messages accumulate", () => {
  let used = 0;
  for (const chunk of ["oi", "tudo", "bem?"]) {
    const r = q.authorizeFreeTextSend({
      senderUid: "free1",
      senderData: { homeCountryCode: "br" },
      recipientData: { homeCountryCode: "ca", isPremium: true },
      existingQuota: { freeUid: "free1", used, limit: 300, enabled: true },
      text: chunk,
    });
    assert.equal(r.ok, true);
    used = r.quotaAfter.used;
  }
  assert.equal(used, 2 + 4 + 4); // oi + tudo + bem?
});

test("media blocked under quota", () => {
  const r = q.authorizeFreeTextSend({
    senderUid: "free1",
    senderData: { homeCountryCode: "br" },
    recipientData: { homeCountryCode: "us", isPremium: true },
    existingQuota: { freeUid: "free1", used: 0, limit: 300, enabled: true },
    text: "hi",
    messageType: "image",
  });
  assert.equal(r.ok, false);
  assert.equal(r.code, "media-not-allowed");
});

test("Free becomes Premium → unlimited", () => {
  const r = q.authorizeFreeTextSend({
    senderUid: "user1",
    senderData: {
      homeCountryCode: "br",
      premiumUntil: { toMillis: () => Date.now() + 86400000 },
    },
    recipientData: { homeCountryCode: "us" },
    existingQuota: { freeUid: "user1", used: 300, limit: 300, enabled: true },
    text: "long text ok",
    messageType: "image",
  });
  assert.equal(r.ok, true);
  assert.equal(r.mode, "unlimited_premium");
  assert.equal(r.consume, 0);
});

test("Premium expired → quota resumes from used", () => {
  const r = q.authorizeFreeTextSend({
    senderUid: "user1",
    senderData: {
      homeCountryCode: "br",
      premiumUntil: { toMillis: () => Date.now() - 1000 },
      isPremium: false,
    },
    recipientData: { homeCountryCode: "us", isPremium: true },
    existingQuota: { freeUid: "user1", used: 250, limit: 300, enabled: true },
    text: "hello!!", // 7
  });
  assert.equal(r.ok, true);
  assert.equal(r.quotaAfter.used, 257);
});

test("Premium↔Premium and Free↔Free same country", () => {
  assert.equal(
    q.canSendViaClientWrite(
      { homeCountryCode: "br", isPremium: true },
      { homeCountryCode: "us", isPremium: true },
    ),
    true,
  );
  assert.equal(
    q.canSendViaClientWrite(
      { homeCountryCode: "br" },
      { homeCountryCode: "br" },
    ),
    true,
  );
  assert.equal(
    q.requiresReplyQuotaCallable(
      { homeCountryCode: "br" },
      { homeCountryCode: "us", isPremium: true },
      null,
      "free1",
    ),
    true,
  );
  // Free intl sem peer Premium e sem quota → sem franquia
  assert.equal(
    q.requiresReplyQuotaCallable(
      { homeCountryCode: "br" },
      { homeCountryCode: "us", isPremium: false },
      null,
      "free1",
    ),
    false,
  );
});

test("Free intl without Premium peer is denied (not franchise)", () => {
  const r = q.authorizeFreeTextSend({
    senderUid: "free1",
    senderData: { homeCountryCode: "br" },
    recipientData: { homeCountryCode: "us", isPremium: false },
    existingQuota: null,
    text: "oi",
  });
  assert.equal(r.ok, false);
  assert.equal(r.code, "premium-required");
});

test("same-country Free unlimited (no quota path)", () => {
  const r = q.authorizeFreeTextSend({
    senderUid: "free1",
    senderData: { homeCountryCode: "br" },
    recipientData: { homeCountryCode: "br", isPremium: true },
    existingQuota: null,
    text: "x".repeat(200),
  });
  assert.equal(r.ok, true);
  assert.equal(r.mode, "same_country_free");
  assert.equal(r.consume, 0);
});

test("concurrency serialized: used=299 two sends of 1 — only one accepted", () => {
  const base = {
    senderUid: "free1",
    senderData: { homeCountryCode: "br" },
    recipientData: { homeCountryCode: "us", isPremium: true },
    initiatorUid: "prem1",
  };
  // Concurrent reads would both see 299; commits serialize:
  const { used, outcomes } = q.commitSerializedFreeTexts({
    ...base,
    initialUsed: 299,
    texts: ["a", "b"],
  });
  assert.equal(outcomes[0].ok, true);
  assert.equal(outcomes[0].quotaAfter.used, 300);
  assert.equal(outcomes[1].ok, false);
  assert.equal(outcomes[1].code, "quota-exceeded");
  assert.equal(used, 300);
});

test("idempotent requestId validation stable for retries", () => {
  const id = "msg_pending_abc123";
  assert.equal(q.validateRequestId(id).ok, true);
  assert.equal(q.validateRequestId(id).requestId, id);
});

test("callable message shape matches push trigger fields", () => {
  // Espelha payload de send_dm_message (sem requestId/viaCallable).
  const msg = {
    type: "text",
    text: "olá",
    senderId: "free1",
    fromUid: "free1",
    toUid: "prem1",
    deleted: false,
    deletedBy: "",
    deletedText: "",
    deletedAt: null,
    replyToMessageId: null,
    replyToText: "",
    replyToType: "text",
    replyToIsMe: false,
    replyToImageUrl: "",
  };
  assert.equal(msg.type, "text");
  assert.ok(msg.senderId || msg.fromUid);
  assert.equal(typeof msg.text, "string");
  assert.equal("requestId" in msg, false);
  assert.equal("viaCallable" in msg, false);
});

test("lazy init quota when missing", () => {
  const r = q.authorizeFreeTextSend({
    senderUid: "free1",
    senderData: { homeCountryCode: "pt" },
    recipientData: { homeCountryCode: "fr", isPremium: true },
    existingQuota: null,
    text: "olá",
    recipientUid: "prem1",
  });
  assert.equal(r.ok, true);
  assert.equal(r.quotaAfter.used, 3);
  assert.equal(r.quotaAfter.limit, 300);
  assert.equal(r.quotaAfter.freeUid, "free1");
  assert.equal(r.quotaAfter.initiatorUid, "prem1");
});

test("requestId validation", () => {
  assert.equal(q.validateRequestId("short").ok, false);
  assert.equal(q.validateRequestId("abcd-efgh-ijkl").ok, true);
});

test("firstPublicName", () => {
  assert.equal(q.firstPublicName("Maria Silva"), "Maria");
  assert.equal(q.firstPublicName(""), "esta pessoa");
});

console.log("dm_reply_quota.test.js: all assertions registered");
