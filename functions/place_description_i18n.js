"use strict";
/**
 * Build 44: traduz a descrição de um local UMA vez, quando ele fica público
 * (aprovação no app, painel web ou edição de admin em local publicado).
 *
 * - Original fica intacto em `description`; versões vão em
 *   `places/{id}.descriptionI18n` (escrita só pelo servidor: Rules de places
 *   negam qualquer escrita de cliente).
 * - Só retraduz quando o hash do texto muda.
 * - Usa os MESMOS limites/contadores e o MESMO kill switch do callable
 *   translatePlaceDescription. Falha nunca bloqueia a aprovação (roda depois).
 * - Espelha pt/en/es/fr no cache legado `placeDescriptionTranslations`, que a
 *   página /l/ já lê: nenhuma mudança/redeploy da página é necessária.
 */
const admin = require("firebase-admin");
const { GoogleAuth } = require("google-auth-library");
const c = require("./place_description_cache");
const { LIMITS, periods, translateBasic } = require("./place_description_translate");

const FIELD = "descriptionI18n";
const VERSION = 1;
const TARGETS = Object.freeze(["pt-BR", "pt-PT", "en", "es", "fr"]);
// Código de destino no Google Translation v2 (Basic).
const GOOGLE_TARGET = Object.freeze({ "pt-BR": "pt", "pt-PT": "pt-PT", en: "en", es: "es", fr: "fr" });
// Chave do cache legado (o callable e a /l/ tratam pt-BR e pt-PT como "pt").
const LEGACY_KEY = Object.freeze({ "pt-BR": "pt", en: "en", es: "es", fr: "fr" });
const DETECT_SAMPLE = 300;
const MAX_TEXT = 20000;

const auth = new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/cloud-translation"] });

/** Detecta o idioma com uma amostra (cobra só a amostra). */
async function detectBasic(sample, { client: injectedClient } = {}) {
  const client = injectedClient || await auth.getClient();
  const result = await client.request({
    url: "https://translation.googleapis.com/language/translate/v2/detect",
    method: "POST", timeout: 15000, retry: false, retryConfig: { retry: 0 },
    data: { q: sample },
  });
  const lang = result.data?.data?.detections?.[0]?.[0]?.language;
  if (typeof lang !== "string" || !/^[a-z]{2,3}(-[a-z0-9]+)*$/i.test(lang)) {
    throw new Error("invalid_detection_response");
  }
  return lang.toLowerCase();
}

function sampleOf(text) { return Array.from(text).slice(0, DETECT_SAMPLE).join(""); }

/** Destinos que precisam de tradução: tira o idioma de origem (pt cobre pt-BR e pt-PT). */
function targetsFor(sourceLanguage) {
  const family = c.language(sourceLanguage);
  return TARGETS.filter((t) => c.language(t) !== family);
}

function storedTexts(i18n) {
  const out = {};
  const texts = i18n && typeof i18n.texts === "object" && i18n.texts ? i18n.texts : {};
  for (const t of TARGETS) {
    if (typeof texts[t] === "string" && texts[t] && texts[t].length <= MAX_TEXT) out[t] = texts[t];
  }
  return out;
}

/**
 * Precisa traduzir? Público, com descrição, e sem resultado para este hash.
 * `retry` (backfill) também refaz resultados não "ready" do mesmo hash.
 */
function needsTranslation(place, { retry = false } = {}) {
  if (!c.isPublic(place)) return false;
  const text = typeof place.description === "string" ? place.description : "";
  if (!text.trim()) return false;
  const i18n = place[FIELD];
  if (!i18n || i18n.sourceHash !== c.hash(text)) return true;
  return retry && i18n.status !== "ready" && i18n.status !== "source_only";
}

/** Gatilho: só reage quando o local está público e o hash ainda não foi tratado. */
function shouldHandleWrite(before, after) {
  if (!after) return false;
  return needsTranslation(after);
}

/**
 * Estimativa (backfill/dry-run) de caracteres cobrados: amostra de detecção
 * + texto × destinos, assumindo pior caso de 4 destinos quando a origem é
 * pt/en/es/fr e 5 quando desconhecida e não detectável pelo cache.
 */
function estimateCharacters(place) {
  const text = typeof place.description === "string" ? place.description : "";
  const count = Array.from(text).length;
  if (!count) return { count: 0, detect: 0, targets: 0, characters: 0 };
  const detect = Math.min(count, DETECT_SAMPLE);
  const targets = 4; // pt (2 variantes) ou en/es/fr: sempre 4 destinos fora da origem
  return { count, detect, targets, characters: detect + count * targets };
}

async function reserve(db, characters, now, placeRef, text) {
  const { day, month } = periods(now);
  const usage = db.collection("placeDescriptionTranslationUsage");
  const dayRef = usage.doc(`day_${day}`), monthRef = usage.doc(`month_${month}`);
  return db.runTransaction(async (tx) => {
    const [latest, daily, monthly] = await Promise.all([placeRef, dayRef, monthRef].map((r) => tx.get(r)));
    if (!c.isPublic(latest.data()) || latest.data().description !== text) return "source_changed";
    const dayCount = daily.data()?.characters || 0, monthCount = monthly.data()?.characters || 0;
    if (![dayCount, monthCount].every((n) => Number.isSafeInteger(n) && n >= 0)) return "quota";
    if (dayCount + characters > LIMITS.daily || monthCount + characters > LIMITS.monthly) return "quota";
    tx.set(dayRef, { characters: dayCount + characters });
    tx.set(monthRef, { characters: monthCount + characters });
    return "ok";
  });
}

/**
 * Traduz a descrição atual de um local para os 5 idiomas (menos a origem).
 * Nunca lança: devolve { outcome, ... }. `deps` permite testes/emulador.
 */
async function translatePlaceOnApproval(placeId, deps = {}) {
  const db = deps.db || admin.firestore();
  const now = deps.now || new Date();
  const translate = deps.translate || translateBasic;
  const detect = deps.detect || detectBasic;
  const enabled = deps.enabled ?? process.env.PLACE_DESCRIPTION_TRANSLATION_ENABLED === "true";
  try {
    const placeRef = db.collection("places").doc(placeId);
    const snap = await placeRef.get();
    const place = snap.exists ? snap.data() : null;
    if (!needsTranslation(place, { retry: deps.retry === true })) return { outcome: "not_needed" };
    // Kill switch: sem escrita nenhuma; o app cai no fallback (original).
    if (!enabled) return { outcome: "disabled" };
    const text = place.description;
    const count = Array.from(text).length;
    const sourceHash = c.hash(text);
    const base = { version: VERSION, sourceHash, characters: count };
    const writeResult = async (fields) => {
      // Só grava se o texto ainda for o mesmo (late responses nunca sobrescrevem texto novo).
      return db.runTransaction(async (tx) => {
        const latest = await tx.get(placeRef);
        if (!latest.exists || latest.data().description !== text) return false;
        tx.update(placeRef, { [FIELD]: { ...base, ...fields, updatedAt: now } });
        return true;
      });
    };
    if (count > LIMITS.perCall) {
      await writeResult({ status: "too_long", sourceLanguage: "", texts: {} });
      return { outcome: "too_long" };
    }

    // 1) Reaproveita traduções e idioma já pagos (cache legado / resultado parcial).
    const reused = place[FIELD]?.sourceHash === sourceHash ? storedTexts(place[FIELD]) : {};
    let sourceLanguage = place[FIELD]?.sourceHash === sourceHash ? String(place[FIELD].sourceLanguage || "") : "";
    const cache = db.collection(c.CACHE);
    if (!sourceLanguage) {
      const known = await cache.doc(c.sourceId(placeId, sourceHash)).get();
      sourceLanguage = String(known.data()?.language || "");
    }
    for (const [target, key] of Object.entries(LEGACY_KEY)) {
      if (reused[target]) continue;
      const row = await cache.doc(c.cacheId(placeId, key, sourceHash)).get();
      const hit = c.cachedText(row.data(), text, key);
      if (hit !== null) {
        reused[target] = hit;
        if (!sourceLanguage && typeof row.data()?.sourceLanguage === "string") sourceLanguage = row.data().sourceLanguage;
      }
    }

    // 2) Detecta a origem só se ainda não souber (amostra de até 300 caracteres).
    if (!sourceLanguage) {
      const sample = sampleOf(text);
      const r = await reserve(db, Array.from(sample).length, now, placeRef, text);
      if (r !== "ok") {
        if (r === "quota") await writeResult({ status: "quota", sourceLanguage: "", texts: reused });
        return { outcome: r };
      }
      try {
        sourceLanguage = await detect(sample);
      } catch (_) {
        await writeResult({ status: "failed", sourceLanguage: "", texts: reused });
        return { outcome: "failed" };
      }
    }
    sourceLanguage = sourceLanguage.toLowerCase();

    // 3) Traduz só o que falta, depois de reservar no limite diário/mensal.
    const targets = targetsFor(sourceLanguage);
    const texts = {};
    for (const t of targets) if (reused[t]) texts[t] = reused[t];
    const missing = targets.filter((t) => !texts[t]);
    if (!targets.length) {
      await writeResult({ status: "source_only", sourceLanguage, texts: {} });
      return { outcome: "source_only" };
    }
    let billed = 0;
    if (missing.length) {
      const r = await reserve(db, count * missing.length, now, placeRef, text);
      if (r !== "ok") {
        if (r === "quota") await writeResult({ status: "quota", sourceLanguage, texts });
        return { outcome: r };
      }
      billed = count * missing.length;
      for (const t of missing) {
        try {
          const out = await translate(text, GOOGLE_TARGET[t]);
          if (typeof out?.text === "string" && out.text && out.text.length <= MAX_TEXT) texts[t] = out.text;
        } catch (_) { /* Falha por idioma: segue com os outros. Sem texto/UID em log. */ }
      }
    }
    const done = targets.filter((t) => texts[t]).length;
    const status = done === targets.length ? "ready" : done ? "partial" : "failed";
    const stored = await writeResult({ status, sourceLanguage, texts });

    // 4) Espelho no cache legado (lido pela /l/ e pelo callable antigo).
    const batch = db.batch();
    let mirrored = 0;
    for (const [target, key] of Object.entries(LEGACY_KEY)) {
      if (!texts[target]) continue;
      batch.set(cache.doc(c.cacheId(placeId, key, sourceHash)), {
        status: "ready", placeId, sourceHash, targetLanguage: key, sourceLanguage,
        text: texts[target], characters: count, createdAt: now, origin: "approval",
      });
      mirrored++;
    }
    batch.set(cache.doc(c.sourceId(placeId, sourceHash)), { language: sourceLanguage, sourceHash });
    await batch.commit();
    return { outcome: stored ? status : "source_changed", billed, mirrored };
  } catch (error) {
    console.error("translatePlaceOnApproval", error && error.code ? error.code : "error");
    return { outcome: "error" };
  }
}

module.exports = {
  FIELD, VERSION, TARGETS, GOOGLE_TARGET, LEGACY_KEY, DETECT_SAMPLE,
  detectBasic, targetsFor, storedTexts, needsTranslation, shouldHandleWrite,
  estimateCharacters, translatePlaceOnApproval,
};
