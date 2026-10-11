"use strict";

/**
 * Validação pura de Place Details (Google Places).
 * Sem I/O — testável com fixtures. Coordenadas canônicas vêm só daqui.
 */

const CITY_PLACE_TYPES = new Set([
  "locality",
  "postal_town",
  "administrative_area_level_2",
  "administrative_area_level_3",
  "sublocality",
  "sublocality_level_1",
  "sublocality_level_2",
  "neighborhood",
]);

/** Bump when the selected place name must win over the parent locality. */
const PLACE_PARSE_REVISION = 2;

const REJECT_ONLY_TYPES = new Set([
  "country",
  "route",
  "street_address",
  "premise",
  "subpremise",
  "plus_code",
  "geocode",
]);

function normalizeCountryCode(value) {
  return (value || "").toString().trim().toLowerCase();
}

function componentByType(components, type) {
  if (!Array.isArray(components)) return null;
  return (
    components.find(
      (c) => Array.isArray(c.types) && c.types.includes(type),
    ) || null
  );
}

/**
 * @param {object} detailsResult - `result` de Place Details
 * @param {string} placeId
 * @returns {{
 *   placeId: string,
 *   cityName: string,
 *   countryName: string,
 *   countryCode: string,
 *   latitude: number,
 *   longitude: number,
 *   types: string[],
 *   isCityLike: boolean,
 * }}
 */
function parsePlaceDetailsResult(detailsResult, placeId) {
  if (!detailsResult || typeof detailsResult !== "object") {
    const err = new Error("Place details missing.");
    err.code = "invalid-place";
    throw err;
  }

  const types = Array.isArray(detailsResult.types)
    ? detailsResult.types.map((t) => String(t))
    : [];
  const components = detailsResult.address_components || [];

  const locality =
    componentByType(components, "locality") ||
    componentByType(components, "postal_town") ||
    componentByType(components, "administrative_area_level_2");
  const selectedComponent =
    componentByType(components, "sublocality_level_1") ||
    componentByType(components, "sublocality") ||
    componentByType(components, "neighborhood") ||
    componentByType(components, "administrative_area_level_3");
  const adminArea = componentByType(components, "administrative_area_level_1");
  const country = componentByType(components, "country");

  const geometry = detailsResult.geometry || {};
  const location = geometry.location || {};
  const lat = location.lat;
  const lng = location.lng;

  if (typeof lat !== "number" || !Number.isFinite(lat) || lat < -90 || lat > 90) {
    const err = new Error("Place latitude invalid.");
    err.code = "invalid-place";
    throw err;
  }
  if (
    typeof lng !== "number" ||
    !Number.isFinite(lng) ||
    lng < -180 ||
    lng > 180
  ) {
    const err = new Error("Place longitude invalid.");
    err.code = "invalid-place";
    throw err;
  }

  const countryCode = normalizeCountryCode(
    (country && (country.short_name || country.shortName)) || "",
  );
  const countryName = (
    (country && (country.long_name || country.longName)) ||
    ""
  )
    .toString()
    .trim();
  const parentLocality = (
    (locality && (locality.long_name || locality.longName)) ||
    ""
  )
    .toString()
    .trim();
  const selectedComponentName = (
    (selectedComponent &&
      (selectedComponent.long_name || selectedComponent.longName)) ||
    ""
  )
    .toString()
    .trim();
  const placeName = (detailsResult.name || "").toString().trim();
  // The place the user picked. A sublocality named York stays York even when
  // its parent locality is Toronto. A locality named Toronto stays Toronto.
  const cityName = placeName || selectedComponentName || parentLocality;
  const stateName = (
    (adminArea &&
      (adminArea.short_name ||
        adminArea.shortName ||
        adminArea.long_name ||
        adminArea.longName)) ||
    ""
  )
    .toString()
    .trim();

  const hasCityType = types.some((t) => CITY_PLACE_TYPES.has(t));
  const hasLocalityComponent = Boolean(locality);
  const onlyRejected =
    types.length > 0 && types.every((t) => REJECT_ONLY_TYPES.has(t));
  const isCityLike = (hasCityType || hasLocalityComponent) && !onlyRejected;

  return {
    placeId: (placeId || detailsResult.place_id || "").toString().trim(),
    cityName,
    parentLocality,
    stateName,
    countryName,
    countryCode,
    latitude: lat,
    longitude: lng,
    types,
    isCityLike,
    parseRevision: PLACE_PARSE_REVISION,
  };
}

function placesCacheIsCurrent(payload) {
  return Boolean(
    payload &&
      payload.parseRevision === PLACE_PARSE_REVISION &&
      payload.cityName,
  );
}

/**
 * Exige cidade pública confiável e correspondência com o país do grupo.
 * @param {ReturnType<typeof parsePlaceDetailsResult>} parsed
 * @param {{ expectedCountryCode: string }} opts
 */
function assertTrustedCityPlace(parsed, opts) {
  const expected = normalizeCountryCode(opts?.expectedCountryCode);
  if (!parsed || !parsed.placeId) {
    const err = new Error("placeId required.");
    err.code = "invalid-place";
    throw err;
  }
  if (!parsed.isCityLike) {
    const err = new Error("Place is not a city.");
    err.code = "not-a-city";
    throw err;
  }
  if (!parsed.cityName) {
    const err = new Error("City name missing from place.");
    err.code = "invalid-place";
    throw err;
  }
  if (!parsed.countryCode || parsed.countryCode.length !== 2) {
    const err = new Error("Country code missing from place.");
    err.code = "invalid-place";
    throw err;
  }
  if (!expected || expected.length !== 2) {
    const err = new Error("Expected country code required.");
    err.code = "invalid-country";
    throw err;
  }
  if (parsed.countryCode !== expected) {
    const err = new Error("City/country mismatch.");
    err.code = "country-mismatch";
    throw err;
  }
  return parsed;
}

/**
 * Recusa coordenadas/geohash/raio forjados pelo cliente quando o servidor
 * já resolveu o lugar. Sempre usa o valor canônico.
 */
function stripClientGeoTrust(clientPayload = {}) {
  const copy = { ...clientPayload };
  delete copy.regionCenterLat;
  delete copy.regionCenterLng;
  delete copy.regionCenterGeohash;
  delete copy.regionRadiusKm;
  delete copy.latitude;
  delete copy.longitude;
  return copy;
}

const REGION_RADIUS_KM = 110;
const PLACES_CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 dias

module.exports = {
  CITY_PLACE_TYPES,
  PLACE_PARSE_REVISION,
  REGION_RADIUS_KM,
  PLACES_CACHE_TTL_MS,
  normalizeCountryCode,
  parsePlaceDetailsResult,
  placesCacheIsCurrent,
  assertTrustedCityPlace,
  stripClientGeoTrust,
};
