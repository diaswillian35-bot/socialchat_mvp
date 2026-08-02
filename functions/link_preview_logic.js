/**
 * Link Preview — pure/testable logic (SSRF checks, sanitization, HTML
 * metadata parsing, cache/rate-limit policy). NO firebase-admin imports
 * here on purpose: this module must be safe to unit test in plain Node,
 * and keeping it framework-free makes the SSRF-critical checks easy to
 * audit and reuse.
 *
 * CACHE POLICY
 * ------------
 * Collection: `linkPreviewCache/{hash}` where `{hash}` = cacheKeyForUrl(url)
 * (stable sha256 hex of the normalized https URL).
 *   - Doc shape: { preview: {title, description, domain, url, imageUrl},
 *                  fetchedAtMs, status: 'ready' | 'failed' }
 *   - TTL: CACHE_TTL_MS (7 days). Entries are NOT deleted on expiry; the
 *     next request for that URL simply treats the doc as a miss
 *     (shouldUseCache() returns false) and overwrites it with a fresh
 *     fetch result. There are no permanent listeners on this collection.
 *   - Cleanup: no cleanup Cloud Function ships in this change. A future
 *     scheduled function MAY sweep `linkPreviewCache` for docs older than
 *     CACHE_TTL_MS to reclaim storage; not required for correctness since
 *     stale docs are simply ignored by shouldUseCache().
 *   - Reads/writes: server-only (Admin SDK). Firestore rules deny all
 *     client access (`allow read, write: if false;`).
 *
 * RATE LIMITS (server-only, `_rateLimits` collection, Admin SDK only)
 *   - `_rateLimits/linkPreview_{uid}` — 20 requests / 60_000ms per caller
 *     (covers cache hits + misses; stops one user flooding).
 *   - `_rateLimits/linkPreviewFetch_{uid}_{hash}` — 10 network fetches /
 *     60_000ms per caller per URL. Applied ONLY on cache miss.
 *   - There is NO global-per-URL limit: popular links (Amazon, etc.) must
 *     stay available to many users; the shared `linkPreviewCache` absorbs
 *     fan-out after the first successful fetch.
 *   Both use the fixed-window policy implemented by evaluateRateLimit().
 */

const crypto = require("crypto");

const MAX_BYTES = 512_000;
/** Amazon short links (a.co / amzn.to) often need 2–4 hops. */
const MAX_REDIRECTS = 5;
const FETCH_TIMEOUT_MS = 5000;
const CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000; // 7 days
const RATE_LIMIT_UID_MAX = 20;
const RATE_LIMIT_UID_WINDOW_MS = 60_000;
const RATE_LIMIT_FETCH_MAX = 10;
const RATE_LIMIT_FETCH_WINDOW_MS = 60_000;

const FIELD_LIMITS = Object.freeze({
  title: 120,
  description: 240,
  domain: 120,
  url: 2048,
  imageUrl: 2048,
});

// ---------------------------------------------------------------------------
// URL normalization
// ---------------------------------------------------------------------------

/**
 * Only https is allowed. Any other scheme (http, javascript, data, file,
 * ftp, etc.) is rejected. Embedded credentials (user:pass@host) are
 * stripped rather than rejected. Fragment is dropped (never sent to the
 * server, irrelevant for a preview / cache key).
 */
function normalizeHttpsUrl(raw) {
  if (typeof raw !== "string") {
    throw new Error("url_required");
  }
  const trimmed = raw.trim();
  if (!trimmed) {
    throw new Error("url_required");
  }
  if (trimmed.length > FIELD_LIMITS.url) {
    throw new Error("url_too_long");
  }

  let parsed;
  try {
    parsed = new URL(trimmed);
  } catch (_) {
    throw new Error("url_invalid");
  }

  if (parsed.protocol !== "https:") {
    throw new Error("url_scheme_not_https");
  }
  if (!parsed.hostname) {
    throw new Error("url_missing_host");
  }

  parsed.username = "";
  parsed.password = "";
  parsed.hash = "";

  return parsed.toString();
}

// ---------------------------------------------------------------------------
// SSRF guards — hostnames + IPv4/IPv6 literals
// ---------------------------------------------------------------------------

const BLOCKED_HOSTNAME_EXACT = new Set([
  "localhost",
  "metadata",
  "metadata.internal",
  "metadata.google.internal",
]);

const BLOCKED_HOSTNAME_SUFFIXES = [".localhost"];

function stripBrackets(host) {
  const h = String(host || "").trim();
  if (h.startsWith("[") && h.endsWith("]")) return h.slice(1, -1);
  return h;
}

function looksLikeIpLiteral(host) {
  return /^[0-9.]+$/.test(host) || host.includes(":");
}

/**
 * Rejects localhost, *.localhost, known metadata hostnames, and any
 * hostname that is itself a blocked IPv4/IPv6 literal (private, loopback,
 * link-local, multicast, metadata, CGNAT).
 */
function isBlockedHostname(host) {
  const raw = stripBrackets(host).toLowerCase();
  if (!raw) return true;
  if (BLOCKED_HOSTNAME_EXACT.has(raw)) return true;
  for (const suffix of BLOCKED_HOSTNAME_SUFFIXES) {
    if (raw.endsWith(suffix)) return true;
  }
  if (looksLikeIpLiteral(raw)) {
    return isPrivateOrBlockedIp(raw);
  }
  return false;
}

function parseIpv4(ip) {
  const parts = String(ip || "").split(".");
  if (parts.length !== 4) return null;
  const nums = [];
  for (const part of parts) {
    if (!/^\d{1,3}$/.test(part)) return null;
    const n = Number(part);
    if (n < 0 || n > 255) return null;
    nums.push(n);
  }
  return nums;
}

/**
 * Blocks: 0.0.0.0/8, 10/8, 127/8, 169.254/16 (incl. cloud metadata
 * 169.254.169.254), 172.16/12, 192.168/16, 100.64/10 (CGNAT),
 * 192.0.0.0/24, 192.0.2.0/24, 198.18.0.0/15, 198.51.100.0/24,
 * 203.0.113.0/24, 224/4 (multicast), 240/4 + 255.255.255.255 (reserved).
 */
function isPrivateOrBlockedIpv4(ip) {
  const o = parseIpv4(ip);
  if (!o) return true; // malformed -> fail closed
  const [a, b, c] = o;

  if (a === 0) return true;
  if (a === 10) return true;
  if (a === 127) return true;
  if (a === 169 && b === 254) return true;
  if (a === 172 && b >= 16 && b <= 31) return true;
  if (a === 192 && b === 168) return true;
  if (a === 100 && b >= 64 && b <= 127) return true;
  if (a === 192 && b === 0 && c === 0) return true;
  if (a === 192 && b === 0 && c === 2) return true;
  if (a === 198 && (b === 18 || b === 19)) return true;
  if (a === 198 && b === 51 && c === 100) return true;
  if (a === 203 && b === 0 && c === 113) return true;
  if (a >= 224 && a <= 239) return true; // multicast
  if (a >= 240) return true; // reserved + broadcast

  return false;
}

/** Expands a possibly-compressed IPv6 literal into 8 16-bit groups. */
function expandIpv6(rawInput) {
  let ip = String(rawInput || "").toLowerCase().split("%")[0];

  if (ip.includes(".")) {
    const lastColon = ip.lastIndexOf(":");
    const v4 = ip.slice(lastColon + 1);
    const parts = parseIpv4(v4);
    if (parts) {
      const hex1 = ((parts[0] << 8) | parts[1]).toString(16);
      const hex2 = ((parts[2] << 8) | parts[3]).toString(16);
      ip = `${ip.slice(0, lastColon + 1)}${hex1}:${hex2}`;
    }
  }

  let head = [];
  let tail = [];
  if (ip.includes("::")) {
    const [h, t] = ip.split("::");
    head = h ? h.split(":") : [];
    tail = t ? t.split(":") : [];
  } else {
    head = ip.split(":");
  }

  const missing = 8 - (head.length + tail.length);
  const groups = [...head, ...Array(Math.max(missing, 0)).fill("0"), ...tail];
  while (groups.length < 8) groups.push("0");
  return groups.slice(0, 8).map((g) => parseInt(g === "" ? "0" : g, 16));
}

/**
 * Blocks: :: (unspecified), ::1 (loopback), fe80::/10 (link-local),
 * fc00::/7 (unique local), ff00::/8 (multicast), IPv4-mapped
 * (::ffff:0:0/96) and NAT64 (64:ff9b::/96) addresses whose embedded IPv4
 * is itself blocked.
 */
function isPrivateOrBlockedIpv6(ip) {
  const groups = expandIpv6(ip);
  if (groups.some((g) => !Number.isFinite(g))) return true; // malformed

  if (groups.every((g) => g === 0)) return true; // ::
  if (groups.slice(0, 7).every((g) => g === 0) && groups[7] === 1) return true; // ::1

  const g0 = groups[0];
  if ((g0 & 0xffc0) === 0xfe80) return true; // fe80::/10
  if ((g0 & 0xfe00) === 0xfc00) return true; // fc00::/7
  if ((g0 & 0xff00) === 0xff00) return true; // ff00::/8

  const isV4MappedPrefix =
    groups[0] === 0 &&
    groups[1] === 0 &&
    groups[2] === 0 &&
    groups[3] === 0 &&
    groups[4] === 0 &&
    groups[5] === 0xffff;
  const isNat64Prefix =
    groups[0] === 0x64 &&
    groups[1] === 0xff9b &&
    groups[2] === 0 &&
    groups[3] === 0 &&
    groups[4] === 0 &&
    groups[5] === 0;

  if (isV4MappedPrefix || isNat64Prefix) {
    const embeddedIpv4 = [
      (groups[6] >> 8) & 0xff,
      groups[6] & 0xff,
      (groups[7] >> 8) & 0xff,
      groups[7] & 0xff,
    ].join(".");
    return isPrivateOrBlockedIpv4(embeddedIpv4);
  }

  return false;
}

function isPrivateOrBlockedIp(ip) {
  const v = String(ip || "").trim();
  if (!v) return true;
  if (v.includes(":")) return isPrivateOrBlockedIpv6(v);
  return isPrivateOrBlockedIpv4(v);
}

/**
 * Throws if any resolved address is blocked. Accepts either an array of
 * IP strings or the `{address, family}` shape returned by
 * `dns.promises.lookup(host, {all: true})`. Called BEFORE the initial
 * connect and again before following each redirect (DNS rebinding guard).
 */
function assertSafeResolvedAddresses(addresses) {
  const list = Array.isArray(addresses) ? addresses : [];
  if (list.length === 0) {
    throw new Error("dns_no_addresses");
  }
  for (const entry of list) {
    const ip = typeof entry === "string" ? entry : entry && entry.address;
    if (!ip || isPrivateOrBlockedIp(ip)) {
      throw new Error(`blocked_ip:${ip || "unknown"}`);
    }
  }
}

// ---------------------------------------------------------------------------
// Sanitization
// ---------------------------------------------------------------------------

function stripControlChars(value) {
  return String(value == null ? "" : value)
    .replace(/[\x00-\x1F\x7F]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function clamp(value, maxLen) {
  const v = stripControlChars(value);
  return v.length > maxLen ? v.slice(0, maxLen) : v;
}

/**
 * Length-limits + control-char-strips every field. `imageUrl` must be a
 * valid https URL (reused normalizeHttpsUrl); anything else becomes "".
 */
function sanitizePreviewFields({ title, description, domain, url, imageUrl } = {}) {
  const out = {
    title: clamp(title, FIELD_LIMITS.title),
    description: clamp(description, FIELD_LIMITS.description),
    domain: clamp(domain, FIELD_LIMITS.domain),
    url: clamp(url, FIELD_LIMITS.url),
    imageUrl: "",
  };

  const rawImage = stripControlChars(imageUrl).slice(0, FIELD_LIMITS.imageUrl);
  if (rawImage) {
    try {
      out.imageUrl = normalizeHttpsUrl(rawImage).slice(0, FIELD_LIMITS.imageUrl);
    } catch (_) {
      out.imageUrl = "";
    }
  }

  return out;
}

// ---------------------------------------------------------------------------
// HTML metadata extraction — regex based, no JS execution / no DOM
// ---------------------------------------------------------------------------

function decodeEntities(str) {
  if (!str) return "";
  return str
    .replace(/&#x([0-9a-fA-F]+);/g, (_, hex) => {
      try {
        return String.fromCodePoint(parseInt(hex, 16));
      } catch (_) {
        return "";
      }
    })
    .replace(/&#(\d+);/g, (_, dec) => {
      try {
        return String.fromCodePoint(parseInt(dec, 10));
      } catch (_) {
        return "";
      }
    })
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;|&#39;/g, "'")
    .replace(/&nbsp;/g, " ");
}

const MAX_META_TAGS_SCANNED = 5000;

function extractMetaTags(html) {
  const tags = [];
  const re = /<meta\b[^>]*>/gi;
  let match;
  let iterations = 0;
  while (iterations < MAX_META_TAGS_SCANNED && (match = re.exec(html))) {
    tags.push(match[0]);
    iterations += 1;
  }
  return tags;
}

function readAttr(tag, attrName) {
  const re = new RegExp(`${attrName}\\s*=\\s*("([^"]*)"|'([^']*)'|([^\\s"'>]+))`, "i");
  const m = re.exec(tag);
  if (!m) return null;
  const value = m[2] !== undefined ? m[2] : m[3] !== undefined ? m[3] : m[4];
  return decodeEntities(value || "");
}

function metaByAttr(tags, attrKey, attrValues) {
  const wanted = new Set(attrValues.map((v) => v.toLowerCase()));
  for (const tag of tags) {
    const keyVal = readAttr(tag, attrKey);
    if (keyVal && wanted.has(keyVal.toLowerCase())) {
      const content = readAttr(tag, "content");
      if (content) return content;
    }
  }
  return "";
}

function extractTitleTag(html) {
  const m = /<title[^>]*>([\s\S]*?)<\/title>/i.exec(html);
  if (!m) return "";
  return decodeEntities(m[1].replace(/\s+/g, " ").trim());
}

/**
 * Extracts og:*, twitter:*, <title> and meta description via regex only —
 * never parses/executes scripts, never builds a DOM.
 */
function parseHtmlMetadata(html) {
  const safeHtml = typeof html === "string" ? html : "";
  const tags = extractMetaTags(safeHtml);

  const ogTitle = metaByAttr(tags, "property", ["og:title"]);
  const twitterTitle = metaByAttr(tags, "name", ["twitter:title"]);
  const titleTag = extractTitleTag(safeHtml);

  const ogDescription = metaByAttr(tags, "property", ["og:description"]);
  const twitterDescription = metaByAttr(tags, "name", ["twitter:description"]);
  const metaDescription = metaByAttr(tags, "name", ["description"]);

  const ogImage = metaByAttr(tags, "property", [
    "og:image",
    "og:image:url",
    "og:image:secure_url",
  ]);
  const twitterImage = metaByAttr(tags, "name", ["twitter:image", "twitter:image:src"]);

  return {
    title: ogTitle || twitterTitle || titleTag || "",
    description: ogDescription || twitterDescription || metaDescription || "",
    imageUrl: ogImage || twitterImage || "",
  };
}

// ---------------------------------------------------------------------------
// Cache / rate limit policy (pure)
// ---------------------------------------------------------------------------

/** True when the cached doc is present, status ready, and within TTL. */
function shouldUseCache(cacheDoc, nowMs, ttlMs) {
  if (!cacheDoc || typeof cacheDoc !== "object") return false;
  if (cacheDoc.status !== "ready" || !cacheDoc.preview) return false;
  const fetchedAtMs = Number(cacheDoc.fetchedAtMs);
  if (!Number.isFinite(fetchedAtMs)) return false;
  const now = Number(nowMs);
  const ttl = Number(ttlMs);
  return now - fetchedAtMs < ttl;
}

/** Stable Firestore-doc-id-safe key for a normalized URL. */
function cacheKeyForUrl(normalizedUrl) {
  return crypto.createHash("sha256").update(String(normalizedUrl || ""), "utf8").digest("hex");
}

/**
 * Fixed-window rate limit decision. Pure — caller persists `next` inside a
 * transaction. Window resets once `nowMs - windowStartMs >= windowMs`.
 */
function evaluateRateLimit({ windowStartMs, count, nowMs, max, windowMs }) {
  let ws = Number(windowStartMs);
  let c = Number(count) || 0;
  const now = Number(nowMs);

  if (!Number.isFinite(ws) || now - ws >= windowMs) {
    ws = now;
    c = 0;
  }

  const allowed = c < max;
  return {
    allowed,
    next: {
      windowStartMs: ws,
      count: allowed ? c + 1 : c,
    },
  };
}

function isHtmlContentType(ct) {
  if (!ct || typeof ct !== "string") return false;
  const base = ct.split(";")[0].trim().toLowerCase();
  return base === "text/html" || base === "application/xhtml+xml";
}

/**
 * True when `normalizedUrl` appears in the message text (exact candidate
 * after https normalization). Prevents attaching a preview for a URL the
 * user did not send.
 */
function urlAppearsInMessageText(text, normalizedUrl) {
  if (typeof text !== "string" || !text.trim()) return false;
  let target;
  try {
    target = normalizeHttpsUrl(normalizedUrl);
  } catch (_) {
    return false;
  }

  const candidates = extractUrlCandidatesFromText(text);
  for (const raw of candidates) {
    try {
      let candidate = raw;
      if (/^http:\/\//i.test(candidate)) {
        candidate = `https://${candidate.slice(7)}`;
      } else if (!/^https:\/\//i.test(candidate)) {
        candidate = `https://${candidate}`;
      }
      if (normalizeHttpsUrl(candidate) === target) return true;
    } catch (_) {
      // ignore invalid candidate
    }
  }
  return false;
}

function trimTrailingPunctuation(raw) {
  let s = String(raw || "").trim();
  while (s && ".,);]!?:'\"".includes(s[s.length - 1])) {
    s = s.slice(0, -1);
  }
  return s.trim();
}

function extractUrlCandidatesFromText(text) {
  const found = [];
  const re =
    /(?:https?:\/\/|www\.)[^\s<>"]+|(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+(?:com|net|org|edu|gov|io|co|app|dev|info|biz|br|ca|uk|us|pt|es|fr|de|it|jp|au|shop|store)(?::\d{2,5})?(?:\/[^\s]*)?/gi;
  let m;
  while ((m = re.exec(text)) !== null) {
    const raw = trimTrailingPunctuation(m[0]);
    if (!raw) continue;
    // Skip emails: char before match is @
    if (m.index > 0 && text[m.index - 1] === "@") continue;
    found.push(raw);
  }
  return found;
}

/** Soft-deleted or hidden-for-caller messages must not receive a preview. */
function isMessageEligibleForPreview(messageData, uid) {
  if (!messageData || typeof messageData !== "object") return false;
  if (messageData.deleted === true) return false;
  const hiddenFor = Array.isArray(messageData.hiddenFor) ? messageData.hiddenFor : [];
  const deletedFor = Array.isArray(messageData.deletedFor) ? messageData.deletedFor : [];
  if (hiddenFor.includes(uid) || deletedFor.includes(uid)) return false;
  return true;
}

/** Message author must be the caller (senderId or fromUid). */
function isMessageAuthoredBy(messageData, uid) {
  if (!messageData || !uid) return false;
  const sender = (messageData.senderId || messageData.fromUid || "").toString();
  return sender === uid;
}

module.exports = {
  MAX_BYTES,
  MAX_REDIRECTS,
  FETCH_TIMEOUT_MS,
  CACHE_TTL_MS,
  FIELD_LIMITS,
  RATE_LIMIT_UID_MAX,
  RATE_LIMIT_UID_WINDOW_MS,
  RATE_LIMIT_FETCH_MAX,
  RATE_LIMIT_FETCH_WINDOW_MS,
  normalizeHttpsUrl,
  isBlockedHostname,
  isPrivateOrBlockedIp,
  isPrivateOrBlockedIpv4,
  isPrivateOrBlockedIpv6,
  assertSafeResolvedAddresses,
  sanitizePreviewFields,
  parseHtmlMetadata,
  shouldUseCache,
  cacheKeyForUrl,
  evaluateRateLimit,
  isHtmlContentType,
  urlAppearsInMessageText,
  extractUrlCandidatesFromText,
  isMessageEligibleForPreview,
  isMessageAuthoredBy,
};
