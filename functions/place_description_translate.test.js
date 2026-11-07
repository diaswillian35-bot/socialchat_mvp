"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const c = require("./place_description_cache");
const { LIMITS, periods, translatePlaceDescriptionHandler: handle } = require("./place_description_translate");
const description = "Hambúrguer 🍔 feito com amor";
const published = { schemaVersion: 1, active: true, deleted: false, moderationStatus: "published", description };
function fakeDb() {
  const docs = new Map([["places/JohnID", published]]);
  let chain = Promise.resolve();
  const ref = path => ({ path, get: async () => ({ exists: docs.has(path), data: () => docs.get(path) }),
    set: async value => { docs.set(path, value); } });
  const db = { collection: name => ({ doc: id => ref(`${name}/${id}`) }),
    runTransaction: fn => {
      const job = chain.then(async () => {
        const pending = [];
        const result = await fn({ get: r => r.get(), set: (r, v) => pending.push([r.path, v]) });
        for (const [k, v] of pending) docs.set(k, v);
        return result;
      });
      chain = job.catch(() => {}); return job;
    } };
  return { db, docs };
}
const request = (lang = "en", text = description) => ({ auth: { uid: "adult" }, data: { placeId: "JohnID", language: lang, sourceHash: c.hash(text) } });
function setup(extra = {}) {
  const { db, docs } = fakeDb(); let calls = 0;
  const deps = { db, enabled: true, now: new Date("2026-11-07T01:00:00Z"), translate: async () => { calls++; return { text: "Burger made with love", sourceLanguage: "pt" }; }, ...extra };
  return { db, docs, deps, calls: () => calls };
}
test("one provider attempt across repeated and concurrent views, cache hit no writes", async () => {
  const s = setup(); const results = await Promise.all(Array.from({ length: 20 }, () => handle(request(), s.deps)));
  assert.equal(s.calls(), 1); assert.ok(results.some(r => r.translated));
  const before = JSON.stringify([...s.docs]); const hit = await handle(request(), s.deps);
  assert.equal(hit.text, "Burger made with love"); assert.equal(JSON.stringify([...s.docs]), before);
  assert.equal(s.docs.get("placeDescriptionTranslationUsage/month_2026-11").characters, Array.from(description).length);
});
test("same source language displays original; pt variants share the detected language", async () => {
  const s = setup(); await handle(request(), s.deps);
  for (const lang of ["pt-BR", "pt-PT", "pt"]) assert.equal((await handle(request(lang), s.deps)).reason, "same_language");
  assert.equal(s.calls(), 1);
});
test("first unknown source matching target returns original and caches detection once", async () => {
  const s = setup(); assert.equal((await handle(request("pt-PT"), s.deps)).reason, "same_language");
  await handle(request("pt-BR"), s.deps); assert.equal(s.calls(), 1);
});
for (const field of ["active", "deleted", "moderationStatus", "schemaVersion"]) test(`private/inactive source rejected: ${field}`, async () => {
  const s = setup(); s.docs.set("places/JohnID", { ...published, [field]: { active: false, deleted: true, moderationStatus: "pending", schemaVersion: 2 }[field] });
  assert.equal((await handle(request(), s.deps)).translated, false); assert.equal(s.calls(), 0); assert.equal(s.docs.size, 1);
});
test("authentication and payload validation reject before any write", async () => {
  const s = setup(); await assert.rejects(handle({ data: request().data }, s.deps), e => e.code === "unauthenticated");
  for (const patch of [{ placeId: "../private" }, { language: "de" }, { sourceHash: "wrong" }])
    await assert.rejects(handle({ ...request(), data: { ...request().data, ...patch } }, s.deps), e => e.code === "invalid-argument");
  assert.equal(s.calls(), 0); assert.equal(s.docs.size, 1);
});
test("feature is off by default and even disabled serves only existing cache", async () => {
  const s = setup({ enabled: false }); assert.equal((await handle(request(), s.deps)).reason, "disabled");
  assert.equal(s.calls(), 0); assert.equal(s.docs.size, 1);
  await handle(request(), { ...s.deps, enabled: true }); assert.ok((await handle(request(), s.deps)).translated);
});
test("stale hash, empty and oversized input never reach provider", async () => {
  const s = setup(); assert.equal((await handle(request("en", "old"), s.deps)).translated, false);
  for (const value of ["", "a".repeat(LIMITS.perCall + 1)]) {
    s.docs.set("places/JohnID", { ...published, description: value });
    assert.equal((await handle(request("en", value), s.deps)).translated, false);
  }
  assert.equal(s.calls(), 0);
});
for (const bucket of ["daily", "monthly", "userDaily"]) test(`${bucket} limit is fail closed`, async () => {
  const s = setup(); const ids = { daily: "day_2026-11-06", monthly: "month_2026-11", userDaily: `user_${c.hash("adult")}_2026-11-06` };
  s.docs.set(`placeDescriptionTranslationUsage/${ids[bucket]}`, bucket === "userDaily" ? { calls: LIMITS.userDaily } : { characters: LIMITS[bucket] });
  assert.equal((await handle(request(), s.deps)).reason, "reserved_or_quota"); assert.equal(s.calls(), 0);
});
test("failed provider and abandoned reservations are never retried or refunded", async () => {
  const s = setup(); let calls = 0;
  s.deps.translate = async () => { calls++; throw new Error("timeout contains private provider data"); };
  assert.equal((await handle(request(), s.deps)).reason, "translation_failed");
  assert.equal((await handle(request(), s.deps)).reason, "already_attempted"); assert.equal(calls, 1);
  const path = `${c.CACHE}/${c.cacheId("JohnID", "fr", c.hash(description))}`;
  s.docs.set(path, { status: "reserved" }); await handle(request("fr"), s.deps); assert.equal(calls, 1);
  assert.ok(s.docs.get("placeDescriptionTranslationUsage/month_2026-11").characters > 0);
});
test("editing the source invalidates hash; old response cannot replace current description", async () => {
  const s = setup(); s.deps.translate = async () => {
    s.docs.set("places/JohnID", { ...published, description: "Novo original" });
    return { text: "Old translated", sourceLanguage: "pt" };
  };
  assert.equal((await handle(request(), s.deps)).reason, "source_changed");
  const old = s.docs.get(`${c.CACHE}/${c.cacheId("JohnID", "en", c.hash(description))}`);
  assert.equal(c.cachedText(old, "Novo original", "en"), null);
});
test("unpublishing mid-call hides the translation", async () => {
  const s = setup(); s.deps.translate = async () => { s.docs.set("places/JohnID", { ...published, active: false }); return { text: "Burger", sourceLanguage: "pt" }; };
  assert.equal((await handle(request(), s.deps)).translated, false);
});
test("invalid provider output fails once without exposing content", async () => {
  const s = setup({ translate: async () => ({ text: "x", sourceLanguage: "" }) });
  assert.equal((await handle(request(), s.deps)).reason, "translation_failed");
});
test("Pacific billing dates including month/DST boundaries", () => {
  assert.deepEqual(periods(new Date("2026-11-01T06:59:59Z")), { day: "2026-10-31", month: "2026-10" });
  assert.deepEqual(periods(new Date("2026-11-01T07:00:00Z")), { day: "2026-11-01", month: "2026-11" });
});
for (const lang of ["pt-BR", "pt-PT", "en", "es", "fr"]) test(`supported locale ${lang}`, () => {
  assert.ok(c.language(lang)); assert.equal(c.hash("á🍔").length, 64);
});
test("cache-only reader rejects stale or mismatched target and never writes", async () => {
  const s = setup(); await handle(request(), s.deps); const before = JSON.stringify([...s.docs]);
  assert.equal(await c.readCachedDescription(s.db, "JohnID", description, "en"), "Burger made with love");
  assert.equal(await c.readCachedDescription(s.db, "JohnID", "Changed", "en"), null);
  assert.equal(await c.readCachedDescription(s.db, "JohnID", description, "fr"), null);
  assert.equal(JSON.stringify([...s.docs]), before);
});

test("Basic adapter uses OAuth client, text format, one auto-detect request and no retry", async () => {
 const {translateBasic} = require("./place_description_translate"); let calls=0;
 const client={request:async options=>{
  calls++;assert.equal(options.url,"https://translation.googleapis.com/language/translate/v2");
  assert.equal(options.method,"POST");assert.equal(options.retry,false);assert.equal(options.retryConfig.retry,0);
  assert.deepEqual(options.data,{q:description,target:"en",format:"text",model:"nmt"});assert.ok(!options.data.key);
  return{data:{data:{translations:[{translatedText:"Burger",detectedSourceLanguage:"pt"}]}}};
 }};
 assert.deepEqual(await translateBasic(description,"en",{client}),{text:"Burger",sourceLanguage:"pt"});assert.equal(calls,1);
});
test("malformed quota counters fail closed", async()=>{
 const s=setup();s.docs.set("placeDescriptionTranslationUsage/month_2026-11",{characters:-1});
 assert.equal((await handle(request(),s.deps)).translated,false);assert.equal(s.calls(),0);
});
