const test = require("node:test");
const assert = require("node:assert/strict");
const { dmBlockedBetween, conversationHasHistory } = require("./dm_block_logic");

test("PV bloqueado nos dois sentidos, sem exceção", () => {
  const off = {};
  const on = { dmBlocked: true };
  const keep = { dmBlocked: true, dmAllowExisting: true };
  assert.equal(dmBlockedBetween(off, off, { hasHistory: false }), false);
  assert.equal(dmBlockedBetween(off, on, { hasHistory: false }), true);
  assert.equal(dmBlockedBetween(on, off, { hasHistory: true }), true);
  assert.equal(dmBlockedBetween(off, keep, { hasHistory: false }), true);
  assert.equal(dmBlockedBetween(off, keep, { hasHistory: true }), false);
  assert.equal(dmBlockedBetween(keep, off, { hasHistory: true }), false);
  assert.equal(dmBlockedBetween({ isAdmin: true }, on, { hasHistory: true }), true);
});

test("histórico = lastMessage não vazio", () => {
  assert.equal(conversationHasHistory({ lastMessage: "oi" }), true);
  assert.equal(conversationHasHistory({ lastMessage: "  " }), false);
  assert.equal(conversationHasHistory(null), false);
});
