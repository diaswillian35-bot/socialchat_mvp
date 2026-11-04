/**
 * Server-side UGC filter (Apple Guideline 1.2) plus adult/link extension.
 * The original phrase list and regexes stay; new checks only add coverage.
 * Mirrors lib/services/objectionable_content_filter.dart.
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

const CSAM_PHRASE_SET = new Set([
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
]);

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

const EXTRA_CSAM_PHRASES = [
  "porno infantil",
  "sexo com crianca",
  "sexo com criancas",
  "nudez infantil",
  "conteudo sexual infantil",
  "child pornography",
  "pornographie infantile",
];

const ADULT_PHRASES = [
  "sexo explicito",
  "conteudo adulto",
  "contenido adulto",
  "contenu adulte",
  "explicit sex",
  "pack de nudes",
  "vendo nudes",
  "venda de nudes",
  "manda nude",
  "mande nude",
  "send nude",
  "envia nude",
];

const ADULT_WORDS = [
  "porn",
  "porno",
  "pornografia",
  "pornography",
  "pornographie",
  "xvideos",
  "pornhub",
  "xhamster",
  "onlyfans",
  "fansly",
  "boquete",
  "punheta",
  "buceta",
  "piroca",
  "blowjob",
  "handjob",
  "camgirl",
  "nudes",
];

const DEFAULT_BLOCKED_DOMAINS = Object.freeze([
  "onlyfans.com",
  "pornhub.com",
  "xvideos.com",
  "xvideos2.com",
  "xnxx.com",
  "xhamster.com",
  "redtube.com",
  "youporn.com",
  "fansly.com",
  "fanvue.com",
  "privacy.com.br",
  "chaturbate.com",
  "stripchat.com",
  "bongacams.com",
  "livejasmin.com",
  "erome.com",
  "spankbang.com",
  "rule34.xxx",
  "sex.com",
  "justfor.fans",
  "manyvids.com",
]);

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

function applyLeet(value) {
  return String(value || "")
    .replace(/0/g, "o")
    .replace(/1/g, "i")
    .replace(/3/g, "e");
}

function collapseSpacedLetters(value) {
  return String(value || "").replace(
    /\b(?:[a-z]\s+){3,}[a-z]\b/g,
    (match) => match.replace(/\s+/g, ""),
  );
}

function evasionRaw(raw) {
  let s = String(raw || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
  s = s.replace(/[\u200B-\u200D\uFEFF]/g, "");
  s = applyLeet(s);
  s = s.replace(/\s*(?:ponto|dot|punto|point)\s+(com|net|org|xxx)\b/g, ".$1");
  s = s.replace(/\s*\.\s*/g, ".");
  s = collapseSpacedLetters(s);
  return s;
}

function domainsOf(config) {
  const list = config && config.blockedDomains;
  if (Array.isArray(list) && list.length > 0) {
    const out = [];
    for (const item of list) {
      const n = String(item || "")
        .trim()
        .toLowerCase()
        .replace(/^https?:\/\//, "")
        .replace(/^www\./, "")
        .split("/")[0];
      if (n && n.includes(".")) out.push(n);
    }
    if (out.length > 0) return out;
  }
  return DEFAULT_BLOCKED_DOMAINS.slice();
}

function hostBlocked(host, domains) {
  const h = String(host || "")
    .toLowerCase()
    .replace(/^www\./, "");
  if (!h) return false;
  if (h === "xxx" || h.endsWith(".xxx")) return true;
  return domains.some((d) => h === d || h.endsWith(`.${d}`));
}

function glueSpacedDomains(s, domains) {
  const list = domains || [];
  let cur = s;
  for (let i = 0; i < 4; i += 1) {
    const next = cur.replace(
      /\b([a-z0-9-]{2,})\s+((?:[a-z0-9-]+\.)+[a-z]{2,})\b/g,
      (full, left, host) => {
        const joined = `${left}${host}`;
        if (hostBlocked(host, list)) return full;
        if (hostBlocked(joined, list)) return joined;
        return full;
      },
    );
    if (next === cur) break;
    cur = next;
  }
  return cur;
}

function extractHosts(text) {
  const re = /(?:https?:\/\/)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/[^\s]*)?/gi;
  const hosts = [];
  let match;
  while ((match = re.exec(text))) {
    let token = match[0].replace(/^https?:\/\//, "");
    token = token.split("/")[0].split(":")[0];
    if (token) hosts.push(token);
  }
  return hosts;
}

function hasToken(text, token) {
  const escaped = token.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(?:^|[^a-z0-9])${escaped}(?:[^a-z0-9]|$)`).test(text);
}

function baseDecision(raw) {
  if (raw == null) return null;
  const trimmed = String(raw).trim();
  if (!trimmed) return null;
  const normalized = normalize(trimmed);
  if (!normalized) return null;

  for (const phrase of BLOCKED_PHRASES) {
    const p = normalize(phrase);
    if (!p) continue;
    if (normalized.includes(p)) {
      return { reason: CSAM_PHRASE_SET.has(p) ? "csam" : "text_adult" };
    }
  }

  if (BLOCKED_REGEXES[2].test(trimmed) || BLOCKED_REGEXES[2].test(normalized)) {
    return { reason: "csam" };
  }
  for (let i = 0; i < BLOCKED_REGEXES.length; i += 1) {
    if (i === 2) continue;
    const re = BLOCKED_REGEXES[i];
    if (re.test(trimmed) || re.test(normalized)) return { reason: "text_adult" };
  }
  return null;
}

function extensionDecision(raw, config) {
  const prepared = evasionRaw(raw);
  if (!prepared) return null;
  const words = normalize(prepared);
  const domains = domainsOf(config);
  const glued = glueSpacedDomains(prepared, domains);

  for (const phrase of EXTRA_CSAM_PHRASES) {
    if (hasToken(words, phrase)) return { reason: "csam" };
  }
  for (const host of extractHosts(glued)) {
    if (hostBlocked(host, domains)) return { reason: "link_adult" };
  }
  for (const phrase of ADULT_PHRASES) {
    if (hasToken(words, phrase)) return { reason: "text_adult" };
  }
  for (const word of ADULT_WORDS) {
    if (hasToken(words, word)) return { reason: "text_adult" };
  }
  return null;
}

function worse(a, b) {
  const rank = { csam: 3, link_adult: 2, text_adult: 1 };
  if (!a) return b || null;
  if (!b) return a;
  return (rank[a.reason] || 0) >= (rank[b.reason] || 0) ? a : b;
}

/**
 * @returns {{reason:'csam'|'link_adult'|'text_adult'}|null}
 */
function evaluateText(raw, config) {
  if (raw == null) return null;
  const trimmed = String(raw).trim();
  if (!trimmed) return null;
  const direct = baseDecision(trimmed);
  if (direct && direct.reason === "csam") return direct;
  const evaded = baseDecision(evasionRaw(trimmed));
  if (evaded && evaded.reason === "csam") return evaded;
  const extra = extensionDecision(trimmed, config);
  if (extra && extra.reason === "csam") return extra;
  return worse(worse(direct, evaded), extra);
}

function isObjectionableText(raw) {
  return evaluateText(raw, {}) != null;
}

function safeChatPreview(text, config) {
  if (config && config.enabled === false) return text == null ? "" : String(text);
  const raw = text == null ? "" : String(text);
  if (!raw.trim()) return raw;
  if (evaluateText(raw, config)) return "";
  return raw;
}

module.exports = {
  isObjectionableText,
  evaluateText,
  safeChatPreview,
  BLOCKED_PHRASES,
  DEFAULT_BLOCKED_DOMAINS,
  domainsOf,
  strikesWindowMs: 30 * 24 * 60 * 60 * 1000,
};
