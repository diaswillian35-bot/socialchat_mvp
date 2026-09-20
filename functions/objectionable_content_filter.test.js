/**
 * Pure Node tests for the UGC filter (no emulator).
 * Run: node --test objectionable_content_filter.test.js
 */
const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const { isObjectionableText } = require("./objectionable_content_filter");
const { sanitizeCommentText } = require("./event_interactions_helpers");

describe("objectionable_content_filter", () => {
  it("allows ordinary messages", () => {
    assert.equal(isObjectionableText("Oi, tudo bem?"), false);
    assert.equal(isObjectionableText("Hello from Toronto"), false);
    assert.equal(isObjectionableText(""), false);
    assert.equal(isObjectionableText(null), false);
  });

  it("blocks clearly objectionable phrases", () => {
    assert.equal(isObjectionableText("child porn link"), true);
    assert.equal(isObjectionableText("vou te matar agora"), true);
    assert.equal(isObjectionableText("pornografia infantil"), true);
    assert.equal(isObjectionableText("kill yourself please"), true);
  });

  it("blocks exact vou matar and locale equivalents, not food/time idioms", () => {
    for (const t of [
      "vou matar",
      "VOU MATAR",
      "vou matar.",
      "eu vou matar",
      "vou matar voce",
      "i will kill you",
      "gonna kill you",
      "voy a matar",
      "te voy a matar",
      "je vais te tuer",
    ]) {
      assert.equal(isObjectionableText(t), true, t);
    }
    for (const t of [
      "vou matar a fome",
      "matar saudade",
      "kill time at the airport",
      "just kill it",
      "skill issue",
      "the killer app",
      "voy a matar el hambre",
      "je vais tuer le temps",
      "Oi, tudo bem?",
    ]) {
      assert.equal(isObjectionableText(t), false, t);
    }
  });

  it("blocks event comments with the same filter", () => {
    assert.equal(sanitizeCommentText("hello friends").text, "hello friends");
    assert.equal(sanitizeCommentText("csam pack").error, "objectionable");
  });
});
