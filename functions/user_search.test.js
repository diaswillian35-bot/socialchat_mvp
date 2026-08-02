/**
 * Testes unitários — busca global segura.
 * Executar: node user_search.test.js
 */
const assert = require("assert");
const {
  normalizeSearchText,
  isQueryReady,
  clampLimit,
  resolveSearchType,
  searchFieldForType,
  isCountryCodeQuery,
  parseCursor,
  encodeCursor,
  isSearchableAccount,
  buildSafeResult,
  buildPublicSearchFields,
  computeFetchLimit,
  pageEligibleHits,
  createSearchUsersHandler,
  DEFAULT_PAGE_SIZE,
  MAX_PAGE_SIZE,
  MAX_PUBLIC_FETCH,
} = require("./user_search");

class FakeHttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

// ---- Normalização ----
assert.strictEqual(normalizeSearchText("MaRiA"), "maria");
assert.strictEqual(normalizeSearchText("  JOÃO  "), "joao");
assert.strictEqual(normalizeSearchText("José"), "jose");
assert.strictEqual(normalizeSearchText("Ação"), "acao");
assert.strictEqual(normalizeSearchText("François"), "francois");
assert.strictEqual(normalizeSearchText("Ñandú"), "nandu");
assert.strictEqual(normalizeSearchText("東京"), "東京"); // Unicode preservado
assert.strictEqual(isQueryReady("á"), false);
assert.strictEqual(isQueryReady("ab"), true);

// ---- Tipos whitelist ----
assert.strictEqual(resolveSearchType("name"), "name");
assert.strictEqual(resolveSearchType("city"), "city");
assert.strictEqual(resolveSearchType("region"), "region");
assert.strictEqual(resolveSearchType("country"), "country");
assert.strictEqual(resolveSearchType("email"), null);
assert.strictEqual(resolveSearchType("isBanned"), null);
assert.strictEqual(searchFieldForType("name"), "nameSearch");
assert.strictEqual(searchFieldForType("city"), "citySearch");
assert.strictEqual(searchFieldForType("region"), "regionSearch");
assert.strictEqual(searchFieldForType("country"), "countrySearch");
assert.strictEqual(isCountryCodeQuery("br"), true);
assert.strictEqual(isCountryCodeQuery("brasil"), false);

// ---- Cursor ----
assert.deepStrictEqual(encodeCursor("joao", "u1"), { v: "joao", id: "u1" });
assert.deepStrictEqual(parseCursor({ v: "joao", id: "u1" }), {
  v: "joao",
  id: "u1",
});
assert.strictEqual(parseCursor("joao"), null);
assert.strictEqual(parseCursor({ v: "x" }), null);
assert.strictEqual(parseCursor({ v: "x", id: "bad id!" }), null);

// ---- Conta invisível ----
assert.strictEqual(
  isSearchableAccount({ name: "Ana", profileComplete: true }),
  true
);
assert.strictEqual(
  isSearchableAccount({ name: "Ana", profileComplete: true, isBanned: true }),
  false
);
assert.strictEqual(
  isSearchableAccount({
    name: "Ana",
    profileComplete: true,
    accountDeleted: true,
  }),
  false
);
assert.strictEqual(
  isSearchableAccount({ name: "Ana", profileComplete: true, isActive: false }),
  false
);
assert.strictEqual(
  isSearchableAccount({ name: "Ana", profileComplete: false }),
  false
);

// ---- Privacidade ----
const safe = buildSafeResult("u1", {
  name: "Ana",
  photoUrl: "https://x/a.jpg",
  city: "Lisboa",
  state: "Lisboa",
  country: "Portugal",
  countryCode: "pt",
  email: "secret@x.com",
  isPremium: true,
  fcmToken: "tok",
  lat: -23.5,
  lng: -46.6,
  role: "admin",
});
assert.deepStrictEqual(Object.keys(safe).sort(), [
  "city",
  "country",
  "countryCode",
  "name",
  "photoUrl",
  "region",
  "uid",
]);
assert.strictEqual(safe.region, "Lisboa");
assert.ok(!("email" in safe));
assert.ok(!("lat" in safe));
assert.ok(!("isPremium" in safe));

// ---- Backfill fields (somente públicos) ----
const fields = buildPublicSearchFields({
  name: "José",
  city: "São Paulo",
  stateName: "São Paulo",
  country: "Brasil",
  countryCode: "BR",
  email: "x@x",
  isPremium: true,
});
assert.strictEqual(fields.nameSearch, "jose");
assert.strictEqual(fields.citySearch, "sao paulo");
assert.strictEqual(fields.regionSearch, "sao paulo");
assert.strictEqual(fields.countrySearch, "brasil");
assert.strictEqual(fields.countryCode, "br");
assert.ok(!("email" in fields));
assert.ok(!("isPremium" in fields));

// ---- Paginação sem pular/repetir (vários João) ----
function makeDocs(items) {
  return items.map((it) => ({
    id: it.id,
    data: () => it.data,
  }));
}

const joaoDocs = makeDocs([
  { id: "j1", data: { name: "João A", nameSearch: "joao" } },
  { id: "j2", data: { name: "João B", nameSearch: "joao" } },
  { id: "j3", data: { name: "João C", nameSearch: "joao" } },
  { id: "j4", data: { name: "João D", nameSearch: "joao" } },
  { id: "banned", data: { name: "João X", nameSearch: "joao" } },
]);

const usersById = new Map([
  ["j1", { name: "João A", profileComplete: true }],
  ["j2", { name: "João B", profileComplete: true }],
  ["j3", { name: "João C", profileComplete: true }],
  ["j4", { name: "João D", profileComplete: true }],
  ["banned", { name: "João X", profileComplete: true, isBanned: true }],
]);

const page1 = pageEligibleHits({
  docs: joaoDocs.slice(0, 3),
  callerUid: "me",
  usersById,
  pageSize: 2,
  fetchLimit: 3,
  getSortValue: (d) => d.nameSearch,
});
assert.deepStrictEqual(
  page1.results.map((r) => r.uid),
  ["j1", "j2"]
);
assert.strictEqual(page1.hasMore, true);
assert.deepStrictEqual(page1.nextCursor, { v: "joao", id: "j2" });

const page2Docs = joaoDocs.filter(
  (d) => d.id === "j3" || d.id === "j4" || d.id === "banned"
);
const page2 = pageEligibleHits({
  docs: page2Docs,
  callerUid: "me",
  usersById,
  pageSize: 2,
  fetchLimit: 3,
  getSortValue: (d) => d.nameSearch,
});
assert.deepStrictEqual(
  page2.results.map((r) => r.uid),
  ["j3", "j4"]
);
assert.ok(!page2.results.some((r) => r.uid === "banned"));

// Mesma cidade / região / país
const cityPage = pageEligibleHits({
  docs: makeDocs([
    {
      id: "c1",
      data: {
        name: "Alice",
        city: "Springfield",
        country: "USA",
        countryCode: "us",
        citySearch: "springfield",
      },
    },
    {
      id: "c2",
      data: {
        name: "Bobbie",
        city: "Springfield",
        country: "Canada",
        countryCode: "ca",
        citySearch: "springfield",
      },
    },
  ]),
  callerUid: "me",
  usersById: new Map([
    ["c1", { name: "Alice", profileComplete: true }],
    ["c2", { name: "Bobbie", profileComplete: true }],
  ]),
  pageSize: 10,
  fetchLimit: 40,
  getSortValue: (d) => d.citySearch,
});
assert.strictEqual(cityPage.results.length, 2);
assert.strictEqual(cityPage.results[0].country, "USA");
assert.strictEqual(cityPage.results[1].country, "Canada");

assert.ok(computeFetchLimit(20) <= MAX_PUBLIC_FETCH);
assert.strictEqual(clampLimit(999), MAX_PAGE_SIZE);

// ---- Fake Firestore handler ----
class FakePublicQuery {
  constructor(map) {
    this.docs0 = Object.keys(map).map((id) => ({ id, _data: map[id] }));
    this._filters = [];
    this._orders = [];
    this._after = null;
    this._limit = 1000;
  }
  where(field, op, value) {
    this._filters.push({ field, op, value });
    return this;
  }
  orderBy(field) {
    this._orders.push(field);
    return this;
  }
  startAfter(...args) {
    this._after = args;
    return this;
  }
  limit(n) {
    this._limit = n;
    return this;
  }
  async get() {
    let field = "nameSearch";
    let gte = null;
    let lt = null;
    let eqCode = null;
    for (const f of this._filters) {
      if (f.op === ">=") {
        field = f.field;
        gte = f.value;
      }
      if (f.op === "<") lt = f.value;
      if (f.field === "countryCode" && f.op === "==") eqCode = f.value;
    }

    let docs = this.docs0.filter((d) => {
      if (eqCode !== null) {
        return (d._data.countryCode || "") === eqCode;
      }
      const ns = (d._data[field] || "").toString();
      if (gte !== null && ns < gte) return false;
      if (lt !== null && ns >= lt) return false;
      return true;
    });

    docs.sort((a, b) => {
      const fa = (a._data[field] || "").toString();
      const fb = (b._data[field] || "").toString();
      if (fa !== fb) return fa.localeCompare(fb);
      return a.id.localeCompare(b.id);
    });

    if (this._after) {
      if (this._after.length === 2) {
        const [v, id] = this._after;
        docs = docs.filter((d) => {
          const ns = (d._data[field] || "").toString();
          return ns > v || (ns === v && d.id > id);
        });
      } else if (this._after.length === 1) {
        const id = this._after[0];
        docs = docs.filter((d) => d.id > id);
      }
    }

    docs = docs.slice(0, this._limit).map((d) => ({
      id: d.id,
      data: () => d._data,
    }));
    return { docs, size: docs.length };
  }
}

function makeFakeDb({ publicUsers, users }) {
  return {
    getAll: async (...refs) =>
      refs.map((r) => ({
        id: r._id,
        exists: Object.prototype.hasOwnProperty.call(users, r._id),
        data: () => users[r._id],
      })),
    collection(name) {
      if (name === "publicUsers") {
        return {
          where: (...a) => new FakePublicQuery(publicUsers).where(...a),
        };
      }
      if (name === "users") {
        return {
          doc: (id) => ({
            _id: id,
            get: async () => ({
              exists: Object.prototype.hasOwnProperty.call(users, id),
              data: () => users[id],
            }),
          }),
        };
      }
      throw new Error("unexpected " + name);
    },
  };
}

async function runHandlerTests() {
  const publicUsers = {
    me: {
      nameSearch: "ana clara",
      name: "Ana Clara",
      citySearch: "rio",
      city: "Rio",
      countryCode: "br",
      country: "Brasil",
    },
    ok: {
      nameSearch: "ana souza",
      name: "Ana Souza",
      citySearch: "lisboa",
      city: "Lisboa",
      regionSearch: "lisboa",
      state: "Lisboa",
      countrySearch: "portugal",
      country: "Portugal",
      countryCode: "pt",
      email: "x@x",
    },
    banned: { nameSearch: "ana ban", name: "Ana Ban" },
    incomplete: { nameSearch: "ana nova", name: "Ana Nova" },
    legacy: {
      nameSearch: "ana antiga",
      name: "Ana Antiga",
      city: "Porto",
      citySearch: "porto",
      country: "Portugal",
      countryCode: "pt",
      countrySearch: "portugal",
    },
    joao1: { nameSearch: "joao", name: "João 1" },
    joao2: { nameSearch: "joao", name: "João 2" },
    joao3: { nameSearch: "joao", name: "João 3" },
  };
  const users = {
    me: { name: "Ana Clara", profileComplete: true },
    ok: { name: "Ana Souza", profileComplete: true },
    banned: { name: "Ana Ban", profileComplete: true, isBanned: true },
    incomplete: { name: "Ana Nova", profileComplete: false },
    legacy: { name: "Ana Antiga", profileComplete: true },
    joao1: { name: "João 1", profileComplete: true },
    joao2: { name: "João 2", profileComplete: true },
    joao3: { name: "João 3", profileComplete: true },
  };

  const handler = createSearchUsersHandler({
    getFirestore: () => makeFakeDb({ publicUsers, users }),
    HttpsError: FakeHttpsError,
    documentIdPath: "__name__",
    rateLimitFn: async () => {},
  });

  // Tipo inválido
  let threw = false;
  try {
    await handler({
      auth: { uid: "me" },
      data: { query: "ana", type: "email" },
    });
  } catch (e) {
    threw = true;
    assert.strictEqual(e.code, "invalid-argument");
  }
  assert.ok(threw);

  // Nome
  const byName = await handler({
    auth: { uid: "me" },
    data: { query: "ana", type: "name", limit: 20 },
  });
  assert.deepStrictEqual(
    byName.results.map((r) => r.uid).sort(),
    ["legacy", "ok"]
  );
  for (const r of byName.results) {
    for (const k of Object.keys(r)) {
      assert.ok(
        ["uid", "name", "photoUrl", "city", "region", "country", "countryCode"].includes(
          k
        ),
        "campo inesperado: " + k
      );
    }
  }

  // Cidade
  const byCity = await handler({
    auth: { uid: "me" },
    data: { query: "lis", type: "city" },
  });
  assert.deepStrictEqual(
    byCity.results.map((r) => r.uid),
    ["ok"]
  );

  // Região
  const byRegion = await handler({
    auth: { uid: "me" },
    data: { query: "lis", type: "region" },
  });
  assert.ok(byRegion.results.some((r) => r.uid === "ok"));

  // País por nome
  const byCountry = await handler({
    auth: { uid: "me" },
    data: { query: "port", type: "country" },
  });
  assert.ok(byCountry.results.every((r) => r.countryCode === "pt" || r.country));

  // País por código
  const byCode = await handler({
    auth: { uid: "me" },
    data: { query: "pt", type: "country" },
  });
  assert.ok(byCode.results.length >= 1);

  // Paginação vários João
  const p1 = await handler({
    auth: { uid: "me" },
    data: { query: "jo", type: "name", limit: 2 },
  });
  assert.strictEqual(p1.results.length, 2);
  assert.strictEqual(p1.hasMore, true);
  assert.ok(p1.nextCursor && p1.nextCursor.v && p1.nextCursor.id);

  const p2 = await handler({
    auth: { uid: "me" },
    data: {
      query: "jo",
      type: "name",
      limit: 2,
      cursor: p1.nextCursor,
    },
  });
  const allIds = [...p1.results, ...p2.results].map((r) => r.uid);
  assert.strictEqual(new Set(allIds).size, allIds.length, "sem repetir");

  // Rate limit: injetado para falhar
  const limited = createSearchUsersHandler({
    getFirestore: () => makeFakeDb({ publicUsers, users }),
    HttpsError: FakeHttpsError,
    documentIdPath: "__name__",
    rateLimitFn: async () => {
      throw new FakeHttpsError("resource-exhausted", "Too many");
    },
  });
  let rateThrew = false;
  try {
    await limited({
      auth: { uid: "me" },
      data: { query: "ana", type: "name" },
    });
  } catch (e) {
    rateThrew = true;
    assert.strictEqual(e.code, "resource-exhausted");
  }
  assert.ok(rateThrew, "rate limit deve bloquear");

  console.log("user_search handler tests OK");
}

runHandlerTests()
  .then(() => console.log("All user_search tests passed."))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
