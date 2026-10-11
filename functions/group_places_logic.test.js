"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  parsePlaceDetailsResult,
  assertTrustedCityPlace,
  placesCacheIsCurrent,
  stripClientGeoTrust,
  REGION_RADIUS_KM,
  PLACE_PARSE_REVISION,
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

function yorkDetails() {
  return {
    place_id: "york-place",
    name: "York",
    types: ["political", "sublocality", "sublocality_level_1"],
    geometry: { location: { lat: 43.69, lng: -79.48 } },
    address_components: [
      {
        long_name: "York",
        short_name: "York",
        types: ["sublocality_level_1", "sublocality", "political"],
      },
      {
        long_name: "Toronto",
        short_name: "Toronto",
        types: ["locality", "political"],
      },
      {
        long_name: "Ontario",
        short_name: "ON",
        types: ["administrative_area_level_1", "political"],
      },
      {
        long_name: "Canada",
        short_name: "CA",
        types: ["country", "political"],
      },
    ],
  };
}

test("York sublocality keeps York and does not become Toronto", () => {
  const parsed = assertTrustedCityPlace(
    parsePlaceDetailsResult(yorkDetails(), "york-place"),
    { expectedCountryCode: "ca" },
  );
  assert.equal(parsed.cityName, "York");
  assert.equal(parsed.parentLocality, "Toronto");
  assert.equal(parsed.stateName, "ON");
  assert.equal(parsed.countryCode, "ca");
  assert.equal(parsed.latitude, 43.69);
  assert.equal(parsed.longitude, -79.48);
  assert.equal(parsed.parseRevision, PLACE_PARSE_REVISION);

  const fields = buildCanonicalGeoFields("city", {
    place: parsed,
    countryName: "Canadá",
    countryCode: "ca",
    displayLocation: "York, ON, Canadá",
    stateName: "Toronto",
  });
  assert.equal(fields.city, "York");
  assert.equal(fields.cityName, "York");
  assert.equal(fields.cityKey, "york");
  assert.equal(fields.stateName, "ON");
  assert.equal(fields.displayLocation, "York, ON, Canadá");
  assert.equal(fields.placeId, "york-place");
  assert.equal(fields.latitude, 43.69);
});

test("a Toronto locality stays Toronto", () => {
  const parsed = assertTrustedCityPlace(
    parsePlaceDetailsResult(
      cityDetails({
        name: "Toronto",
        place_id: "toronto-place",
        geometry: { location: { lat: 43.65, lng: -79.38 } },
        address_components: [
          {
            long_name: "Toronto",
            short_name: "Toronto",
            types: ["locality", "political"],
          },
          {
            long_name: "Ontario",
            short_name: "ON",
            types: ["administrative_area_level_1", "political"],
          },
          {
            long_name: "Canada",
            short_name: "CA",
            types: ["country", "political"],
          },
        ],
      }),
      "toronto-place",
    ),
    { expectedCountryCode: "ca" },
  );
  const fields = buildCanonicalGeoFields("city", {
    place: parsed,
    countryName: "Canada",
    countryCode: "ca",
    displayLocation: "Toronto, ON, Canada",
  });
  assert.equal(fields.cityName, "Toronto");
  assert.equal(fields.cityKey, "toronto");
  assert.equal(fields.displayLocation, "Toronto, ON, Canada");
});

test("a mismatched display cannot rename the selected place", () => {
  const parsed = assertTrustedCityPlace(
    parsePlaceDetailsResult(yorkDetails(), "york-place"),
    { expectedCountryCode: "ca" },
  );
  const fields = buildCanonicalGeoFields("city", {
    place: parsed,
    countryName: "Canada",
    countryCode: "ca",
    displayLocation: "Toronto, ON, Canada",
  });
  assert.equal(fields.cityName, "York");
  assert.equal(fields.displayLocation, "York, ON, Canada");
  assert.equal(fields.cityKey, "york");
});

test("stale places cache without the selected-name revision is ignored", () => {
  assert.equal(
    placesCacheIsCurrent({
      cityName: "Toronto",
      parseRevision: PLACE_PARSE_REVISION,
    }),
    true,
  );
  assert.equal(placesCacheIsCurrent({ cityName: "Toronto" }), false);
});
