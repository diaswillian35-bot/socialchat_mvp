"use strict";
const admin = require("firebase-admin");
const { HttpsError } = require("firebase-functions/v2/https");
const { GoogleAuth } = require("google-auth-library");
const c = require("./place_description_cache");
// Fixed ceilings: no remote config can raise these accidentally.
const LIMITS = Object.freeze({ perCall: 5000, daily: 12000, monthly: 300000, userDaily: 20 });
const auth = new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/cloud-translation"] });
async function translateBasic(text, target, { client: injectedClient } = {}) {
  const client = injectedClient || await auth.getClient();
  const result = await client.request({
    url: "https://translation.googleapis.com/language/translate/v2",
    method: "POST", timeout: 15000,
    // Never retry a billable request: ambiguous failures consume their reservation.
    retry: false, retryConfig: { retry: 0 },
    data: { q: text, target, format: "text", model: "nmt" },
  });
  const row = result.data?.data?.translations?.[0];
  if (typeof row?.translatedText !== "string" || !row.detectedSourceLanguage || row.translatedText.length > 20000)
    throw new Error("invalid_translation_response");
  return { text: row.translatedText, sourceLanguage: row.detectedSourceLanguage };
}
function periods(now) {
  // Billing/quotas use Pacific calendar boundaries, including DST.
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Los_Angeles", year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(now);
  const values = Object.fromEntries(parts.map(p => [p.type, p.value]));
  const day = `${values.year}-${values.month}-${values.day}`;
  return { day, month: day.slice(0, 7) };
}
function validate(request) {
  if (!request.auth?.uid) throw new HttpsError("unauthenticated", "authentication_required");
  const { placeId, language, sourceHash } = request.data || {};
  if (typeof placeId !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(placeId) ||
      !c.language(language) || typeof sourceHash !== "string" || !/^[a-f0-9]{64}$/.test(sourceHash))
    throw new HttpsError("invalid-argument", "invalid_translation_request");
  return { placeId, target: c.language(language), sourceHash };
}
function original(reason) { return { translated: false, reason }; }
async function translatePlaceDescriptionHandler(request, deps = {}) {
  const { placeId, target, sourceHash } = validate(request);
  const db = deps.db || admin.firestore();
  const placeRef = db.collection("places").doc(placeId);
  const snap = await placeRef.get();
  const place = snap.data();
  if (!c.isPublic(place)) return original("unavailable");
  const text = typeof place.description === "string" ? place.description : "";
  const count = Array.from(text).length;
  if (!count || count > LIMITS.perCall || c.hash(text) !== sourceHash) return original("source_changed_or_limit");
  const cacheRef = db.collection(c.CACHE).doc(c.cacheId(placeId, target, sourceHash));
  const sourceRef = db.collection(c.CACHE).doc(c.sourceId(placeId, sourceHash));
  const hit = await cacheRef.get();
  const cached = c.cachedText(hit.data(), text, target);
  if (cached !== null) return { translated: true, text: cached, sourceHash, targetLanguage: target };
  const source = await sourceRef.get();
  if (c.language(source.data()?.language) === target) return original("same_language");
  if (hit.exists) return original("already_attempted");
  // OFF by default. Enabling API or deploying alone is not permission to spend.
  if (!(deps.enabled ?? process.env.PLACE_DESCRIPTION_TRANSLATION_ENABLED === "true")) return original("disabled");
  const now = deps.now || new Date();
  const { day, month } = periods(now);
  const usage = db.collection("placeDescriptionTranslationUsage");
  const dayRef = usage.doc(`day_${day}`), monthRef = usage.doc(`month_${month}`);
  const userRef = usage.doc(`user_${c.hash(request.auth.uid)}_${day}`);
  // A persistent, non-expiring reservation ensures at-most-one API attempt per hash/target.
  // A crash never releases it automatically; an explicit admin repair is required.
  const reserved = await db.runTransaction(async tx => {
    const [latest, current, known, daily, monthly, user] = await Promise.all(
      [placeRef, cacheRef, sourceRef, dayRef, monthRef, userRef].map(ref => tx.get(ref)));
    if (!c.isPublic(latest.data()) || latest.data().description !== text) return false;
    if (current.exists || c.language(known.data()?.language) === target) return false;
    const dayCount = daily.data()?.characters || 0, monthCount = monthly.data()?.characters || 0;
    const calls = user.data()?.calls || 0;
    if (![dayCount, monthCount, calls].every(n => Number.isSafeInteger(n) && n >= 0)) return false;
    if (dayCount + count > LIMITS.daily || monthCount + count > LIMITS.monthly || calls >= LIMITS.userDaily) return false;
    tx.set(cacheRef, { status: "reserved", placeId, sourceHash, targetLanguage: target, characters: count, createdAt: now });
    tx.set(dayRef, { characters: dayCount + count });
    tx.set(monthRef, { characters: monthCount + count });
    tx.set(userRef, { calls: calls + 1 });
    return true;
  });
  if (!reserved) return original("reserved_or_quota");
  try {
    const translated = await (deps.translate || translateBasic)(text, target);
    if (typeof translated.text !== "string" || !translated.text || translated.text.length > 20000 ||
        typeof translated.sourceLanguage !== "string" || !/^[a-z]{2,3}(-[a-z0-9]+)*$/i.test(translated.sourceLanguage))
      throw new Error("invalid_translation_response");
    const sourceLanguage = translated.sourceLanguage.toLowerCase();
    const valid = await db.runTransaction(async tx => {
      const latest = await tx.get(placeRef);
      // Cache is keyed by the old hash, so even a late response cannot replace new text.
      const current = c.isPublic(latest.data()) && latest.data().description === text;
      tx.set(cacheRef, { status: "ready", placeId, sourceHash, targetLanguage: target,
        sourceLanguage, text: translated.text, characters: count, createdAt: now });
      tx.set(sourceRef, { language: sourceLanguage, sourceHash });
      return current;
    });
    if (!valid) return original("source_changed");
    if (c.language(sourceLanguage) === target) return original("same_language");
    return { translated: true, text: translated.text, sourceHash, targetLanguage: target };
  } catch (_) {
    // No original, translation, UID or provider response in logs/errors.
    await cacheRef.set({ status: "failed", sourceHash, targetLanguage: target, createdAt: now });
    return original("translation_failed");
  }
}
module.exports = { LIMITS, periods, translateBasic, translatePlaceDescriptionHandler };
