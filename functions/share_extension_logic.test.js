const test = require("node:test");
const assert = require("node:assert/strict");
const {
  hashToken,
  generateOpaqueToken,
  normalizeShareText,
  containsPhone,
  canSendInternational,
  isPremiumUser,
  isExpired,
  shouldRenew,
  SESSION_TTL_MS,
  evaluateRateLimit,
  accountBlocked,
} = require("./share_extension_logic");

test("hashToken is stable sha256 hex", () => {
  const a = hashToken("abc");
  const b = hashToken("abc");
  assert.equal(a, b);
  assert.equal(a.length, 64);
  assert.notEqual(hashToken("abc"), hashToken("abcd"));
});

test("generateOpaqueToken is long enough", () => {
  const t = generateOpaqueToken();
  assert.ok(t.length >= 40);
});

test("normalizeShareText accepts https and rejects http/js/file", () => {
  assert.equal(normalizeShareText("hello").ok, true);
  assert.equal(
    normalizeShareText("see https://example.com/x").ok,
    true,
  );
  assert.equal(normalizeShareText("http://example.com").ok, false);
  assert.equal(normalizeShareText("javascript:alert(1)").ok, false);
  assert.equal(normalizeShareText("").ok, false);
});

test("containsPhone detects sequences", () => {
  assert.equal(containsPhone("call +55 11"), true);
  assert.equal(containsPhone("hello world"), false);
});

test("premium / international", () => {
  assert.equal(isPremiumUser({ isMaster: true }), true);
  assert.equal(
    canSendInternational(
      { countryCode: "br" },
      { countryCode: "us" },
    ),
    false,
  );
  assert.equal(
    canSendInternational(
      { countryCode: "br", isMaster: true },
      { countryCode: "us" },
    ),
    true,
  );
});

test("session expiry helpers", () => {
  const now = Date.now();
  assert.equal(isExpired(now - 1, now), true);
  assert.equal(isExpired(now + SESSION_TTL_MS, now), false);
  assert.equal(shouldRenew(now + SESSION_TTL_MS * 0.4, now), true);
  assert.equal(shouldRenew(now + SESSION_TTL_MS * 0.8, now), false);
});

test("rate limit window", () => {
  const now = 1_000_000;
  const first = evaluateRateLimit({}, now, 2, 60_000);
  assert.equal(first.allowed, true);
  assert.equal(first.count, 1);
  const second = evaluateRateLimit(first, now + 1000, 2, 60_000);
  assert.equal(second.allowed, true);
  const third = evaluateRateLimit(second, now + 2000, 2, 60_000);
  assert.equal(third.allowed, false);
});

test("accountBlocked", () => {
  assert.equal(accountBlocked({}), null);
  assert.equal(accountBlocked({ isBanned: true }), "banned");
  assert.equal(accountBlocked({ shadowBan: true }), "shadow_ban");
});
