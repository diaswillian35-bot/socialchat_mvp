"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");

test("places package keeps client writes server-only and manager storage scoped", () => {
  const firestore = fs.readFileSync("../firestore.rules", "utf8");
  const storage = fs.readFileSync("../storage.rules", "utf8");
  const indexes = fs.readFileSync("../firestore.indexes.json", "utf8");
  assert.match(firestore, /match \/places\/\{placeId\}/);
  assert.match(firestore, /allow write: if false/);
  assert.match(firestore, /match \/placeReports\/\{reportId\}/);
  assert.match(storage, /match \/places\/\{placeId\}\/menu\/\{fileName\}/);
  assert.match(storage, /application\/pdf/);
  assert.match(indexes, /"collectionGroup": "places"/);
  assert.match(indexes, /"fieldPath": "placeGeohash"/);
});
