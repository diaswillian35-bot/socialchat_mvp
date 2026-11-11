/**
 * Backfill da tradução única das descrições de locais JÁ aprovados (build 44).
 * Só grava `places/{id}.descriptionI18n` e o espelho no cache legado
 * `placeDescriptionTranslations` (o mesmo que a página /l/ já lê).
 * Não mexe em `description` nem em nenhum outro campo.
 *
 * Uso:
 *   # Dry-run (padrão — NÃO escreve, NÃO chama a API de tradução):
 *   node scripts/backfill_place_description_i18n.js [--out DIR]
 *   # Dry-run offline a partir de um export JSON (lista REST ou [{id,...}]):
 *   node scripts/backfill_place_description_i18n.js --input places.json \
 *     [--cache placeDescriptionTranslations.json] [--out DIR]
 *
 *   # Execução real (SÓ com OK do Willian). Exige o kill switch ligado e
 *   # respeita os mesmos limites diário/mensal do callable:
 *   PLACE_DESCRIPTION_TRANSLATION_ENABLED=true \
 *     node scripts/backfill_place_description_i18n.js --execute --out DIR
 *
 *   # Rollback: restaura descriptionI18n de antes e apaga do cache só os docs
 *   # que o --execute criou (os contadores de uso não voltam: já foi cobrado):
 *   node scripts/backfill_place_description_i18n.js --rollback DIR/antes_<ts>.json
 */
"use strict";

const fs = require("fs");
const path = require("path");
const c = require("../place_description_cache");
const i18n = require("../place_description_i18n");
const { LIMITS } = require("../place_description_translate");

// Cloud Translation Basic (v2): US$ 20 por 1 milhão de caracteres; os
// primeiros 500 mil caracteres/mês são gratuitos (conta de faturamento).
const USD_PER_MILLION = 20;
const FREE_MONTHLY = 500000;

function argValue(args, name) {
  const i = args.indexOf(name);
  return i < 0 ? null : args[i + 1] || null;
}
function fromRest(v) {
  if (v === null || v === undefined || typeof v !== "object") return v;
  if ("stringValue" in v) return v.stringValue;
  if ("doubleValue" in v) return Number(v.doubleValue);
  if ("integerValue" in v) return Number(v.integerValue);
  if ("booleanValue" in v) return v.booleanValue;
  if ("nullValue" in v) return null;
  if ("timestampValue" in v) return v.timestampValue;
  if ("mapValue" in v) {
    const out = {};
    for (const [k, x] of Object.entries(v.mapValue.fields || {})) out[k] = fromRest(x);
    return out;
  }
  if ("arrayValue" in v) return (v.arrayValue.values || []).map(fromRest);
  return v;
}
function loadInput(file) {
  const raw = JSON.parse(fs.readFileSync(file, "utf8"));
  const list = Array.isArray(raw) ? raw : raw.documents || [];
  return list.map((d) => {
    if (d.fields) {
      const data = {};
      for (const [k, v] of Object.entries(d.fields)) data[k] = fromRest(v);
      return { id: d.name.split("/").pop(), data };
    }
    const { id, ...data } = d;
    return { id, data };
  });
}

/** Plano por local (puro): precisa traduzir? quantos caracteres no pior caso? */
function cacheIndexFrom(rows) {
  const idx = new Map();
  for (const r of rows || []) idx.set(r.id, r.data || {});
  return idx;
}

/** Caracteres esperados reaproveitando idioma/traduções já pagos no cache legado. */
function expectedFor(id, data, cacheIdx) {
  const text = typeof data.description === "string" ? data.description : "";
  const count = Array.from(text).length;
  if (!count || !cacheIdx) return null;
  const h = c.hash(text);
  const source = String(cacheIdx.get(c.sourceId(id, h))?.language || "");
  const targets = source ? i18n.targetsFor(source) : i18n.TARGETS.slice(0, 4);
  const missing = targets.filter((t) => {
    const key = i18n.LEGACY_KEY[t];
    if (!key) return true;
    const row = cacheIdx.get(c.cacheId(id, key, h));
    return !(row && row.status === "ready" && row.sourceHash === h && c.language(row.sourceLanguage) !== key);
  });
  const detect = source ? 0 : Math.min(count, i18n.DETECT_SAMPLE);
  return { sourceLanguage: source || "?", targets: missing, characters: detect + count * missing.length };
}

function planFor(id, data, cacheIdx = null) {
  const text = typeof data.description === "string" ? data.description : "";
  const isPublic = c.isPublic(data);
  const need = i18n.needsTranslation(data, { retry: true });
  const e = i18n.estimateCharacters(data);
  let reason = "traduzir";
  if (!isPublic) reason = "pular (não publicado)";
  else if (!text.trim()) reason = "pular (sem descrição)";
  else if (!need) reason = "pular (já traduzido p/ este texto)";
  else if (e.count > LIMITS.perCall) reason = "pular (texto > limite)";
  const plan = {
    id, name: String(data.name || ""), city: String(data.cityName || ""),
    published: isPublic, chars: e.count,
    estimated: need && e.count <= LIMITS.perCall ? e.characters : 0,
    expected: null,
    sourceHash: text ? c.hash(text) : "", current: data[i18n.FIELD] ? data[i18n.FIELD].status || "?" : "",
    action: reason,
  };
  if (need && e.count <= LIMITS.perCall) plan.expected = expectedFor(id, data, cacheIdx);
  return plan;
}

function summarize(plans) {
  const todo = plans.filter((p) => p.estimated > 0);
  const characters = todo.reduce((n, p) => n + p.estimated, 0);
  return {
    published: plans.filter((p) => p.published).length,
    toTranslate: todo.length,
    sourceCharacters: todo.reduce((n, p) => n + p.chars, 0),
    billedCharactersWorstCase: characters,
    billedCharactersExpected: todo.every((p) => p.expected) ? todo.reduce((n, p) => n + p.expected.characters, 0) : null,
    usdWithoutFreeTier: Number(((characters / 1e6) * USD_PER_MILLION).toFixed(4)),
    usdIfInsideFreeTier: characters <= FREE_MONTHLY ? 0 : Number((((characters - FREE_MONTHLY) / 1e6) * USD_PER_MILLION).toFixed(4)),
    daysAtDailyCap: Math.ceil(characters / LIMITS.daily) || 0,
    dailyCap: LIMITS.daily, monthlyCap: LIMITS.monthly,
  };
}

function printTable(plans) {
  console.log("id | nome | cidade | publicado | chars | pior caso | esperado (origem; destinos) | atual | ação");
  for (const p of plans) {
    const exp = p.expected ? `${p.expected.characters} (${p.expected.sourceLanguage}; ${p.expected.targets.join(",")})` : "-";
    console.log([p.id, p.name, p.city, p.published ? "sim" : "não", p.chars, p.estimated, exp, p.current || "-", p.action].join(" | "));
  }
}

function getDb() {
  const admin = require("firebase-admin");
  if (!admin.apps.length) admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || "socialchatmvp" });
  return admin.firestore();
}

async function readPlaces(db) {
  const snap = await db.collection("places").get();
  return snap.docs.map((d) => ({ id: d.id, data: d.data() }));
}

async function main() {
  const args = process.argv.slice(2);
  const outDir = argValue(args, "--out") || process.cwd();
  const input = argValue(args, "--input");
  const rollback = argValue(args, "--rollback");
  const execute = args.includes("--execute");
  const ts = new Date().toISOString().replace(/[:.]/g, "-");
  fs.mkdirSync(outDir, { recursive: true });

  if (rollback) {
    const db = getDb();
    const before = JSON.parse(fs.readFileSync(rollback, "utf8"));
    const admin = require("firebase-admin");
    for (const row of before.places || []) {
      const ref = db.collection("places").doc(row.id);
      await ref.update({ [i18n.FIELD]: row.previous == null ? admin.firestore.FieldValue.delete() : row.previous });
    }
    for (const id of before.createdCacheDocs || []) await db.collection(c.CACHE).doc(id).delete();
    console.log(JSON.stringify({ mode: "rollback", places: (before.places || []).length, cacheDocsDeleted: (before.createdCacheDocs || []).length }));
    return;
  }
  if (execute && input) throw new Error("--execute não aceita --input (lê do Firestore)");

  const rows = input ? loadInput(input) : await readPlaces(getDb());
  const cacheFile = argValue(args, "--cache");
  let cacheIdx = null;
  if (cacheFile) cacheIdx = cacheIndexFrom(loadInput(cacheFile));
  else if (!input) cacheIdx = cacheIndexFrom((await getDb().collection(c.CACHE).get()).docs.map((d) => ({ id: d.id, data: d.data() })));
  const plans = rows.map((r) => planFor(r.id, r.data, cacheIdx)).sort((a, b) => a.id.localeCompare(b.id));
  const summary = summarize(plans);
  printTable(plans);

  if (!execute) {
    const file = path.join(outDir, `dryrun_traducao_locais_${ts}.json`);
    fs.writeFileSync(file, JSON.stringify({ mode: "dry-run", summary, plans }, null, 2));
    console.log(JSON.stringify({ mode: "dry-run", ...summary, report: file }));
    return;
  }

  if (process.env.PLACE_DESCRIPTION_TRANSLATION_ENABLED !== "true") {
    throw new Error("kill switch desligado: defina PLACE_DESCRIPTION_TRANSLATION_ENABLED=true para --execute");
  }
  const db = getDb();
  const todo = plans.filter((p) => p.estimated > 0);
  const byId = new Map(rows.map((r) => [r.id, r.data]));
  const backup = { mode: "antes", at: ts, places: [], createdCacheDocs: [] };
  for (const p of todo) {
    backup.places.push({ id: p.id, previous: byId.get(p.id)[i18n.FIELD] || null });
    for (const key of Object.values(i18n.LEGACY_KEY)) {
      const id = c.cacheId(p.id, key, p.sourceHash);
      if (!(await db.collection(c.CACHE).doc(id).get()).exists) backup.createdCacheDocs.push(id);
    }
    const sid = c.sourceId(p.id, p.sourceHash);
    if (!(await db.collection(c.CACHE).doc(sid).get()).exists) backup.createdCacheDocs.push(sid);
  }
  const backupFile = path.join(outDir, `antes_traducao_locais_${ts}.json`);
  fs.writeFileSync(backupFile, JSON.stringify(backup, null, 2));
  const results = [];
  for (const p of todo) {
    const r = await i18n.translatePlaceOnApproval(p.id, { db, retry: true, enabled: true });
    results.push({ id: p.id, ...r });
    console.log(p.id, r.outcome);
    if (r.outcome === "quota") { console.log("limite diário/mensal atingido: parando"); break; }
  }
  const file = path.join(outDir, `execute_traducao_locais_${ts}.json`);
  fs.writeFileSync(file, JSON.stringify({ mode: "execute", backup: backupFile, results }, null, 2));
  console.log(JSON.stringify({ mode: "execute", done: results.length, backup: backupFile, report: file }));
}

if (require.main === module) {
  main().catch((e) => { console.error(e.message || e); process.exitCode = 1; });
}
module.exports = { planFor, summarize, loadInput, fromRest, expectedFor, cacheIndexFrom };
