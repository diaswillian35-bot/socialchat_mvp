"use strict";
const { createHash } = require("node:crypto");
const CACHE = "placeDescriptionTranslations";
function language(raw) {
  const tag = String(raw || "").toLowerCase().replace(/_/g, "-");
  return /^(pt|en|es|fr)(-|$)/.exec(tag)?.[1] || null;
}
const hash = text => createHash("sha256").update(text, "utf8").digest("hex");
const cacheId = (id, lang, digest) => `${id}_${lang}_${digest}`;
const sourceId = (id, digest) => `${id}_source_${digest}`;
function isPublic(d) {
  return !!d && (d.schemaVersion === 1 || d.contractVersion === "remdy.places.v1") &&
    d.active === true && d.deleted !== true && d.moderationStatus === "published";
}
function cachedText(row, original, lang) {
  return row?.status === "ready" && row.sourceHash === hash(original) &&
    typeof row.sourceLanguage === "string" && !!row.sourceLanguage &&
    row.targetLanguage === language(lang) && language(row.sourceLanguage) !== language(lang) &&
    typeof row.text === "string" && row.text.length > 0 && row.text.length <= 20000 ? row.text : null;
}
// No API import or write: safe to use on public /l/ pages.
async function readCachedDescription(db, id, original, lang) {
  const target = language(lang);
  if (!target || !original) return null;
  const row = await db.collection(CACHE).doc(cacheId(id, target, hash(original))).get();
  return cachedText(row.data(), original, target);
}
module.exports = { CACHE, language, hash, cacheId, sourceId, isPublic, cachedText, readCachedDescription };
