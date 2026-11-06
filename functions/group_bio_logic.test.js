"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const fs = require("node:fs");
const path = require("node:path");
const { GROUP_BIO_MAX_LENGTH, normalizeGroupBio } = require("./group_bio_logic");

function mixedBio(length) {
  const seed = "🎉👨‍👩‍👧 acentuação ção".repeat(80);
  assert.ok(seed.length < length);
  return seed.padEnd(length, "a");
}

for (const operation of ["createGroup", "updateGroupSettings"]) {
  test(`${operation}: shared validation accepts 2900 UTF-16 units with emoji`, () => {
    const bio = mixedBio(2900);
    assert.equal(bio.length, 2900);
    assert.equal(normalizeGroupBio(bio), bio);
    assert.equal(normalizeGroupBio(`  ${bio}  `), bio);
    assert.ok(Buffer.byteLength(bio, "utf8") < 12000);
  });
  test(`${operation}: exactly 3000 passes; 3001 fails`, () => {
    assert.equal(GROUP_BIO_MAX_LENGTH, 3000);
    assert.equal(normalizeGroupBio(mixedBio(3000)).length, 3000);
    assert.throws(() => normalizeGroupBio(mixedBio(3001)), {
      code: "invalid-argument", message: "Bio too long.",
    });
  });
}

test("both real handlers are wired to the shared validator", () => {
  const src = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
  const update = src.slice(src.indexOf("exports.updateGroupSettings ="),
    src.indexOf("const GROUP_CREATE_ALLOWED"));
  const create = src.slice(src.indexOf("exports.createGroup ="));
  assert.match(update, /value = validatedGroupBio\(value\)/);
  assert.match(create, /const bio = validatedGroupBio\(dataIn.bio\)/);
  assert.match(src, /return normalizeGroupBio\(value\)/);
  assert.match(src, /throw new HttpsError\(error.code, error.message\)/);
});

test("optional bio normalization is unchanged", () => {
  assert.equal(normalizeGroupBio(undefined), "");
  assert.equal(normalizeGroupBio("  oi 🎉  "), "oi 🎉");
});
