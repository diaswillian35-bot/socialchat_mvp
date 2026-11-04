const test = require("node:test");
const assert = require("node:assert/strict");
const { WINDOW_MS, eventsInWindow, nextStrikeEvents } = require("./strikes");

test("strike fora de 30 dias não entra na contagem", () => {
  const now = Date.UTC(2026, 10, 4);
  const old = now - WINDOW_MS - 1000;
  const recent = now - 1000;
  assert.deepEqual(eventsInWindow([old, recent], now), [recent]);
  const next = nextStrikeEvents([old, recent], now);
  assert.equal(next.length, 2);
  assert.equal(next.includes(old), false);
  assert.equal(next.includes(now), true);
});
