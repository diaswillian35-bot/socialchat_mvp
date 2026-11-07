"use strict";
const test = require("node:test");
const assert = require("assert");
const {
  validateEventEditorial,
  EVENT_ALLOWED_CATEGORIES,
  normalizeEventCategory,
} = require("./event_editorial");

test("Cultural continua aceita (apps antigos)", () => {
  assert.ok(EVENT_ALLOWED_CATEGORIES.has("Cultural"));
  assert.ok(EVENT_ALLOWED_CATEGORIES.has("Cultura"));
});

test("normalizeEventCategory: Cultural -> Cultura; demais intactas", () => {
  assert.strictEqual(normalizeEventCategory("Cultural"), "Cultura");
  for (const c of EVENT_ALLOWED_CATEGORIES) {
    if (c !== "Cultural") assert.strictEqual(normalizeEventCategory(c), c);
  }
  assert.strictEqual(normalizeEventCategory(""), "");
});

test("update parcial com Cultural grava Cultura", () => {
  const e = validateEventEditorial({ category: "Cultural" }, { forUpdate: true });
  assert.strictEqual(e.category, "Cultura");
});

test("update parcial com Show fica Show; inválida rejeita", () => {
  assert.strictEqual(
    validateEventEditorial({ category: "Show" }, { forUpdate: true }).category,
    "Show",
  );
  assert.throws(() =>
    validateEventEditorial({ category: "Xyz" }, { forUpdate: true }));
});
