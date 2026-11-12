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
  shouldIncludeSharePerson,
  collectGroupMemberUids,
  mergeSharePeople,
  pairKey,
  SHARE_PEOPLE_CAP,
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
  assert.equal(
    canSendInternational({ countryCode: "br" }, { countryCode: "ca" }),
    true,
  );
  assert.equal(
    canSendInternational({ homeCountryCode: "PT" }, { countryCode: "BR" }),
    true,
  );
  assert.equal(
    canSendInternational({ countryCode: "ca" }, { countryCode: "pt" }),
    true,
  );
  assert.equal(
    canSendInternational({ countryCode: "us" }, { countryCode: "us" }),
    true,
  );
  assert.equal(
    canSendInternational({ countryCode: "us" }, { countryCode: "ca" }),
    false,
  );
  assert.equal(
    canSendInternational({ countryCode: "us", isPremium: true }, { countryCode: "ca" }),
    true,
  );
  assert.equal(
    canSendInternational({ countryCode: "br" }, { countryCode: "" }),
    false,
  );
});

test("pairKey is deterministic", () => {
  assert.equal(pairKey("b", "a"), "a_b");
  assert.equal(pairKey("a", "b"), "a_b");
});

test("collectGroupMemberUids dedupes and excludes self", () => {
  const uids = collectGroupMemberUids(
    [
      { data: { members: ["me", "u1", "u2"], ownerId: "me", admins: ["u1"] } },
      { members: ["u2", "u3"], ownerId: "u4" },
    ],
    "me",
  );
  assert.deepEqual(uids, ["u1", "u2", "u3", "u4"]);
});

test("shouldIncludeSharePerson filters self, blocked, hidden, banned, exploreOnly", () => {
  assert.equal(
    shouldIncludeSharePerson({ uid: "me", otherUid: "me", otherData: {} }),
    false,
  );
  assert.equal(
    shouldIncludeSharePerson({
      uid: "me",
      otherUid: "u1",
      otherData: {},
      blocked: true,
    }),
    false,
  );
  assert.equal(
    shouldIncludeSharePerson({
      uid: "me",
      otherUid: "u1",
      otherData: { hiddenFromLists: true },
    }),
    false,
  );
  assert.equal(
    shouldIncludeSharePerson({
      uid: "me",
      otherUid: "u1",
      otherData: { isBanned: true },
    }),
    false,
  );
  assert.equal(
    shouldIncludeSharePerson({
      uid: "me",
      otherUid: "u1",
      otherData: { exploreOnly: true },
      isContact: false,
    }),
    false,
  );
  assert.equal(
    shouldIncludeSharePerson({
      uid: "me",
      otherUid: "u1",
      otherData: { exploreOnly: true },
      isContact: true,
    }),
    true,
  );
  assert.equal(
    shouldIncludeSharePerson({
      uid: "me",
      otherUid: "u1",
      otherData: {},
    }),
    true,
  );
});

test("mergeSharePeople orders DMs first, then group members, then search, and caps", () => {
  const conversations = [
    { otherUid: "a", origin: "conversation" },
    { otherUid: "b", origin: "conversation" },
  ];
  const groupMembers = [
    { otherUid: "b", origin: "group_member" },
    { otherUid: "c", origin: "group_member" },
    { otherUid: "d", origin: "group_member" },
  ];
  const searchHits = [
    { otherUid: "c", origin: "search" },
    { otherUid: "e", origin: "search" },
  ];
  const merged = mergeSharePeople({
    conversations,
    groupMembers,
    searchHits,
    cap: 4,
  });
  assert.deepEqual(
    merged.map((x) => x.otherUid),
    ["a", "b", "c", "d"],
  );
  const full = mergeSharePeople({ conversations, groupMembers, searchHits });
  assert.deepEqual(
    full.map((x) => x.otherUid),
    ["a", "b", "c", "d", "e"],
  );
  assert.equal(SHARE_PEOPLE_CAP, 50);
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
