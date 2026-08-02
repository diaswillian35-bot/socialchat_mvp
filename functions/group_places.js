"use strict";

const {
  PLACES_CACHE_TTL_MS,
  parsePlaceDetailsResult,
  assertTrustedCityPlace,
  normalizeCountryCode,
} = require("./group_places_logic");

/**
 * Resolve cidade pública via Place Details + cache Firestore.
 *
 * Custo típico (Places Details): ~$0.017/consulta (SKU Place Details).
 * Cache hit (TTL 30d) → 1 leitura Firestore, $0 Places.
 * Não expor a chave no cliente; usar Secret Manager.
 *
 * @param {{
 *   placeId: string,
 *   expectedCountryCode: string,
 *   apiKey: string,
 *   db: FirebaseFirestore,
 *   fetchImpl?: typeof fetch,
 *   nowMs?: number,
 * }} opts
 */
async function resolveTrustedCityPlace(opts) {
  const placeId = (opts.placeId || "").toString().trim();
  if (!placeId) {
    const err = new Error("placeId required.");
    err.code = "invalid-place";
    throw err;
  }
  const expectedCountryCode = normalizeCountryCode(opts.expectedCountryCode);
  const apiKey = (opts.apiKey || "").toString().trim();
  if (!apiKey) {
    const err = new Error("Places API key not configured.");
    err.code = "places-unavailable";
    throw err;
  }

  const db = opts.db;
  const nowMs = opts.nowMs ?? Date.now();
  const cacheRef = db.collection("placesCache").doc(encodeURIComponent(placeId));

  const cacheSnap = await cacheRef.get();
  if (cacheSnap.exists) {
    const cached = cacheSnap.data() || {};
    const cachedAt = Number(cached.cachedAtMs) || 0;
    if (cachedAt && nowMs - cachedAt < PLACES_CACHE_TTL_MS && cached.payload) {
      const parsed = assertTrustedCityPlace(cached.payload, {
        expectedCountryCode,
      });
      return { place: parsed, fromCache: true };
    }
  }

  const fetchImpl = opts.fetchImpl || global.fetch;
  if (typeof fetchImpl !== "function") {
    const err = new Error("fetch unavailable.");
    err.code = "places-unavailable";
    throw err;
  }

  const url =
    "https://maps.googleapis.com/maps/api/place/details/json" +
    `?place_id=${encodeURIComponent(placeId)}` +
    "&fields=place_id,name,types,geometry,address_components" +
    `&key=${encodeURIComponent(apiKey)}`;

  const res = await fetchImpl(url);
  if (!res.ok) {
    const err = new Error(`Places HTTP ${res.status}`);
    err.code = "places-unavailable";
    throw err;
  }
  const body = await res.json();
  if (!body || body.status !== "OK" || !body.result) {
    const err = new Error(`Places status: ${(body && body.status) || "unknown"}`);
    err.code =
      body && body.status === "INVALID_REQUEST" ? "invalid-place" : "places-unavailable";
    throw err;
  }

  const parsed = assertTrustedCityPlace(
    parsePlaceDetailsResult(body.result, placeId),
    { expectedCountryCode },
  );

  await cacheRef.set(
    {
      placeId,
      payload: parsed,
      cachedAtMs: nowMs,
      provider: "google_places_details",
    },
    { merge: true },
  );

  return { place: parsed, fromCache: false };
}

module.exports = {
  resolveTrustedCityPlace,
};
