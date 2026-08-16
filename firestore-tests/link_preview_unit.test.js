/**
 * Link Preview — testes unitários puros (sem emulador, sem rede real).
 * DNS e fetch são mockados; Firestore é um fake em memória.
 */
const assert = require("assert");
const {
  normalizeHttpsUrl,
  isBlockedHostname,
  isPrivateOrBlockedIp,
  assertSafeResolvedAddresses,
  sanitizePreviewFields,
  parseHtmlMetadata,
  shouldUseCache,
  cacheKeyForUrl,
  evaluateRateLimit,
  isHtmlContentType,
  urlAppearsInMessageText,
  isMessageEligibleForPreview,
  isMessageAuthoredBy,
  MAX_REDIRECTS,
  CACHE_TTL_MS,
  RATE_LIMIT_UID_MAX,
  RATE_LIMIT_FETCH_MAX,
} = require("../functions/link_preview_logic");

const {
  createFetchLinkPreviewHandler,
} = require("../functions/link_preview");

class FakeHttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

// ---------------------------------------------------------------------------
// Fake Firestore — in-memory, supports collection/doc/get/set/update/runTransaction.
// ---------------------------------------------------------------------------
function makeFakeFirestore(seed = {}) {
  const store = new Map(Object.entries(seed));
  // All legacy positive fixtures represent adults; age-specific denial is
  // covered in social_age_guard.test.js.
  for (let i = 0; i <= 120; i++) {
    store.set(`users/u${i}`, { ageVerificationStatus: "verified" });
  }
  store.set("users/outsider", { ageVerificationStatus: "verified" });

  function docRef(path) {
    return {
      id: path.split("/").pop(),
      async get() {
        const data = store.get(path);
        return {
          exists: data !== undefined,
          id: path.split("/").pop(),
          data: () => (data === undefined ? undefined : { ...data }),
        };
      },
      async set(data, opts) {
        const existing = store.get(path) || {};
        const next = opts && opts.merge ? { ...existing, ...data } : { ...data };
        store.set(path, next);
        return next;
      },
      async update(data) {
        const existing = store.get(path);
        if (existing === undefined) {
          const err = new Error("not-found");
          err.code = "not-found";
          throw err;
        }
        store.set(path, { ...existing, ...data });
        return store.get(path);
      },
      collection(name) {
        return collectionRef(`${path}/${name}`);
      },
    };
  }

  function collectionRef(path) {
    return { doc: (id) => docRef(`${path}/${id}`) };
  }

  return {
    collection: (name) => collectionRef(name),
    async runTransaction(fn) {
      const tx = {
        get: (ref) => ref.get(),
        set: (ref, data, opts) => ref.set(data, opts),
        update: (ref, data) => ref.update(data),
      };
      return fn(tx);
    },
    _store: store,
  };
}

function makeAuth(uid) {
  return uid ? { uid } : null;
}

async function publicDnsLookup() {
  return [{ address: "93.184.216.34", family: 4 }];
}

function htmlFetch({ statusCode = 200, contentType = "text/html", body = "<html></html>", truncated = false, headers = {} } = {}) {
  return async () => ({
    statusCode,
    headers: { "content-type": contentType, ...headers },
    body,
    truncated,
  });
}

function makeHandler({ db, dnsLookup, fetchImpl }) {
  return createFetchLinkPreviewHandler({
    getFirestore: () => db || makeFakeFirestore(),
    getDnsLookup: () => dnsLookup || publicDnsLookup,
    fetchImpl: fetchImpl || htmlFetch(),
    HttpsError: FakeHttpsError,
  });
}

/** Seed a DM thread + owned message whose text contains `url`. */
function seedDm({ uid = "u1", other = "u2", cid = "c1", mid = "m1", url = "https://example.com/", extra = {} } = {}) {
  return {
    [`conversations/${cid}`]: { participants: [uid, other] },
    [`conversations/${cid}/messages/${mid}`]: {
      senderId: uid,
      text: `veja ${url} por favor`,
      createdAt: 1,
      replyTo: null,
      unread: { [other]: 1 },
      ...extra,
    },
  };
}

function seedGroup({ uid = "u1", gid = "g1", mid = "m1", url = "https://example.com/", extraMsg = {}, extraGroup = {} } = {}) {
  return {
    [`groups/${gid}`]: {
      members: [uid, "u2"],
      admins: [],
      ownerId: uid,
      ...extraGroup,
    },
    [`groups/${gid}/messages/${mid}`]: {
      senderId: uid,
      text: `veja ${url}`,
      createdAt: 1,
      ...extraMsg,
    },
  };
}

function call({ uid = "u1", url = "https://example.com/", messagePath = "conversations/c1/messages/m1" } = {}) {
  return { auth: makeAuth(uid), data: { url, messagePath } };
}

// ---------------------------------------------------------------------------
// Auth / ownership / membership
// ---------------------------------------------------------------------------
describe("fetchLinkPreview: auth e autorização", () => {
  it("rejeita sem autenticação", async () => {
    const handler = makeHandler({ db: makeFakeFirestore(seedDm()) });
    let threw = false;
    try {
      await handler({ auth: null, data: { url: "https://example.com/", messagePath: "conversations/c1/messages/m1" } });
    } catch (e) {
      threw = true;
      assert.strictEqual(e.code, "unauthenticated");
    }
    assert.ok(threw);
  });

  it("rejeita URL inválida com invalid-argument", async () => {
    const handler = makeHandler({ db: makeFakeFirestore(seedDm()) });
    let threw = false;
    try {
      await handler(call({ url: "not a url" }));
    } catch (e) {
      threw = true;
      assert.strictEqual(e.code, "invalid-argument");
    }
    assert.ok(threw);
  });

  it("exige messagePath", async () => {
    const handler = makeHandler({ db: makeFakeFirestore(seedDm()) });
    let threw = false;
    try {
      await handler({ auth: makeAuth("u1"), data: { url: "https://example.com/" } });
    } catch (e) {
      threw = true;
      assert.strictEqual(e.code, "invalid-argument");
    }
    assert.ok(threw);
  });

  it("rejeita messagePath fora do formato esperado", async () => {
    const handler = makeHandler({ db: makeFakeFirestore(seedDm()) });
    let threw = false;
    try {
      await handler(call({ messagePath: "conversations/c1/msgs/m1" }));
    } catch (e) {
      threw = true;
      assert.strictEqual(e.code, "invalid-argument");
    }
    assert.ok(threw);
  });

  it("exige participante no chat privado", async () => {
    const db = makeFakeFirestore(seedDm());
    const handler = makeHandler({ db });
    let threw = false;
    try {
      await handler(call({ uid: "outsider" }));
    } catch (e) {
      threw = true;
      assert.strictEqual(e.code, "permission-denied");
    }
    assert.ok(threw);
  });

  it("exige membro no grupo", async () => {
    const db = makeFakeFirestore(seedGroup());
    const handler = makeHandler({ db });
    let threw = false;
    try {
      await handler(call({ uid: "outsider", messagePath: "groups/g1/messages/m1" }));
    } catch (e) {
      threw = true;
      assert.strictEqual(e.code, "permission-denied");
    }
    assert.ok(threw);
  });

  it("rejeita membro banido (bannedUsers.isActive)", async () => {
    const seed = {
      ...seedGroup({ uid: "u1" }),
      "groups/g1/bannedUsers/u1": { isActive: true },
    };
    // Keep u1 as member but banned (stale membership edge case).
    seed["groups/g1"].members = ["u1", "u2"];
    const db = makeFakeFirestore(seed);
    const handler = makeHandler({ db });
    let threw = false;
    try {
      await handler(call({ uid: "u1", messagePath: "groups/g1/messages/m1" }));
    } catch (e) {
      threw = true;
      assert.strictEqual(e.code, "permission-denied");
    }
    assert.ok(threw);
  });

  it("só o autor da mensagem pode anexar prévia", async () => {
    const db = makeFakeFirestore(seedDm({ uid: "u1" }));
    // u2 is participant but not author
    const handler = makeHandler({ db });
    let threw = false;
    try {
      await handler(call({ uid: "u2" }));
    } catch (e) {
      threw = true;
      assert.strictEqual(e.code, "permission-denied");
    }
    assert.ok(threw);
  });

  it("URL processada deve existir no texto da mensagem", async () => {
    const db = makeFakeFirestore(seedDm({ url: "https://example.com/a" }));
    const handler = makeHandler({ db });
    let threw = false;
    try {
      await handler(call({ url: "https://evil.example/other" }));
    } catch (e) {
      threw = true;
      assert.strictEqual(e.code, "invalid-argument");
    }
    assert.ok(threw);
  });

  it("mensagem apagada (deleted) não recebe prévia", async () => {
    const db = makeFakeFirestore(seedDm({ extra: { deleted: true } }));
    const handler = makeHandler({ db, fetchImpl: htmlFetch() });
    let threw = false;
    try {
      await handler(call());
    } catch (e) {
      threw = true;
      assert.strictEqual(e.code, "failed-precondition");
    }
    assert.ok(threw);
  });

  it("mensagem ocultada (hiddenFor / deletedFor) não recebe prévia", async () => {
    const db = makeFakeFirestore(seedDm({ extra: { hiddenFor: ["u1"] } }));
    const handler = makeHandler({ db });
    let threw = false;
    try {
      await handler(call());
    } catch (e) {
      threw = true;
      assert.strictEqual(e.code, "failed-precondition");
    }
    assert.ok(threw);

    const db2 = makeFakeFirestore(seedDm({ mid: "m2", extra: { deletedFor: ["u1"] } }));
    const handler2 = makeHandler({ db: db2 });
    threw = false;
    try {
      await handler2(call({ messagePath: "conversations/c1/messages/m2" }));
    } catch (e) {
      threw = true;
      assert.strictEqual(e.code, "failed-precondition");
    }
    assert.ok(threw);
  });

  it("participante autor autorizado recebe linkPreviewStatus ready; outros campos intactos", async () => {
    const db = makeFakeFirestore(seedDm());
    const before = { ...db._store.get("conversations/c1/messages/m1") };
    const handler = makeHandler({
      db,
      fetchImpl: htmlFetch({ body: "<html><head><title>Hi</title></head></html>" }),
    });
    const res = await handler(call());
    assert.strictEqual(res.status, "ready");
    const msg = db._store.get("conversations/c1/messages/m1");
    assert.strictEqual(msg.linkPreviewStatus, "ready");
    assert.ok(msg.linkPreview);
    assert.strictEqual(msg.text, before.text);
    assert.strictEqual(msg.senderId, before.senderId);
    assert.strictEqual(msg.createdAt, before.createdAt);
    assert.strictEqual(msg.replyTo, before.replyTo);
    assert.deepStrictEqual(msg.unread, before.unread);
  });
});

describe("helpers de mensagem / URL no texto", () => {
  it("urlAppearsInMessageText normaliza https e bare domains", () => {
    assert.strictEqual(
      urlAppearsInMessageText("veja https://example.com/a", "https://example.com/a"),
      true
    );
    assert.strictEqual(
      urlAppearsInMessageText("veja example.com/a aqui", "https://example.com/a"),
      true
    );
    assert.strictEqual(
      urlAppearsInMessageText("sem link", "https://example.com/a"),
      false
    );
  });

  it("isMessageAuthoredBy / isMessageEligibleForPreview", () => {
    assert.strictEqual(isMessageAuthoredBy({ senderId: "u1" }, "u1"), true);
    assert.strictEqual(isMessageAuthoredBy({ fromUid: "u1" }, "u1"), true);
    assert.strictEqual(isMessageAuthoredBy({ senderId: "u2" }, "u1"), false);
    assert.strictEqual(isMessageEligibleForPreview({ deleted: true }, "u1"), false);
    assert.strictEqual(isMessageEligibleForPreview({ hiddenFor: ["u1"] }, "u1"), false);
    assert.strictEqual(isMessageEligibleForPreview({ text: "ok" }, "u1"), true);
  });
});

// ---------------------------------------------------------------------------
// Rate limit
// ---------------------------------------------------------------------------
describe("fetchLinkPreview: rate limit", () => {
  it("bloqueia após RATE_LIMIT_UID_MAX chamadas/min por uid", async () => {
    const seed = { "conversations/c1": { participants: ["u1", "u2"] } };
    for (let i = 0; i <= RATE_LIMIT_UID_MAX; i++) {
      const url = `https://example.com/${i}`;
      seed[`conversations/c1/messages/m${i}`] = {
        senderId: "u1",
        text: url,
      };
    }
    const db = makeFakeFirestore(seed);
    const handler = makeHandler({ db, fetchImpl: htmlFetch() });

    for (let i = 0; i < RATE_LIMIT_UID_MAX; i++) {
      const url = `https://example.com/${i}`;
      const res = await handler(call({ url, messagePath: `conversations/c1/messages/m${i}` }));
      assert.strictEqual(res.status, "ready");
    }

    let threw = false;
    try {
      await handler(
        call({
          url: `https://example.com/${RATE_LIMIT_UID_MAX}`,
          messagePath: `conversations/c1/messages/m${RATE_LIMIT_UID_MAX}`,
        })
      );
    } catch (e) {
      threw = true;
      assert.strictEqual(e.code, "resource-exhausted");
    }
    assert.ok(threw);
  });

  it("NÃO bloqueia URLs populares por limite global — cache serve muitos uids", async () => {
    const sameUrl = "https://www.amazon.com/dp/B00POPULAR";
    const seed = {};
    const n = 40;
    for (let i = 0; i < n; i++) {
      seed[`conversations/c${i}`] = { participants: [`u${i}`, "other"] };
      seed[`conversations/c${i}/messages/m1`] = {
        senderId: `u${i}`,
        text: sameUrl,
      };
    }
    const db = makeFakeFirestore(seed);
    let fetchCalls = 0;
    const handler = makeHandler({
      db,
      fetchImpl: async (...args) => {
        fetchCalls += 1;
        return htmlFetch({
          body: "<html><head><title>Amazon Product</title></head></html>",
        })(...args);
      },
    });

    for (let i = 0; i < n; i++) {
      const res = await handler(
        call({
          uid: `u${i}`,
          url: sameUrl,
          messagePath: `conversations/c${i}/messages/m1`,
        })
      );
      assert.strictEqual(res.status, "ready");
    }
    assert.strictEqual(fetchCalls, 1, "só a 1ª chamada deve buscar na rede");
  });

  it("limita fetches por (uid,url) no cache miss", async () => {
    const url = "https://example.com/fetch-limit";
    const seed = { "conversations/c1": { participants: ["u1", "u2"] } };
    for (let i = 0; i <= RATE_LIMIT_FETCH_MAX; i++) {
      seed[`conversations/c1/messages/m${i}`] = { senderId: "u1", text: url };
    }
    const db = makeFakeFirestore(seed);
    const handler = makeHandler({ db, fetchImpl: htmlFetch() });

    for (let i = 0; i < RATE_LIMIT_FETCH_MAX; i++) {
      // Force miss by clearing cache between calls
      for (const key of [...db._store.keys()]) {
        if (key.startsWith("linkPreviewCache/")) db._store.delete(key);
      }
      const res = await handler(call({ url, messagePath: `conversations/c1/messages/m${i}` }));
      assert.strictEqual(res.status, "ready");
    }

    for (const key of [...db._store.keys()]) {
      if (key.startsWith("linkPreviewCache/")) db._store.delete(key);
    }
    let threw = false;
    try {
      await handler(
        call({
          url,
          messagePath: `conversations/c1/messages/m${RATE_LIMIT_FETCH_MAX}`,
        })
      );
    } catch (e) {
      threw = true;
      assert.strictEqual(e.code, "resource-exhausted");
    }
    assert.ok(threw);
  });

  it("evaluateRateLimit reseta a janela após windowMs", () => {
    const now0 = 1_000_000;
    const first = evaluateRateLimit({ windowStartMs: undefined, count: 0, nowMs: now0, max: 2, windowMs: 60000 });
    assert.strictEqual(first.allowed, true);
    const second = evaluateRateLimit({ ...first.next, nowMs: now0 + 1000, max: 2, windowMs: 60000 });
    assert.strictEqual(second.allowed, true);
    const third = evaluateRateLimit({ ...second.next, nowMs: now0 + 2000, max: 2, windowMs: 60000 });
    assert.strictEqual(third.allowed, false);
    const afterWindow = evaluateRateLimit({ ...third.next, nowMs: now0 + 61000, max: 2, windowMs: 60000 });
    assert.strictEqual(afterWindow.allowed, true);
    assert.strictEqual(afterWindow.next.count, 1);
  });
});

// ---------------------------------------------------------------------------
// Cache hit / miss
// ---------------------------------------------------------------------------
describe("fetchLinkPreview: cache", () => {
  it("cache miss busca na rede; cache hit não chama fetchImpl de novo", async () => {
    const sameUrl = "https://example.com/cache";
    const db = makeFakeFirestore({
      ...seedDm({ uid: "u1", cid: "c1", url: sameUrl }),
      ...seedDm({ uid: "u2", other: "u1", cid: "c2", url: sameUrl }),
    });
    let fetchCalls = 0;
    const fetchImpl = async (...args) => {
      fetchCalls += 1;
      return htmlFetch({ body: "<html><head><title>Cached Page</title></head></html>" })(...args);
    };
    const handler = makeHandler({ db, fetchImpl });

    const first = await handler(call({ uid: "u1", url: sameUrl, messagePath: "conversations/c1/messages/m1" }));
    assert.strictEqual(first.cached, false);
    assert.strictEqual(fetchCalls, 1);

    const second = await handler(call({ uid: "u2", url: sameUrl, messagePath: "conversations/c2/messages/m1" }));
    assert.strictEqual(second.cached, true);
    assert.strictEqual(fetchCalls, 1, "não deveria buscar de novo");
    assert.deepStrictEqual(second.preview, first.preview);
  });

  it("shouldUseCache: TTL expirado é tratado como miss", () => {
    const now = Date.now();
    const fresh = { status: "ready", preview: { title: "x" }, fetchedAtMs: now - 1000 };
    const stale = { status: "ready", preview: { title: "x" }, fetchedAtMs: now - CACHE_TTL_MS - 1000 };
    assert.strictEqual(shouldUseCache(fresh, now, CACHE_TTL_MS), true);
    assert.strictEqual(shouldUseCache(stale, now, CACHE_TTL_MS), false);
    assert.strictEqual(shouldUseCache(null, now, CACHE_TTL_MS), false);
    assert.strictEqual(shouldUseCache({ status: "failed" }, now, CACHE_TTL_MS), false);
  });

  it("cacheKeyForUrl é estável e determinístico", () => {
    const k1 = cacheKeyForUrl("https://example.com/a");
    const k2 = cacheKeyForUrl("https://example.com/a");
    const k3 = cacheKeyForUrl("https://example.com/b");
    assert.strictEqual(k1, k2);
    assert.notStrictEqual(k1, k3);
    assert.ok(/^[a-f0-9]{64}$/.test(k1));
  });
});

// ---------------------------------------------------------------------------
// Timeout / max bytes / redirects / Amazon
// ---------------------------------------------------------------------------
describe("fetchLinkPreview: rede — timeout, tamanho, redirecionamentos", () => {
  it("timeout do fetchImpl vira falha suave (não lança)", async () => {
    const url = "https://example.com/slow";
    const handler = makeHandler({
      db: makeFakeFirestore(seedDm({ url })),
      fetchImpl: async () => {
        const err = new Error("timeout");
        err.code = "timeout";
        throw err;
      },
    });
    const res = await handler(call({ url }));
    assert.strictEqual(res.status, "failed");
    assert.strictEqual(res.preview, null);
  });

  it("corpo além de MAX_BYTES vira falha suave", async () => {
    const url = "https://example.com/big";
    const handler = makeHandler({
      db: makeFakeFirestore(seedDm({ url })),
      fetchImpl: htmlFetch({ truncated: true }),
    });
    const res = await handler(call({ url }));
    assert.strictEqual(res.status, "failed");
  });

  it("segue até MAX_REDIRECTS e então busca com sucesso", async () => {
    let calls = 0;
    const url = "https://example.com/start";
    const fetchImpl = async () => {
      calls += 1;
      if (calls <= MAX_REDIRECTS) {
        return {
          statusCode: 302,
          headers: { location: `https://example.com/hop${calls}` },
          body: "",
          truncated: false,
        };
      }
      return {
        statusCode: 200,
        headers: { "content-type": "text/html" },
        body: "<html><head><title>Final</title></head></html>",
        truncated: false,
      };
    };
    const handler = makeHandler({ db: makeFakeFirestore(seedDm({ url })), fetchImpl });
    const res = await handler(call({ url }));
    assert.strictEqual(res.status, "ready");
    assert.strictEqual(calls, MAX_REDIRECTS + 1);
  });

  it("excede MAX_REDIRECTS: falha suave", async () => {
    const url = "https://example.com/loop";
    const fetchImpl = async () => ({
      statusCode: 302,
      headers: { location: "https://example.com/loop" },
      body: "",
      truncated: false,
    });
    const handler = makeHandler({ db: makeFakeFirestore(seedDm({ url })), fetchImpl });
    const res = await handler(call({ url }));
    assert.strictEqual(res.status, "failed");
  });

  it("segue redirects estilo Amazon amzn.to → amazon.com (encurtado)", async () => {
    const shortUrl = "https://amzn.to/3AbCdEf";
    let hop = 0;
    const fetchImpl = async ({ url }) => {
      hop += 1;
      if (String(url).includes("amzn.to")) {
        return {
          statusCode: 301,
          headers: { location: "https://www.amazon.com/dp/B00TEST?tag=remdy-20" },
          body: "",
          truncated: false,
        };
      }
      if (String(url).includes("tag=remdy-20")) {
        return {
          statusCode: 302,
          headers: { location: "https://www.amazon.com/dp/B00TEST" },
          body: "",
          truncated: false,
        };
      }
      return {
        statusCode: 200,
        headers: { "content-type": "text/html" },
        body: '<html><head><meta property="og:title" content="Amazon Product"></head></html>',
        truncated: false,
      };
    };
    const handler = makeHandler({
      db: makeFakeFirestore(seedDm({ url: shortUrl })),
      fetchImpl,
    });
    const res = await handler(call({ url: shortUrl }));
    assert.strictEqual(res.status, "ready");
    assert.strictEqual(res.preview.title, "Amazon Product");
    assert.ok(hop >= 3);
  });

  it("segue a.co (Amazon short) com vários hops sem falhar injustamente", async () => {
    const shortUrl = "https://a.co/d/xyz123";
    let hop = 0;
    const fetchImpl = async ({ url }) => {
      hop += 1;
      if (String(url).includes("a.co")) {
        return {
          statusCode: 302,
          headers: { location: "https://www.amazon.com/gp/product/B00ACO?ref=xx" },
          body: "",
          truncated: false,
        };
      }
      if (String(url).includes("ref=xx")) {
        return {
          statusCode: 301,
          headers: { location: "https://www.amazon.com/dp/B00ACO" },
          body: "",
          truncated: false,
        };
      }
      return htmlFetch({
        body: '<html><head><meta property="og:title" content="A.co Product"></head></html>',
      })();
    };
    const handler = makeHandler({
      db: makeFakeFirestore(seedDm({ url: shortUrl })),
      fetchImpl,
    });
    const res = await handler(call({ url: shortUrl }));
    assert.strictEqual(res.status, "ready");
    assert.strictEqual(res.preview.title, "A.co Product");
    assert.ok(hop >= 3);
    assert.ok(hop <= MAX_REDIRECTS + 1);
  });
});

// ---------------------------------------------------------------------------
// SSRF: localhost, IPv4/IPv6 privado, metadata, DNS rebinding
// ---------------------------------------------------------------------------
describe("SSRF guards", () => {
  it("bloqueia localhost sem nunca chamar DNS", async () => {
    let dnsCalls = 0;
    const url = "https://localhost/";
    const handler = makeHandler({
      db: makeFakeFirestore(seedDm({ url })),
      dnsLookup: async () => {
        dnsCalls += 1;
        return [{ address: "93.184.216.34", family: 4 }];
      },
    });
    const res = await handler(call({ url }));
    assert.strictEqual(res.status, "failed");
    assert.strictEqual(dnsCalls, 0);
    assert.strictEqual(isBlockedHostname("localhost"), true);
    assert.strictEqual(isBlockedHostname("foo.localhost"), true);
  });

  it("bloqueia IPv4 privado direto na URL", async () => {
    assert.strictEqual(isPrivateOrBlockedIp("10.0.0.5"), true);
    assert.strictEqual(isPrivateOrBlockedIp("192.168.1.1"), true);
    assert.strictEqual(isPrivateOrBlockedIp("172.16.5.5"), true);
    assert.strictEqual(isPrivateOrBlockedIp("8.8.8.8"), false);

    const url = "https://10.0.0.5/";
    const handler = makeHandler({ db: makeFakeFirestore(seedDm({ url })) });
    const res = await handler(call({ url }));
    assert.strictEqual(res.status, "failed");
  });

  it("bloqueia IPv6 privado/loopback/unique-local", () => {
    assert.strictEqual(isPrivateOrBlockedIp("::1"), true);
    assert.strictEqual(isPrivateOrBlockedIp("fe80::1"), true);
    assert.strictEqual(isPrivateOrBlockedIp("fc00::1"), true);
    assert.strictEqual(isPrivateOrBlockedIp("fd12:3456:789a::1"), true);
    assert.strictEqual(isPrivateOrBlockedIp("2001:4860:4860::8888"), false);
  });

  it("bloqueia IP de metadata em nuvem (169.254.169.254)", async () => {
    assert.strictEqual(isPrivateOrBlockedIp("169.254.169.254"), true);
    const url = "https://169.254.169.254/latest/meta-data/";
    const handler = makeHandler({ db: makeFakeFirestore(seedDm({ url })) });
    const res = await handler(call({ url }));
    assert.strictEqual(res.status, "failed");
  });

  it("bloqueia CGNAT 100.64.0.0/10", () => {
    assert.strictEqual(isPrivateOrBlockedIp("100.64.0.1"), true);
    assert.strictEqual(isPrivateOrBlockedIp("100.127.255.255"), true);
    assert.strictEqual(isPrivateOrBlockedIp("100.63.255.255"), false);
  });

  it("DNS rebinding: IP passa a ser privado no redirecionamento -> falha", async () => {
    let lookupCall = 0;
    const url = "https://rebind.example.com/start";
    const dnsLookup = async () => {
      lookupCall += 1;
      if (lookupCall === 1) return [{ address: "93.184.216.34", family: 4 }];
      return [{ address: "127.0.0.1", family: 4 }];
    };
    const fetchImpl = async () => ({
      statusCode: 302,
      headers: { location: "https://rebind.example.com/after" },
      body: "",
      truncated: false,
    });
    const handler = makeHandler({
      db: makeFakeFirestore(seedDm({ url })),
      dnsLookup,
      fetchImpl,
    });
    const res = await handler(call({ url }));
    assert.strictEqual(res.status, "failed");
    assert.ok(lookupCall >= 2, "deve reconsultar DNS a cada hop");
  });

  it("assertSafeResolvedAddresses lança se qualquer endereço resolvido for bloqueado", () => {
    assert.throws(() => assertSafeResolvedAddresses([{ address: "8.8.8.8" }, { address: "127.0.0.1" }]));
    assert.doesNotThrow(() => assertSafeResolvedAddresses([{ address: "8.8.8.8" }, { address: "1.1.1.1" }]));
    assert.throws(() => assertSafeResolvedAddresses([]));
  });
});

// ---------------------------------------------------------------------------
// HTML parsing / sanitização
// ---------------------------------------------------------------------------
describe("parseHtmlMetadata", () => {
  it("extrai og:*, twitter:*, title e description", () => {
    const html = `
      <html><head>
        <title>Fallback Title</title>
        <meta name="description" content="Fallback description">
        <meta property="og:title" content="OG Title">
        <meta property="og:description" content="OG Description">
        <meta property="og:image" content="https://cdn.example.com/img.png">
        <meta name="twitter:title" content="Twitter Title">
      </head></html>`;
    const meta = parseHtmlMetadata(html);
    assert.strictEqual(meta.title, "OG Title");
    assert.strictEqual(meta.description, "OG Description");
    assert.strictEqual(meta.imageUrl, "https://cdn.example.com/img.png");
  });

  it("usa fallbacks quando og:* ausente", () => {
    const html = `<html><head><title>Only Title</title><meta name="twitter:description" content="Twitter Desc"></head></html>`;
    const meta = parseHtmlMetadata(html);
    assert.strictEqual(meta.title, "Only Title");
    assert.strictEqual(meta.description, "Twitter Desc");
  });

  it("HTML malformado não lança e retorna campos vazios", () => {
    const inputs = [
      "",
      "<html",
      "<meta property=og:title content=Unquoted>",
      "<<<>>>garbage<<<meta",
      null,
      undefined,
      "<title>Unterminated",
    ];
    for (const html of inputs) {
      assert.doesNotThrow(() => parseHtmlMetadata(html));
      const meta = parseHtmlMetadata(html);
      assert.strictEqual(typeof meta.title, "string");
      assert.strictEqual(typeof meta.description, "string");
      assert.strictEqual(typeof meta.imageUrl, "string");
    }
  });
});

describe("sanitizePreviewFields", () => {
  it("aplica limites de tamanho por campo", () => {
    const out = sanitizePreviewFields({
      title: "T".repeat(500),
      description: "D".repeat(500),
      domain: "d".repeat(500),
      url: "https://example.com/" + "a".repeat(3000),
      imageUrl: "https://example.com/" + "i".repeat(3000),
    });
    assert.ok(out.title.length <= 120);
    assert.ok(out.description.length <= 240);
    assert.ok(out.domain.length <= 120);
    assert.ok(out.url.length <= 2048);
    assert.ok(out.imageUrl.length <= 2048);
  });

  it("remove caracteres de controle", () => {
    const out = sanitizePreviewFields({
      title: "Hello\x00\x07World\x1F",
      description: "Line1\nLine2\tTabbed",
      domain: "example.com",
      url: "https://example.com/",
      imageUrl: "",
    });
    assert.ok(!/[\x00-\x1F\x7F]/.test(out.title));
    assert.ok(!/[\x00-\x1F\x7F]/.test(out.description));
  });

  it("descarta imageUrl insegura (http, javascript:, vazio)", () => {
    assert.strictEqual(
      sanitizePreviewFields({ imageUrl: "http://insecure.example/img.png" }).imageUrl,
      ""
    );
    assert.strictEqual(
      sanitizePreviewFields({ imageUrl: "javascript:alert(1)" }).imageUrl,
      ""
    );
    assert.strictEqual(sanitizePreviewFields({ imageUrl: "" }).imageUrl, "");
    assert.strictEqual(
      sanitizePreviewFields({ imageUrl: "https://cdn.example.com/a.png" }).imageUrl,
      "https://cdn.example.com/a.png"
    );
  });
});

describe("isHtmlContentType / non-HTML content-type end-to-end", () => {
  it("aceita text/html e application/xhtml+xml; rejeita outros", () => {
    assert.strictEqual(isHtmlContentType("text/html"), true);
    assert.strictEqual(isHtmlContentType("text/html; charset=utf-8"), true);
    assert.strictEqual(isHtmlContentType("application/xhtml+xml"), true);
    assert.strictEqual(isHtmlContentType("application/json"), false);
    assert.strictEqual(isHtmlContentType("image/png"), false);
    assert.strictEqual(isHtmlContentType(""), false);
    assert.strictEqual(isHtmlContentType(null), false);
  });

  it("resposta non-HTML vira falha suave no handler", async () => {
    const url = "https://example.com/api";
    const handler = makeHandler({
      db: makeFakeFirestore(seedDm({ url })),
      fetchImpl: htmlFetch({ contentType: "application/json", body: "{}" }),
    });
    const res = await handler(call({ url }));
    assert.strictEqual(res.status, "failed");
  });
});

describe("payload retornado é sempre sanitizado", () => {
  it("preview final não tem campos extras nem excede limites", async () => {
    const url = "https://example.com/page";
    const html = `<html><head>
      <meta property="og:title" content="${"X".repeat(300)}">
      <meta property="og:description" content="${"Y".repeat(400)}">
      <meta property="og:image" content="https://cdn.example.com/${"z".repeat(2100)}.png">
    </head></html>`;
    const handler = makeHandler({
      db: makeFakeFirestore(seedDm({ url })),
      fetchImpl: htmlFetch({ body: html }),
    });
    const res = await handler(call({ url }));
    assert.strictEqual(res.status, "ready");
    const { preview } = res;
    assert.ok(preview.title.length <= 120);
    assert.ok(preview.description.length <= 240);
    assert.ok(preview.imageUrl.length <= 2048 || preview.imageUrl === "");
    assert.deepStrictEqual(
      Object.keys(preview).sort(),
      ["description", "domain", "fetchedAt", "imageUrl", "title", "url"].sort()
    );
  });
});

describe("normalizeHttpsUrl", () => {
  it("aceita apenas https e remove credenciais", () => {
    assert.strictEqual(
      normalizeHttpsUrl("https://user:pass@example.com/a"),
      "https://example.com/a"
    );
  });

  it("rejeita esquemas perigosos", () => {
    for (const bad of ["http://example.com", "javascript:alert(1)", "ftp://example.com", "file:///etc/passwd", "data:text/html,x"]) {
      assert.throws(() => normalizeHttpsUrl(bad));
    }
  });

  it("rejeita entradas não-string ou vazias", () => {
    assert.throws(() => normalizeHttpsUrl(null));
    assert.throws(() => normalizeHttpsUrl(""));
    assert.throws(() => normalizeHttpsUrl("   "));
    assert.throws(() => normalizeHttpsUrl(123));
  });
});
