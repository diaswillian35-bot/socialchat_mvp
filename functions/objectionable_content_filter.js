/**
 * Server-side UGC filter (Apple Guideline 1.2).
 * Mirrors lib/services/objectionable_content_filter.dart — keep lists in sync.
 * Does not replace report/block or Firestore rules.
 */

const BLOCKED_PHRASES = [
  "child porn",
  "childporn",
  "cp for sale",
  "venda de cp",
  "onlyfans minors",
  "nudes de menor",
  "nude de menor",
  "sexo com menor",
  "pornografia infantil",
  "csam",
  "i will kill you",
  "vou te matar",
  "te mato",
  "kill yourself",
  "se mate",
  "kys ",
  "morte aos",
  "death to all",
];

const BLOCKED_REGEXES = [
  /\b(rape|estupr[ao]|estuprar)\b/i,
  /\b(nazi|hitler)\s+(rules|power|forever)\b/i,
  /\b(send|mande|envia)\b.{0,24}\b(nudes?|pack)\b.{0,24}\b(minor|menor|under\s*age|crianca|criança)\b/i,
  /\b(?:eu\s+)?vou(?:\s+(?:te|lhe|vos|voce|voces|ele|ela|eles|elas))?\s+matar\b(?!\s+(?:a\s+fome|saudades?|(?:o\s+)?tempo|(?:a\s+)?aula))/i,
  /\bvamos(?:\s+(?:te|vos|voce|voces))?\s+matar\b(?!\s+(?:a\s+fome|saudades?|(?:o\s+)?tempo))/i,
  /\b(?:te\s+)?voy\s+a\s+matar(?:te|lo|la|los|las)?\b(?!\s+(?:el\s+hambre|el\s+tiempo))/i,
  /\bje\s+vais(?:\s+(?:te|vous|le|la|les))?\s+tuer\b(?!\s+le\s+temps)/i,
  /(?:\bi(?:\s+am|\s+'?m)?\s+(?:going\s+to|gonna)|\bi(?:'?ll|\s+will)|\bgonna)\s+kill(?:\s+(?:you|u|him|her|them|ya))?\b(?!\s+(?:time|it)\b)/i,
];

function normalize(input) {
  return String(input || "")
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function isObjectionableText(raw) {
  if (raw == null) return false;
  const trimmed = String(raw).trim();
  if (!trimmed) return false;

  const normalized = normalize(trimmed);
  if (!normalized) return false;

  for (const phrase of BLOCKED_PHRASES) {
    const p = normalize(phrase);
    if (!p) continue;
    if (normalized.includes(p)) return true;
  }

  for (const re of BLOCKED_REGEXES) {
    if (re.test(trimmed) || re.test(normalized)) return true;
  }
  return false;
}

module.exports = {
  isObjectionableText,
  BLOCKED_PHRASES,
};
