const test = require("node:test");
const assert = require("node:assert/strict");
const { ladderStep, moderationPatch, isMutedNow, ladderConfig, DAY } = require("./ladder");
const { nextStrikeEvents, WINDOW_MS } = require("./strikes");

const NOW = Date.UTC(2026, 10, 9, 20, 0);
const H = 3600 * 1000;

test("degraus: 1 aviso, 2 = 24 h, 3 = 7 dias, 4 = banimento pendente", () => {
  assert.deepEqual(ladderStep(1, NOW, {}), { level: 1, action: "warn" });
  assert.deepEqual(ladderStep(2, NOW, {}), { level: 2, action: "mute", mutedUntilMs: NOW + 24 * H });
  assert.deepEqual(ladderStep(3, NOW, {}), { level: 3, action: "mute", mutedUntilMs: NOW + 168 * H });
  assert.deepEqual(ladderStep(4, NOW, {}), { level: 4, action: "suspend" });
  assert.deepEqual(ladderStep(9, NOW, {}), { level: 4, action: "suspend" });
});

test("pontos expiram em 90 dias", () => {
  assert.equal(WINDOW_MS, 90 * DAY);
  assert.equal(ladderConfig({}).windowMs, 90 * DAY);
  const old = NOW - 91 * DAY;
  const recent = NOW - 10 * DAY;
  assert.deepEqual(nextStrikeEvents([old, recent], NOW, 90 * DAY), [recent, NOW]);
});

test("config muda janela e horas sem deploy", () => {
  assert.equal(ladderConfig({ ladder: { windowDays: 30 } }).windowMs, 30 * DAY);
  assert.deepEqual(ladderStep(2, NOW, { ladder: { muteHours: [12, 48] } }).mutedUntilMs, NOW + 12 * H);
});

test("nunca rebaixa banido/suspenso nem encurta sem falar", () => {
  assert.equal(moderationPatch({ status: "banned" }, { level: 1, action: "warn" }, NOW), null);
  assert.equal(moderationPatch({ status: "suspended_pending_review" }, { level: 2, action: "mute", mutedUntilMs: NOW + H }, NOW), null);
  const p = moderationPatch({ status: "muted", mutedUntil: NOW + 100 * H }, { level: 2, action: "mute", mutedUntilMs: NOW + 24 * H }, NOW);
  assert.equal(p.mutedUntilMs, NOW + 100 * H);
  assert.equal(moderationPatch(null, { level: 4, action: "suspend" }, NOW).status, "suspended_pending_review");
});

test("isMutedNow respeita o prazo", () => {
  assert.equal(isMutedNow({ moderation: { status: "muted", mutedUntil: { toMillis: () => NOW + H } } }, NOW), true);
  assert.equal(isMutedNow({ moderation: { status: "muted", mutedUntil: { toMillis: () => NOW - H } } }, NOW), false);
  assert.equal(isMutedNow({ moderation: { status: "warned" } }, NOW), false);
  assert.equal(isMutedNow({}, NOW), false);
});
