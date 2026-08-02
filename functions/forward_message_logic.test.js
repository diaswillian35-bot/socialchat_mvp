const test = require("node:test");
const assert = require("node:assert/strict");
const {
  normalizeDestinations,
  extractForwardableContent,
  callerCanReadMessage,
  isReusableMediaUrl,
  sanitizeLinkPreview,
  canSendInternational,
  MAX_DESTINATIONS,
} = require("./forward_message_logic");

test("normalizeDestinations enforces limit and dedupes", () => {
  const tooMany = Array.from({ length: MAX_DESTINATIONS + 1 }, (_, i) => ({
    kind: "group",
    groupId: `g${i}`,
  }));
  assert.equal(normalizeDestinations(tooMany).ok, false);
  const ok = normalizeDestinations([
    { kind: "dm", conversationId: "c1" },
    { kind: "dm", conversationId: "c1" },
    { kind: "group", groupId: "g1" },
  ]);
  assert.equal(ok.ok, true);
  assert.equal(ok.destinations.length, 2);
});

test("extractForwardableContent rejects deleted and bad media", () => {
  assert.equal(extractForwardableContent({ deleted: true, type: "text", text: "a" }).ok, false);
  assert.equal(
    extractForwardableContent({ type: "text", text: "hello" }).ok,
    true,
  );
  assert.equal(
    extractForwardableContent({
      type: "image",
      imageUrl: "file:///tmp/x.jpg",
    }).ok,
    false,
  );
  assert.equal(
    extractForwardableContent({
      type: "image",
      imageUrl:
        "https://firebasestorage.googleapis.com/v0/b/x/o/y.jpg?alt=media",
    }).ok,
    true,
  );
  assert.equal(
    extractForwardableContent({
      type: "audio",
      audioUrl:
        "https://firebasestorage.googleapis.com/v0/b/x/o/a.m4a?alt=media",
      durationMs: 1200,
    }).ok,
    true,
  );
});

test("callerCanReadMessage respects hiddenFor/deletedFor", () => {
  assert.equal(
    callerCanReadMessage({ deleted: false, hiddenFor: ["u1"] }, "u1"),
    false,
  );
  assert.equal(
    callerCanReadMessage({ deleted: false, deletedFor: ["u1"] }, "u1"),
    false,
  );
  assert.equal(callerCanReadMessage({ deleted: false }, "u1"), true);
});

test("sanitizeLinkPreview keeps public https fields only", () => {
  assert.equal(sanitizeLinkPreview({ url: "http://x.com" }), null);
  const p = sanitizeLinkPreview({
    url: "https://example.com/a",
    title: "T",
    description: "D",
    domain: "example.com",
    imageUrl: "https://example.com/i.png",
    secret: "nope",
  });
  assert.equal(p.url, "https://example.com/a");
  assert.equal(p.secret, undefined);
  assert.equal(isReusableMediaUrl("https://storage.googleapis.com/x"), true);
});

test("international gate", () => {
  assert.equal(
    canSendInternational({ countryCode: "br" }, { countryCode: "us" }),
    false,
  );
  assert.equal(
    canSendInternational(
      { countryCode: "br", isPremium: true },
      { countryCode: "us" },
    ),
    true,
  );
});
