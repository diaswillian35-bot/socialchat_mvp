/**
 * Busca segura e global de usuários (server-side).
 *
 * Tipos permitidos (whitelist — o cliente NÃO escolhe campos Firestore):
 *   name | city | region | country
 *
 * Filtragem sensível (ban / exclusão / desativação / perfil incompleto) usa a
 * coleção confiável `users`. O payload ao cliente contém SOMENTE:
 *   uid, name, photoUrl, city, region, country, countryCode
 *
 * Cursor: { v: valorNormalizado, id: documentId } — evita pular/repetir
 * quando há vários João / mesma cidade / mesma região / mesmo país.
 *
 * Leituras: no máximo MAX_PUBLIC_FETCH docs em publicUsers + o mesmo lote
 * em users (getAll em paralelo), nunca N gets sequenciais.
 */

const MIN_QUERY_LENGTH = 2;
const DEFAULT_PAGE_SIZE = 20;
const MAX_PAGE_SIZE = 30;
/** Máximo de docs publicUsers lidos por chamada (inclui over-fetch). */
const MAX_PUBLIC_FETCH = 40;
/** Over-fetch relativo ao pageSize para compensar filtragem. */
const OVERFETCH_FACTOR = 2;
/** Proteção contra abuso: máx. buscas por janela por UID. */
const RATE_LIMIT_MAX = 40;
const RATE_LIMIT_WINDOW_MS = 60 * 1000;

const ALLOWED_TYPES = Object.freeze({
  name: "nameSearch",
  city: "citySearch",
  region: "regionSearch",
  country: "countrySearch",
});

const DIACRITICS = {
  á: "a", à: "a", ã: "a", â: "a", ä: "a", å: "a", ā: "a", ă: "a", ą: "a",
  é: "e", è: "e", ê: "e", ë: "e", ē: "e", ĕ: "e", ė: "e", ę: "e", ě: "e",
  í: "i", ì: "i", î: "i", ï: "i", ī: "i", ĭ: "i", į: "i", ı: "i",
  ó: "o", ò: "o", õ: "o", ô: "o", ö: "o", ō: "o", ŏ: "o", ő: "o", ø: "o",
  ú: "u", ù: "u", û: "u", ü: "u", ū: "u", ŭ: "u", ů: "u", ű: "u", ų: "u",
  ý: "y", ÿ: "y",
  ñ: "n", ń: "n", ň: "n", ŋ: "n",
  ç: "c", ć: "c", č: "c",
  ď: "d", đ: "d",
  ľ: "l", ĺ: "l", ł: "l",
  ř: "r", ŕ: "r",
  ś: "s", š: "s", ş: "s",
  ť: "t", ţ: "t",
  ź: "z", ž: "z", ż: "z",
};

function normalizeSearchText(input) {
  if (input === null || input === undefined) return "";
  let value = String(input).trim().toLowerCase().replace(/\s+/g, " ");
  if (!value) return "";
  let out = "";
  for (const ch of value) {
    out += Object.prototype.hasOwnProperty.call(DIACRITICS, ch)
      ? DIACRITICS[ch]
      : ch;
  }
  return out;
}

function isQueryReady(rawQuery) {
  return normalizeSearchText(rawQuery).length >= MIN_QUERY_LENGTH;
}

function clampLimit(raw) {
  const n = Number(raw);
  if (!Number.isFinite(n)) return DEFAULT_PAGE_SIZE;
  const i = Math.floor(n);
  if (i < 1) return DEFAULT_PAGE_SIZE;
  if (i > MAX_PAGE_SIZE) return MAX_PAGE_SIZE;
  return i;
}

function resolveSearchType(raw) {
  const t = (raw || "name").toString().trim().toLowerCase();
  if (!Object.prototype.hasOwnProperty.call(ALLOWED_TYPES, t)) {
    return null;
  }
  return t;
}

function searchFieldForType(type) {
  return ALLOWED_TYPES[type] || null;
}

function isCountryCodeQuery(normalized) {
  return /^[a-z]{2}$/.test(normalized);
}

/**
 * Cursor seguro: { v, id }. Qualquer formato inválido → null (reinicia página).
 */
function parseCursor(raw) {
  if (raw === null || raw === undefined) return null;
  if (typeof raw !== "object" || Array.isArray(raw)) return null;
  const v = (raw.v ?? raw.value ?? "").toString();
  const id = (raw.id ?? raw.docId ?? "").toString().trim();
  if (!v || !id) return null;
  if (id.length > 128) return null;
  if (!/^[A-Za-z0-9_-]+$/.test(id)) return null;
  return { v, id };
}

function encodeCursor(v, id) {
  if (!v || !id) return null;
  return { v: String(v), id: String(id) };
}

function isAccountDisabled(userData) {
  if (!userData) return false;
  if (
    Object.prototype.hasOwnProperty.call(userData, "isActive") &&
    userData.isActive === false
  ) {
    return true;
  }
  return (
    userData.isDisabled === true ||
    userData.disabled === true ||
    userData.deactivated === true
  );
}

function isSearchableAccount(userData) {
  if (!userData) return false;
  if (userData.isBanned === true) return false;
  if (userData.status === "banned") return false;
  if (userData.deleted === true) return false;
  if (userData.isDeleted === true) return false;
  if (userData.accountDeleted === true) return false;
  if (isAccountDisabled(userData)) return false;
  if (userData.profileComplete !== true) return false;
  const name = (userData.name || "").toString().trim();
  if (name.length < MIN_QUERY_LENGTH) return false;
  return true;
}

/** Região administrativa (estado / província / região) a partir de campos públicos. */
function readRegion(publicData) {
  const p = publicData || {};
  const candidates = [
    p.region,
    p.state,
    p.stateName,
    p.province,
    p.adminArea,
    p.administrativeArea,
  ];
  for (const c of candidates) {
    const s = (c || "").toString().trim();
    if (s) return s;
  }
  return "";
}

function readCity(publicData) {
  const p = publicData || {};
  const city = (p.city || p.cityName || "").toString().trim();
  return city;
}

function readCountryCode(publicData) {
  const p = publicData || {};
  return (p.countryCode || p.homeCountryCode || "")
    .toString()
    .trim()
    .toLowerCase();
}

/**
 * Payload seguro ao cliente. Descarta email, Premium, tokens, coords, etc.
 */
function buildSafeResult(uid, publicData) {
  const p = publicData || {};
  const safeUid = (uid || "").toString().trim();
  const name = (p.name || "").toString().trim();
  if (!safeUid || !name) return null;

  const photoUrl = (p.photoUrl || "").toString().trim();
  const city = readCity(p);
  const region = readRegion(p);
  const country = (p.country || "").toString().trim();
  const countryCode = readCountryCode(p);

  const result = { uid: safeUid, name };
  if (photoUrl) result.photoUrl = photoUrl;
  if (city) result.city = city;
  if (region) result.region = region;
  if (country) result.country = country;
  if (countryCode) result.countryCode = countryCode;
  return result;
}

/**
 * Deriva campos normalizados públicos a partir de dados públicos (backfill).
 * Nunca inclui email, Premium, tokens, coords, etc.
 */
function buildPublicSearchFields(publicData) {
  const p = publicData || {};
  const name = (p.name || "").toString().trim();
  const city = readCity(p);
  const region = readRegion(p);
  const country = (p.country || "").toString().trim();
  const countryCode = readCountryCode(p);

  const out = {};
  if (name) out.nameSearch = normalizeSearchText(name);
  if (city) out.citySearch = normalizeSearchText(city);
  if (region) out.regionSearch = normalizeSearchText(region);
  if (country) out.countrySearch = normalizeSearchText(country);
  if (countryCode) out.countryCode = countryCode;
  return out;
}

function computeFetchLimit(pageSize) {
  return Math.min(pageSize * OVERFETCH_FACTOR, MAX_PUBLIC_FETCH);
}

/**
 * Filtra e pagina resultados elegíveis preservando a ordem de `docs`.
 * Pure — testável sem Firestore.
 */
function pageEligibleHits({
  docs,
  callerUid,
  usersById,
  pageSize,
  fetchLimit,
  getSortValue,
}) {
  const results = [];
  let lastCursor = null;

  for (const doc of docs) {
    const uid = doc.id;
    const publicData =
      typeof doc.data === "function" ? doc.data() : doc.data || {};
    const sortValue = getSortValue(publicData, uid);

    if (!uid || uid === callerUid) continue;

    const userData = usersById.get(uid);
    if (!userData || !isSearchableAccount(userData)) continue;

    const safe = buildSafeResult(uid, publicData);
    if (!safe) continue;

    results.push(safe);
    lastCursor = encodeCursor(sortValue, uid);
    if (results.length >= pageSize) break;
  }

  const reachedPage = results.length >= pageSize;
  const fullBatch = docs.length >= fetchLimit;
  const hasMore = (reachedPage || fullBatch) && !!lastCursor;

  return {
    results: results.slice(0, pageSize),
    nextCursor: hasMore ? lastCursor : null,
    hasMore,
  };
}

async function loadUsersByIds(db, uids) {
  const map = new Map();
  if (!uids.length) return map;

  const refs = uids.map((id) => db.collection("users").doc(id));

  if (typeof db.getAll === "function") {
    const snaps = await db.getAll(...refs);
    for (const snap of snaps) {
      if (snap && snap.exists) {
        map.set(snap.id, snap.data() || {});
      }
    }
    return map;
  }

  const CHUNK = 10;
  for (let i = 0; i < refs.length; i += CHUNK) {
    const slice = refs.slice(i, i + CHUNK);
    const snaps = await Promise.all(slice.map((r) => r.get()));
    for (const snap of snaps) {
      if (snap && snap.exists) {
        map.set(snap.id, snap.data() || {});
      }
    }
  }
  return map;
}

/**
 * Rate limit por UID (janela deslizante em `_rateLimits`).
 * Coleção interna — cliente não tem rules de acesso.
 */
async function assertSearchRateLimit(db, uid, HttpsError) {
  if (!uid) {
    throw new HttpsError("unauthenticated", "Login required.");
  }
  const ref = db.collection("_rateLimits").doc(`searchUsers_${uid}`);
  const now = Date.now();

  if (typeof db.runTransaction !== "function") {
    // Ambiente de teste sem transação: no-op controlado pelo fake.
    return;
  }

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() || {} : {};
    let windowStart = Number(data.windowStartMs) || now;
    let count = Number(data.count) || 0;

    if (now - windowStart > RATE_LIMIT_WINDOW_MS) {
      windowStart = now;
      count = 0;
    }

    if (count >= RATE_LIMIT_MAX) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many search requests. Please wait a moment."
      );
    }

    tx.set(
      ref,
      {
        windowStartMs: windowStart,
        count: count + 1,
        updatedAtMs: now,
      },
      { merge: true }
    );
  });
}

function createSearchUsersHandler({
  getFirestore,
  HttpsError,
  documentIdPath,
  rateLimitFn,
}) {
  const docIdPath = documentIdPath || "__name__";
  const checkRate = rateLimitFn || assertSearchRateLimit;

  return async function searchUsersHandler(request) {
    if (!request || !request.auth || !request.auth.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    const callerUid = request.auth.uid;
    const data = request.data || {};
    const type = resolveSearchType(data.type);
    if (!type) {
      throw new HttpsError(
        "invalid-argument",
        "Invalid search type. Allowed: name, city, region, country."
      );
    }

    const q = normalizeSearchText(data.query);
    if (q.length < MIN_QUERY_LENGTH) {
      return { results: [], nextCursor: null, hasMore: false, type };
    }

    const db = getFirestore();
    await checkRate(db, callerUid, HttpsError);

    const pageSize = clampLimit(data.limit);
    const fetchLimit = computeFetchLimit(pageSize);
    const cursor = parseCursor(data.cursor);
    const field = searchFieldForType(type);

    let query;
    let getSortValue;

    if (type === "country" && isCountryCodeQuery(q)) {
      query = db
        .collection("publicUsers")
        .where("countryCode", "==", q)
        .orderBy(docIdPath)
        .limit(fetchLimit);
      if (cursor) {
        query = query.startAfter(cursor.id);
      }
      getSortValue = () => q;
    } else {
      query = db
        .collection("publicUsers")
        .where(field, ">=", q)
        .where(field, "<", q + "\uf8ff")
        .orderBy(field)
        .orderBy(docIdPath)
        .limit(fetchLimit);
      if (cursor) {
        query = query.startAfter(cursor.v, cursor.id);
      }
      getSortValue = (publicData) => (publicData[field] || "").toString() || q;
    }

    const snap = await query.get();
    const docs = snap.docs || [];

    const candidateUids = docs
      .map((d) => d.id)
      .filter((id) => id && id !== callerUid);
    const usersById = await loadUsersByIds(db, candidateUids);

    return {
      ...pageEligibleHits({
        docs,
        callerUid,
        usersById,
        pageSize,
        fetchLimit,
        getSortValue,
      }),
      type,
    };
  };
}

module.exports = {
  MIN_QUERY_LENGTH,
  DEFAULT_PAGE_SIZE,
  MAX_PAGE_SIZE,
  MAX_PUBLIC_FETCH,
  OVERFETCH_FACTOR,
  RATE_LIMIT_MAX,
  RATE_LIMIT_WINDOW_MS,
  ALLOWED_TYPES,
  normalizeSearchText,
  isQueryReady,
  clampLimit,
  resolveSearchType,
  searchFieldForType,
  isCountryCodeQuery,
  parseCursor,
  encodeCursor,
  isAccountDisabled,
  isSearchableAccount,
  readRegion,
  readCity,
  readCountryCode,
  buildSafeResult,
  buildPublicSearchFields,
  computeFetchLimit,
  pageEligibleHits,
  loadUsersByIds,
  assertSearchRateLimit,
  createSearchUsersHandler,
};
