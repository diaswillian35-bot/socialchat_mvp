"use strict";

const {
  REGION_RADIUS_KM,
  normalizeCountryCode,
} = require("./group_places_logic");

function encodeGroupGeohash(latitude, longitude, precision = 3) {
  if (typeof latitude !== "number" || typeof longitude !== "number") return "";
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return "";
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    return "";
  }
  const alphabet = "0123456789bcdefghjkmnpqrstuvwxyz";
  let latMin = -90;
  let latMax = 90;
  let lngMin = -180;
  let lngMax = 180;
  let even = true;
  let bit = 0;
  let value = 0;
  let out = "";
  while (out.length < precision) {
    if (even) {
      const mid = (lngMin + lngMax) / 2;
      if (longitude >= mid) {
        value = (value << 1) | 1;
        lngMin = mid;
      } else {
        value <<= 1;
        lngMax = mid;
      }
    } else {
      const mid = (latMin + latMax) / 2;
      if (latitude >= mid) {
        value = (value << 1) | 1;
        latMin = mid;
      } else {
        value <<= 1;
        latMax = mid;
      }
    }
    even = !even;
    bit += 1;
    if (bit === 5) {
      out += alphabet[value];
      bit = 0;
      value = 0;
    }
  }
  return out;
}

function foldCityKey(value) {
  return (value || "")
    .toString()
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, " ");
}

/**
 * Campos canônicos por escopo. Remove incompatíveis do escopo anterior.
 * @param {'city'|'region'|'country'} scope
 * @param {{
 *   place?: object|null,
 *   countryName?: string,
 *   countryCode?: string,
 *   displayLocation?: string,
 *   stateName?: string,
 * }} opts
 */
function buildCanonicalGeoFields(scope, opts = {}) {
  const countryCode = normalizeCountryCode(
    opts.place?.countryCode || opts.countryCode || "",
  );
  const countryName = (
    opts.place?.countryName ||
    opts.countryName ||
    ""
  )
    .toString()
    .trim();

  const emptyRegion = {
    regionKey: "",
    regionCenterCity: "",
    regionCenterCountryCode: "",
    regionCenterLat: null,
    regionCenterLng: null,
    regionRadiusKm: null,
    regionCenterGeohash: "",
  };

  if (scope === "country") {
    return {
      scope: "country",
      country: countryName,
      countryCode,
      city: "",
      cityName: "",
      cityKey: "",
      stateName: "",
      displayLocation: countryName,
      placeId: "",
      latitude: null,
      longitude: null,
      ...emptyRegion,
    };
  }

  const place = opts.place;
  if (!place) {
    const err = new Error("Trusted place required for city/region.");
    err.code = "invalid-place";
    throw err;
  }

  const cityName = (place.cityName || "").toString().trim();
  const cityKey = foldCityKey(cityName);
  const stateName = (opts.stateName || "").toString().trim();
  const display =
    (opts.displayLocation || "").toString().trim() || cityName;

  if (scope === "city") {
    return {
      scope: "city",
      country: countryName || place.countryName,
      countryCode,
      city: cityName,
      cityName,
      cityKey,
      stateName,
      displayLocation: display,
      placeId: place.placeId,
      latitude: place.latitude,
      longitude: place.longitude,
      ...emptyRegion,
    };
  }

  // region
  const geohash = encodeGroupGeohash(place.latitude, place.longitude, 3);
  return {
    scope: "region",
    country: countryName || place.countryName,
    countryCode,
    city: cityName,
    cityName,
    cityKey,
    stateName,
    displayLocation: display,
    placeId: place.placeId,
    latitude: place.latitude,
    longitude: place.longitude,
    regionKey: "",
    regionCenterCity: cityName,
    regionCenterCountryCode: countryCode,
    regionCenterLat: place.latitude,
    regionCenterLng: place.longitude,
    regionRadiusKm: REGION_RADIUS_KM,
    regionCenterGeohash: geohash,
  };
}

/**
 * Detecta se o cliente tentou forjar centro/raio/geohash divergente do canônico.
 */
function clientForgedRegionalGeo(client, canonical) {
  if (!client || !canonical) return false;
  const forgedKeys = [
    ["regionCenterLat", "regionCenterLat"],
    ["regionCenterLng", "regionCenterLng"],
    ["regionCenterGeohash", "regionCenterGeohash"],
    ["regionRadiusKm", "regionRadiusKm"],
  ];
  for (const [ck, pk] of forgedKeys) {
    if (client[ck] === undefined || client[ck] === null || client[ck] === "") {
      continue;
    }
    if (ck === "regionRadiusKm") {
      if (Number(client[ck]) !== REGION_RADIUS_KM) return true;
      continue;
    }
    if (ck === "regionCenterGeohash") {
      const sent = String(client[ck]).trim();
      if (sent && sent !== canonical[pk]) return true;
      continue;
    }
    if (typeof client[ck] === "number" && Number.isFinite(client[ck])) {
      if (Math.abs(client[ck] - canonical[pk]) > 1e-5) return true;
    }
  }
  return false;
}

module.exports = {
  encodeGroupGeohash,
  foldCityKey,
  buildCanonicalGeoFields,
  clientForgedRegionalGeo,
  REGION_RADIUS_KM,
};
