"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  parsePlaceDetailsResult,
  assertTrustedCityPlace,
  stripClientGeoTrust,
  REGION_RADIUS_KM,
} = require("./group_places_logic");
const {
  buildCanonicalGeoFields,
  clientForgedRegionalGeo,
  encodeGroupGeohash,
} = require("./group_geo_canonical");

function cityDetails(overrides = {}) {
  return {
    place_id: "ChIJcity",
    name: "Navegantes",
    types: ["locality", "political"],
    geometry: { location: { lat: -26.8943, lng: -48.6546 } },
    address_components: [
      {
        long_name: "Navegantes",
        short_name: "Navegantes",
        types: ["locality", "political"],
      },
      {
        long_name: "Brasil",
        short_name: "BR",
        types: ["country", "political"],
      },
    ],
    ...overrides,
  };
}

test("placeId de cidade válida extrai coords/país/tipo", () => {
  const parsed = parsePlaceDetailsResult(cityDetails(), "ChIJcity");
  assert.equal(parsed.cityName, "Navegantes");
  assert.equal(parsed.countryCode, "br");
  assert.equal(parsed.latitude, -26.8943);
  assert.equal(parsed.isCityLike, true);
  assertTrustedCityPlace(parsed, { expectedCountryCode: "br" });
});

test("placeId inválido / details ausentes", () => {
  assert.throws(() => parsePlaceDetailsResult(null, "x"), /Place details/);
});

test("cidade retornando país diferente", () => {
  const parsed = parsePlaceDetailsResult(cityDetails(), "ChIJcity");
  assert.throws(
    () => assertTrustedCityPlace(parsed, { expectedCountryCode: "us" }),
    (err) => err.code === "country-mismatch",
  );
});

test("local que não é cidade", () => {
  const parsed = parsePlaceDetailsResult(
    cityDetails({
      types: ["route"],
      address_components: [
        {
          long_name: "Av. Brasil",
          short_name: "Av. Brasil",
          types: ["route"],
        },
        {
          long_name: "Brasil",
          short_name: "BR",
          types: ["country", "political"],
        },
      ],
      name: "Av. Brasil",
    }),
    "ChIJroad",
  );
  assert.equal(parsed.isCityLike, false);
  assert.throws(
    () => assertTrustedCityPlace(parsed, { expectedCountryCode: "br" }),
    (err) => err.code === "not-a-city",
  );
});

test("radiusKm diferente de 110 é forjado", () => {
  const place = assertTrustedCityPlace(
    parsePlaceDetailsResult(cityDetails(), "ChIJcity"),
    { expectedCountryCode: "br" },
  );
  const canonical = buildCanonicalGeoFields("region", {
    place,
    countryName: "Brasil",
    countryCode: "br",
  });
  assert.equal(canonical.regionRadiusKm, REGION_RADIUS_KM);
  assert.equal(
    clientForgedRegionalGeo({ regionRadiusKm: 500 }, canonical),
    true,
  );
  assert.equal(
    clientForgedRegionalGeo({ regionRadiusKm: 110 }, canonical),
    false,
  );
});

test("coordenadas/geohash forjados pelo cliente", () => {
  const place = assertTrustedCityPlace(
    parsePlaceDetailsResult(cityDetails(), "ChIJcity"),
    { expectedCountryCode: "br" },
  );
  const canonical = buildCanonicalGeoFields("region", {
    place,
    countryName: "Brasil",
    countryCode: "br",
  });
  assert.equal(
    clientForgedRegionalGeo(
      { regionCenterLat: 0, regionCenterLng: 0 },
      canonical,
    ),
    true,
  );
  assert.equal(
    clientForgedRegionalGeo(
      { regionCenterGeohash: "zzz" },
      canonical,
    ),
    true,
  );
  assert.equal(
    clientForgedRegionalGeo(
      {
        regionCenterLat: canonical.regionCenterLat,
        regionCenterLng: canonical.regionCenterLng,
        regionCenterGeohash: canonical.regionCenterGeohash,
        regionRadiusKm: 110,
      },
      canonical,
    ),
    false,
  );
  const stripped = stripClientGeoTrust({
    placeId: "ChIJcity",
    regionCenterLat: 1,
    regionRadiusKm: 999,
  });
  assert.equal(stripped.placeId, "ChIJcity");
  assert.equal(stripped.regionCenterLat, undefined);
  assert.equal(stripped.regionRadiusKm, undefined);
});

test("mudança entre escopos limpa campos incompatíveis", () => {
  const place = assertTrustedCityPlace(
    parsePlaceDetailsResult(cityDetails(), "ChIJcity"),
    { expectedCountryCode: "br" },
  );
  const region = buildCanonicalGeoFields("region", {
    place,
    countryName: "Brasil",
    countryCode: "br",
  });
  assert.equal(region.regionRadiusKm, 110);
  assert.ok(region.regionCenterGeohash);

  const city = buildCanonicalGeoFields("city", {
    place,
    countryName: "Brasil",
    countryCode: "br",
  });
  assert.equal(city.regionCenterLat, null);
  assert.equal(city.regionRadiusKm, null);
  assert.equal(city.regionCenterGeohash, "");
  assert.equal(city.scope, "city");

  const country = buildCanonicalGeoFields("country", {
    countryName: "Brasil",
    countryCode: "br",
  });
  assert.equal(country.city, "");
  assert.equal(country.placeId, "");
  assert.equal(country.regionCenterCity, "");
  assert.equal(country.latitude, null);
  assert.equal(country.scope, "country");
});

test("geohash canônico bate com lat/lng públicas", () => {
  const hash = encodeGroupGeohash(-26.8943, -48.6546, 3);
  assert.equal(hash.length, 3);
  const place = assertTrustedCityPlace(
    parsePlaceDetailsResult(cityDetails(), "ChIJcity"),
    { expectedCountryCode: "br" },
  );
  const region = buildCanonicalGeoFields("region", {
    place,
    countryName: "Brasil",
    countryCode: "br",
  });
  assert.equal(region.regionCenterGeohash, hash);
});
