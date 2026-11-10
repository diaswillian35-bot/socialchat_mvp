/**
 * b44: insultos (sempre bloqueados, contam ponto) e palavrões soltos
 * (bloqueados só onde o filtro do grupo estiver ligado, ou com
 * appConfig/moderation.profanityLevel = "strict").
 * Lista em word_lists.json (RASCUNHO até a revisão do Willian).
 * Espelho no app: lib/services/chat_rules_filter.dart (teste de paridade).
 * Só palavra/frase inteira depois da normalização, nunca substring.
 */

const LISTS = require("./word_lists.json");

const LEET = { "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s" };

function basic(raw) {
  return String(raw || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[\u200B-\u200D\uFEFF]/g, "");
}

/** Normaliza para casar palavras: leet, letras repetidas (3+), f.d.p / v-s-f, espaçadas. */
function prepare(raw) {
  let s = basic(raw);
  // leet só dentro de palavras (não mexe em números soltos como "2024" ou "10")
  s = s.replace(/[a-z0-9@$]+/g, (w) => (/[a-z]/.test(w) ? w.replace(/[013457@$]/g, (c) => LEET[c] || c) : w));
  // letras isoladas separadas por . - _ * (f.d.p, v-s-f)
  s = s.replace(/\b(?:[a-z][.\-_*]){2,}[a-z]\b/g, (m) => m.replace(/[.\-_*]/g, ""));
  s = s.replace(/[^a-z0-9\s]/g, " ");
  // letras soltas com espaço (p o r r a, f d p)
  s = s.replace(/\b(?:[a-z]\s+){2,}[a-z]\b/g, (m) => m.replace(/\s+/g, ""));
  // 3+ letras iguais viram 1 (putaaaa -> puta); duplas normais ficam
  s = s.replace(/([a-z])\1{2,}/g, "$1");
  return s.replace(/\s+/g, " ").trim();
}

function normTerm(term) {
  return basic(term).replace(/[^a-z0-9\s]/g, " ").replace(/\s+/g, " ").trim();
}

function compile(map) {
  const out = new Set();
  for (const lang of Object.keys(map || {})) {
    for (const t of map[lang] || []) {
      const n = normTerm(t);
      if (n) out.add(n);
    }
  }
  return Array.from(out);
}

const INSULTS = compile(LISTS.insults);
const LOOSE = compile(LISTS.loose);

function hasToken(text, token) {
  const escaped = token.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(?:^|[^a-z0-9])${escaped}(?:[^a-z0-9]|$)`).test(text);
}

function firstHit(text, list) {
  for (const t of list) if (hasToken(text, t)) return t;
  return null;
}

/**
 * @param {string} raw
 * @param {{loose?: boolean}} opts loose=true também bloqueia palavrão solto.
 * @returns {{reason:'insult'|'profanity'}|null}
 */
function evaluateProfanity(raw, opts = {}) {
  const text = prepare(raw);
  if (!text) return null;
  // também testa a versão "colada" sem espaços entre letras repetidas duplas
  if (firstHit(text, INSULTS)) return { reason: "insult" };
  if (opts.loose === true && firstHit(text, LOOSE)) return { reason: "profanity" };
  return null;
}

/** profanityLevel: off | insults (padrão) | strict (palavrão solto em todo lugar). */
function profanityOpts(cfg, groupLoose) {
  const level = String((cfg && cfg.profanityLevel) || "insults");
  if (level === "off") return null;
  return { loose: level === "strict" || groupLoose === true };
}

module.exports = { prepare, evaluateProfanity, profanityOpts, INSULTS, LOOSE, LISTS, normTerm };
