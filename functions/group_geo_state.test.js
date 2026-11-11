"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const { normalizeStateCode, stateKeyFor } = require("./group_state_codes");
const {
  buildCanonicalGeoFields,
  encodeGroupGeohash,
} = require("./group_geo_canonical");

test("sigla de estado BR e CA a partir de short_name e nome longo", () => {
  assert.equal(normalizeStateCode("br", "PR"), "PR");
  assert.equal(normalizeStateCode("BR", "Paraná"), "PR");
  assert.equal(normalizeStateCode("br", "State of Paraná"), "PR");
  assert.equal(normalizeStateCode("br", "Estado de São Paulo"), "SP");
  assert.equal(normalizeStateCode("br", "Araranguá - SC"), "SC");
  assert.equal(normalizeStateCode("br", "Brasil"), "");
  assert.equal(normalizeStateCode("ca", "ON"), "ON");
  assert.equal(normalizeStateCode("ca", "Québec"), "QC");
  assert.equal(normalizeStateCode("ca", "Colombie-Britannique"), "BC");
  assert.equal(normalizeStateCode("us", "NY"), "NY");
  assert.equal(normalizeStateCode("br", ""), "");
});

test("stateKey é país-sigla minúsculo", () => {
  assert.equal(stateKeyFor("br", "PR"), "br-pr");
  assert.equal(stateKeyFor("CA", "ON"), "ca-on");
  assert.equal(stateKeyFor("br", ""), "");
});

const campoMourao = {
  placeId: "p-cm",
  cityName: "Campo Mourão",
  stateName: "PR",
  countryName: "Brasil",
  countryCode: "br",
  latitude: -24.0459,
  longitude: -52.3831,
};

test("cidade grava stateCode, stateKey e geohash3 do centro da cidade", () => {
  const g = buildCanonicalGeoFields("city", {
    place: campoMourao,
    countryCode: "br",
    countryName: "Brasil",
  });
  assert.equal(g.stateCode, "PR");
  assert.equal(g.stateKey, "br-pr");
  assert.equal(g.geohash3, encodeGroupGeohash(-24.0459, -52.3831, 3));
  assert.equal(g.geohash3, "6gd");
  assert.equal(g.regionCenterGeohash, "");
});

test("região grava os mesmos campos e mantém o geohash da região", () => {
  const g = buildCanonicalGeoFields("region", {
    place: { ...campoMourao, stateName: "Paraná" },
    countryCode: "br",
  });
  assert.equal(g.stateCode, "PR");
  assert.equal(g.stateKey, "br-pr");
  assert.equal(g.geohash3, "6gd");
  assert.equal(g.regionCenterGeohash, "6gd");
});

test("grupo nacional não tem estado nem geohash", () => {
  const g = buildCanonicalGeoFields("country", {
    countryCode: "br",
    countryName: "Brasil",
  });
  assert.equal(g.stateCode, "");
  assert.equal(g.stateKey, "");
  assert.equal(g.geohash3, "");
});

test("createGroup grava os 3 campos e updateGroupSettings bloqueia o cliente", () => {
  const src = require("fs").readFileSync(require("path").join(__dirname, "index.js"), "utf8");
  const create = src.slice(src.indexOf("exports.createGroup ="));
  assert.match(create, /stateCode: payload\.stateCode/);
  assert.match(create, /stateKey: payload\.stateKey/);
  assert.match(create, /geohash3: payload\.geohash3/);
  const update = src.slice(
    src.indexOf("exports.updateGroupSettings ="),
    src.indexOf("exports.createGroup ="),
  );
  const blocked = update.slice(update.indexOf("blockedDirectGeo"), update.indexOf("];", update.indexOf("blockedDirectGeo")));
  for (const k of ["stateCode", "stateKey", "geohash3"]) {
    assert.ok(blocked.includes(`"${k}"`), k);
  }
});

test("backfill: plano só com os 3 campos, a partir do doc", () => {
  const { planFor, diffFor } = require("./scripts/backfill_group_geo_state");
  const data = {
    scope: "city", countryCode: "br", stateName: "PR",
    latitude: -24.0459, longitude: -52.3831, name: "Amigos De CM",
  };
  const plan = planFor(data);
  assert.deepEqual(plan, { stateCode: "PR", stateKey: "br-pr", geohash3: "6gd" });
  assert.deepEqual(diffFor(data, plan), plan);
  assert.deepEqual(diffFor({ ...data, ...plan }, plan), {});
  assert.deepEqual(planFor({ scope: "country", countryCode: "br" }), {
    stateCode: "", stateKey: "", geohash3: "",
  });
});
