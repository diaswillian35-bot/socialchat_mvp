"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const { validateAdultDate } = require("./age_verification_logic");

const now = new Date("2026-08-15T23:30:00Z");

test("accepts a person turning 18 today", () => {
  assert.equal(validateAdultDate("2008-08-15", now).adult, true);
});

test("rejects a person turning 18 tomorrow", () => {
  assert.equal(validateAdultDate("2008-08-16", now).adult, false);
});

test("handles February 29 by calendar components", () => {
  assert.equal(validateAdultDate("2008-02-29", new Date("2026-02-28T12:00:00Z")).adult, false);
  assert.equal(validateAdultDate("2008-02-29", new Date("2026-03-01T12:00:00Z")).adult, true);
});

test("rejects future, impossible, and excessively old dates", () => {
  assert.equal(validateAdultDate("2027-01-01", now).valid, false);
  assert.equal(validateAdultDate("2008-02-30", now).valid, false);
  assert.equal(validateAdultDate("1800-01-01", now).valid, false);
});

test("social push delivery requires verified age status", () => {
  const indexSource = fs.readFileSync("index.js", "utf8");
  assert.match(indexSource,
    /function pushAllowed[\s\S]*ageVerificationStatus !== "verified"/);
});
