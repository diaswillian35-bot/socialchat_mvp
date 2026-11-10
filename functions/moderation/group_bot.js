/**
 * b44: bot moderador dos grupos (regras determinísticas, sem IA).
 * groups/{id}.modBot = { welcomeEnabled, rules, blockLinks, blockPhones, blockProfanity }.
 * Padrão recomendado (campo ausente): boas-vindas ligada, links e telefones
 * bloqueados, palavrão solto liberado (insulto é sempre bloqueado no app todo).
 */

const { evaluateProfanity, profanityOpts } = require("./profanity");

const BOT_SENDER_ID = "remdy_bot";
const RULES_MAX = 600;

const DEFAULT_BOT = Object.freeze({
  welcomeEnabled: true,
  rules: "",
  blockLinks: true,
  blockPhones: true,
  blockProfanity: false,
});

function botConfig(groupData) {
  const raw = (groupData && groupData.modBot) || {};
  const pick = (k) => (typeof raw[k] === "boolean" ? raw[k] : DEFAULT_BOT[k]);
  return {
    welcomeEnabled: pick("welcomeEnabled"),
    rules: typeof raw.rules === "string" ? raw.rules.slice(0, RULES_MAX) : "",
    blockLinks: pick("blockLinks"),
    blockPhones: pick("blockPhones"),
    blockProfanity: pick("blockProfanity"),
  };
}

/** Valida o que dono/admin manda. Lança Error("invalid:<campo>"). */
function sanitizeBotChanges(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("invalid:modBot");
  const out = {};
  for (const k of Object.keys(input)) {
    if (["welcomeEnabled", "blockLinks", "blockPhones", "blockProfanity"].includes(k)) {
      if (typeof input[k] !== "boolean") throw new Error(`invalid:${k}`);
      out[k] = input[k];
    } else if (k === "rules") {
      if (typeof input.rules !== "string") throw new Error("invalid:rules");
      const r = input.rules.replace(/\r\n/g, "\n").trim();
      if (r.length > RULES_MAX) throw new Error("invalid:rules");
      out.rules = r;
    } else {
      throw new Error(`invalid:${k}`);
    }
  }
  if (!Object.keys(out).length) throw new Error("invalid:modBot");
  return out;
}

// ---------- links ----------
const ALLOWED_HOSTS = ["remdy.app"];
const TLDS = [
  "com", "net", "org", "info", "biz", "io", "app", "dev", "me", "ly", "gg", "co", "tv",
  "xyz", "link", "site", "online", "store", "shop", "club", "live", "top", "vip", "fun",
  "br", "pt", "ca", "us", "uk", "fr", "es", "de", "it", "mx", "ar", "cl", "eu", "be", "ch",
  "to", "cc", "ws", "click", "page", "xxx", "porn", "sex", "cam",
];
// TLDs que também são palavras comuns ("vou.de", "ok.me"): só contam com http/www, caminho "/" ou outro ponto antes.
const AMBIGUOUS_TLDS = ["de", "es", "it", "me", "to", "co", "us", "ca", "pt", "be", "ch", "cc", "ws", "ar", "fr", "eu", "mx", "cl", "uk", "tv"];
const SHORT_HOSTS = ["wa.me", "t.me", "bit.ly", "tinyurl.com", "chat.whatsapp.com", "discord.gg", "linktr.ee"];

function hostAllowed(host) {
  const h = String(host || "").toLowerCase().replace(/^www\./, "").replace(/\.+$/, "");
  return ALLOWED_HOSTS.some((d) => h === d || h.endsWith(`.${d}`));
}

function prepLink(raw) {
  return String(raw || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[\u200B-\u200D\uFEFF]/g, "")
    .replace(/\s*\[\s*(?:\.|dot|ponto)\s*\]\s*/g, ".")
    .replace(/\s+(?:ponto|dot|punto|point)\s+(com|net|org|br|me|ly|app|io)\b/g, ".$1");
}

/** Hosts com cara de link (URL, www., e-mail, domínio.tld conhecido). */
function findLinkHosts(raw) {
  const s = prepLink(raw);
  const hosts = [];
  const re = /(?:https?:\/\/|www\.)?((?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+([a-z]{2,24}))(?::\d+)?(?:\/[^\s]*)?/g;
  let m;
  while ((m = re.exec(s))) {
    const full = m[0];
    const host = m[1].replace(/\.+$/, "");
    const tld = m[2];
    const explicit = /^(?:https?:\/\/|www\.)/.test(full);
    const before = m.index > 0 ? s[m.index - 1] : "";
    if (before === "@") { hosts.push(host); continue; } // e-mail conta como contato/link
    const hasPath = /\/[^\s]/.test(full);
    const multiDot = host.split(".").length > 2;
    const tldOk = TLDS.includes(tld) && (!AMBIGUOUS_TLDS.includes(tld) || hasPath || multiDot);
    if (explicit || SHORT_HOSTS.includes(host) || tldOk) {
      // evita "1.5" sem esquema. URL explícita (http/www) e host com letra (192.168.0.1x.io) entram.
      if (!explicit && !/[a-z]/.test(host)) continue;
      hosts.push(host);
    }
  }
  // IP com http(s):// (o regex de domínio exige TLD com letra e não pega 192.168.1.1).
  const ipRe = /https?:\/\/((?:\d{1,3}\.){3}\d{1,3})(?::\d+)?(?:\/[^\s]*)?/g;
  while ((m = ipRe.exec(s))) hosts.push(m[1]);
  return hosts;
}

function hasBlockedLink(raw) {
  return findLinkHosts(raw).some((h) => !hostAllowed(h));
}

// ---------- telefones ----------
const PHONE_WORDS = /\b(?:whats(?:app)?|wpp|zap|zapzap|tel|telefone|telemovel|fone|celular|cel|liga|ligue|chama|call|text me|phone|llamame|llama|movil|appelle|portable)\b/;

/**
 * Detecta número de telefone (BR, PT, CA/EUA e internacional com +).
 * Não pega: datas (10/11/2026, 2026-11-10), horas (19:30, 19h30), preços
 * (R$ 1.500,00, $1,299.99, 12,50 €), CEP (01310-100), CPF fica como telefone (11 dígitos).
 */
function findPhones(raw) {
  const s = basicLower(raw);
  const found = [];
  const re = /(\+\s?)?(?:\(?\d[\d\s.\-()]{6,22}\d)/g;
  let m;
  while ((m = re.exec(s))) {
    const chunk = m[0];
    const start = m.index;
    const end = start + chunk.length;
    const before = s.slice(Math.max(0, start - 4), start);
    const after = s.slice(end, end + 6);
    const digits = chunk.replace(/\D/g, "");
    const plus = Boolean(m[1]);
    if (/[/:]/.test(s.slice(Math.max(0, start - 1), start)) || /^[/:h]\d/.test(after)) continue; // data/hora
    if (/(?:r\$|us\$|\$|€|£|eur|usd|brl|cad)\s*$/.test(before)) continue; // preço
    if (/^\s*(?:€|eur|reais|real|usd|dolares|dollars|cad|\$|%|km|kg|m2|mil)\b/.test(after) || /^\s*[€$%]/.test(after)) continue;
    if (/[.,]\d{2}$/.test(chunk) && !plus) continue; // 1.234,56 / 1,299.99
    if (/^\d{4}[-.]\d{1,2}[-.]\d{1,2}$/.test(chunk.trim())) continue; // ISO date
    const groups = chunk.trim().split(/[\s.\-()]+/).filter(Boolean);
    if (groups.length > 1 && groups.every((g) => /^(?:19|20)\d{2}$/.test(g))) continue; // anos
    const n = digits.length;
    let phone = false;
    if (plus && n >= 8 && n <= 15) phone = true;
    else if (n >= 10 && n <= 13) phone = true; // BR com DDD (10/11), +55 (12/13), CA/EUA (10/11), PT +351 (12)
    else if (n === 9 && /^[29]/.test(digits) && groups.length >= 2) phone = true; // PT 912 345 678 / BR 98765-4321
    else if (n >= 8 && n <= 9 && PHONE_WORDS.test(s)) phone = true; // "zap 98765-4321"
    if (phone) found.push(digits);
  }
  return found;
}

function basicLower(raw) {
  return String(raw || "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}

function hasPhone(raw) {
  return findPhones(raw).length > 0;
}

/**
 * Decisão do bot para uma mensagem de grupo.
 * @returns {{reason:'bot_link'|'bot_phone'|'insult'|'profanity'}|null}
 */
function evaluateGroupMessage(text, groupData, modCfg) {
  const raw = String(text || "");
  if (!raw.trim()) return null;
  const bot = botConfig(groupData);
  const opts = profanityOpts(modCfg, bot.blockProfanity);
  if (opts) {
    const p = evaluateProfanity(raw, opts);
    if (p) return p;
  }
  if (bot.blockLinks && hasBlockedLink(raw)) return { reason: "bot_link" };
  if (bot.blockPhones && hasPhone(raw)) return { reason: "bot_phone" };
  return null;
}

module.exports = {
  BOT_SENDER_ID,
  DEFAULT_BOT,
  RULES_MAX,
  botConfig,
  sanitizeBotChanges,
  findLinkHosts,
  hasBlockedLink,
  hostAllowed,
  findPhones,
  hasPhone,
  evaluateGroupMessage,
};
