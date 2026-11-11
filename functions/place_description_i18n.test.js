"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const c = require("./place_description_cache");
const { LIMITS, periods } = require("./place_description_translate");
const i18n = require("./place_description_i18n");

const description = "Hambúrguer artesanal feito com amor";
const published = () => ({ schemaVersion: 1, active: true, deleted: false, moderationStatus: "published", description });
const NOW = new Date("2026-11-11T20:00:00Z");

function fakeDb(place) {
  const docs = new Map([["places/P1", place]]);
  let chain = Promise.resolve();
  const ref = (path) => ({ path,
    get: async () => ({ exists: docs.has(path), data: () => docs.get(path) }),
    set: async (v) => { docs.set(path, v); } });
  const apply = (op) => {
    const [kind, path, v] = op;
    if (kind === "set") docs.set(path, v); else docs.set(path, { ...docs.get(path), ...v });
  };
  const db = {
    collection: (name) => ({ doc: (id) => ref(`${name}/${id}`) }),
    batch: () => { const ops = []; return { set: (r, v) => ops.push(["set", r.path, v]), commit: async () => ops.forEach(apply) }; },
    runTransaction: (fn) => {
      const job = chain.then(async () => {
        const ops = [];
        const out = await fn({ get: (r) => r.get(), set: (r, v) => ops.push(["set", r.path, v]), update: (r, v) => ops.push(["update", r.path, v]) });
        ops.forEach(apply); return out;
      });
      chain = job.catch(() => {}); return job;
    },
  };
  return { db, docs };
}
function deps(db, extra = {}) {
  const calls = { translate: [], detect: 0 };
  return { calls, deps: { db, enabled: true, now: NOW,
    detect: async () => { calls.detect++; return "pt"; },
    translate: async (text, target) => { calls.translate.push(target); return { text: `T-${target}`, sourceLanguage: "pt" }; },
    ...extra } };
}

test("translates once into the 4 non-source languages and keeps the original", async () => {
  const { db, docs } = fakeDb(published());
  const { calls, deps: d } = deps(db);
  const r = await i18n.translatePlaceOnApproval("P1", d);
  assert.equal(r.outcome, "ready");
  const place = docs.get("places/P1");
  assert.equal(place.description, description);
  assert.equal(place.descriptionI18n.sourceHash, c.hash(description));
  assert.equal(place.descriptionI18n.sourceLanguage, "pt");
  assert.deepEqual(Object.keys(place.descriptionI18n.texts).sort(), ["en", "es", "fr"]);
  assert.deepEqual(calls.translate.sort(), ["en", "es", "fr"]);
  assert.equal(calls.detect, 1);
  // A second run (trigger fired by our own write) does nothing.
  assert.equal(i18n.shouldHandleWrite(null, place), false);
  assert.equal((await i18n.translatePlaceOnApproval("P1", d)).outcome, "not_needed");
  assert.equal(calls.translate.length, 3);
  // Mirrored into the legacy cache read by /l/ and by the old callable.
  assert.equal(await c.readCachedDescription(db, "P1", description, "en"), "T-en");
  assert.equal(await c.readCachedDescription(db, "P1", description, "pt-BR"), null);
});

test("english source translates to pt-BR, pt-PT, es, fr with Google codes", async () => {
  const { db, docs } = fakeDb(published());
  const { calls, deps: d } = deps(db, { detect: async () => "en" });
  assert.equal((await i18n.translatePlaceOnApproval("P1", d)).outcome, "ready");
  assert.deepEqual(calls.translate.sort(), ["es", "fr", "pt", "pt-PT"]);
  assert.deepEqual(Object.keys(docs.get("places/P1").descriptionI18n.texts).sort(), ["es", "fr", "pt-BR", "pt-PT"]);
  assert.equal(await c.readCachedDescription(db, "P1", description, "pt-PT"), "T-pt");
});

test("description change re-translates; same text never does", async () => {
  const { db, docs } = fakeDb(published());
  const { calls, deps: d } = deps(db);
  await i18n.translatePlaceOnApproval("P1", d);
  const edited = { ...docs.get("places/P1"), description: "Novo texto do local" };
  assert.equal(i18n.shouldHandleWrite(null, edited), true);
  docs.set("places/P1", edited);
  await i18n.translatePlaceOnApproval("P1", d);
  assert.equal(calls.translate.length, 6);
  assert.equal(docs.get("places/P1").descriptionI18n.sourceHash, c.hash("Novo texto do local"));
});

test("pending / rejected / deleted places are not translated", () => {
  for (const patch of [{ moderationStatus: "pending" }, { moderationStatus: "rejected" }, { deleted: true }, { active: false }, { description: "  " }]) {
    assert.equal(i18n.needsTranslation({ ...published(), ...patch }), false);
  }
});

test("kill switch off: no provider call and no write", async () => {
  const { db, docs } = fakeDb(published());
  const { calls, deps: d } = deps(db, { enabled: false });
  assert.equal((await i18n.translatePlaceOnApproval("P1", d)).outcome, "disabled");
  assert.equal(calls.translate.length + calls.detect, 0);
  assert.equal(docs.get("places/P1").descriptionI18n, undefined);
});

test("shared daily cap blocks spending and marks quota; backfill retry can resume", async () => {
  const { db, docs } = fakeDb(published());
  docs.set(`placeDescriptionTranslationUsage/day_${periods(NOW).day}`, { characters: LIMITS.daily });
  const { calls, deps: d } = deps(db);
  assert.equal((await i18n.translatePlaceOnApproval("P1", d)).outcome, "quota");
  assert.equal(calls.translate.length + calls.detect, 0);
  assert.equal(docs.get("places/P1").descriptionI18n.status, "quota");
  assert.equal(i18n.needsTranslation(docs.get("places/P1")), false);
  assert.equal(i18n.needsTranslation(docs.get("places/P1"), { retry: true }), true);
  docs.set(`placeDescriptionTranslationUsage/day_${periods(NOW).day}`, { characters: 0 });
  assert.equal((await i18n.translatePlaceOnApproval("P1", { ...d, retry: true })).outcome, "ready");
});

test("usage counters are charged: detection sample + text x missing targets", async () => {
  const { db, docs } = fakeDb(published());
  const { deps: d } = deps(db);
  await i18n.translatePlaceOnApproval("P1", d);
  const n = Array.from(description).length;
  assert.equal(docs.get(`placeDescriptionTranslationUsage/day_${periods(NOW).day}`).characters, n + n * 3);
});

test("reuses translations already paid for by the old callable cache", async () => {
  const { db, docs } = fakeDb(published());
  const h = c.hash(description);
  docs.set(`${c.CACHE}/P1_en_${h}`, { status: "ready", sourceHash: h, targetLanguage: "en", sourceLanguage: "pt", text: "Cached EN" });
  const { calls, deps: d } = deps(db);
  assert.equal((await i18n.translatePlaceOnApproval("P1", d)).outcome, "ready");
  assert.equal(calls.detect, 0);
  assert.deepEqual(calls.translate.sort(), ["es", "fr"]);
  assert.equal(docs.get("places/P1").descriptionI18n.texts.en, "Cached EN");
});

test("provider failure never throws; partial result is stored", async () => {
  const { db, docs } = fakeDb(published());
  const { deps: d } = deps(db, { translate: async (t, target) => { if (target === "fr") throw new Error("x"); return { text: `T-${target}` }; } });
  assert.equal((await i18n.translatePlaceOnApproval("P1", d)).outcome, "partial");
  assert.equal(docs.get("places/P1").descriptionI18n.texts.fr, undefined);
  const boom = await i18n.translatePlaceOnApproval("P1", { ...d, retry: true, db: { collection: () => { throw new Error("db down"); } } });
  assert.equal(boom.outcome, "error");
});

test("late response never overwrites a newer description", async () => {
  const { db, docs } = fakeDb(published());
  const { deps: d } = deps(db, { translate: async (t, target) => {
    docs.set("places/P1", { ...docs.get("places/P1"), description: "Mudou durante a tradução" });
    return { text: `T-${target}` };
  } });
  assert.equal((await i18n.translatePlaceOnApproval("P1", d)).outcome, "source_changed");
  assert.equal(docs.get("places/P1").descriptionI18n, undefined);
});

test("estimate: detection sample + 4 targets", () => {
  const e = i18n.estimateCharacters({ description: "x".repeat(1000) });
  assert.deepEqual(e, { count: 1000, detect: 300, targets: 4, characters: 4300 });
});
