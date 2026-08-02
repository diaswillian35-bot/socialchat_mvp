"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.SOCIAL_TRIGGER_FIELDS = exports.SOCIAL_FOOTER_HEIGHT = exports.SOCIAL_BRAND_MARGIN_BOTTOM = exports.SOCIAL_BRAND_MARGIN_RIGHT = exports.SOCIAL_BRAND_WIDTH = exports.SOCIAL_TEMPLATE_VERSION = exports.REMDY_NAVY_DARK = exports.REMDY_NAVY = exports.SOCIAL_FORMAT = exports.SOCIAL_MIME = exports.SOCIAL_TARGET_BYTES = exports.SOCIAL_MAX_BYTES = exports.SOCIAL_HEIGHT = exports.SOCIAL_WIDTH = void 0;
exports.loadRemdyLogoPng = loadRemdyLogoPng;
exports.loadRemdyIconPng = loadRemdyIconPng;
exports.computeSocialContentHash = computeSocialContentHash;
exports.normalizeMediaKey = normalizeMediaKey;
exports.pickCoverSource = pickCoverSource;
exports.wrapTitleLines = wrapTitleLines;
exports.renderSocialJpeg = renderSocialJpeg;
exports.ensureLocalSocialImage = ensureLocalSocialImage;
exports.resolveOgImageUrl = resolveOgImageUrl;
exports.socialInputsChanged = socialInputsChanged;
/**
 * Geração de imagem social OG 1200×630 (JPEG) com branding Remdy.
 * Puro quanto ao layout; I/O de capa/logo é injetável para testes.
 */
const crypto = __importStar(require("crypto"));
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
const sharp_1 = __importDefault(require("sharp"));
exports.SOCIAL_WIDTH = 1200;
exports.SOCIAL_HEIGHT = 630;
exports.SOCIAL_MAX_BYTES = 1024 * 1024;
exports.SOCIAL_TARGET_BYTES = 500 * 1024;
exports.SOCIAL_MIME = "image/jpeg";
exports.SOCIAL_FORMAT = "jpeg";
/** Navy Remdy (mockup / app). */
exports.REMDY_NAVY = { r: 49, g: 58, b: 95 };
exports.REMDY_NAVY_DARK = { r: 26, g: 32, b: 56 };
function assetPath(name) {
    const candidates = [
        path.join(__dirname, "assets", name),
        path.join(__dirname, "..", "assets", name),
    ];
    for (const candidate of candidates) {
        if (fs.existsSync(candidate))
            return candidate;
    }
    return candidates[0];
}
/** Marca horizontal oficial: [símbolo colorido] Remdy (wordmark navy, faixa clara). */
function loadRemdyLogoPng() {
    return fs.readFileSync(assetPath("remdy_logo_horizontal_navy.png"));
}
function loadRemdyIconPng() {
    return fs.readFileSync(assetPath("remdy_icon.png"));
}
/** Versão do template visual — incrementar quando a composição da arte muda. */
exports.SOCIAL_TEMPLATE_VERSION = "v4";
/** Largura alvo da marca no canto inferior direito (px). */
exports.SOCIAL_BRAND_WIDTH = 210;
/** Margens da marca na arte 1200×630. */
exports.SOCIAL_BRAND_MARGIN_RIGHT = 40;
exports.SOCIAL_BRAND_MARGIN_BOTTOM = 32;
/** Altura da faixa clara inferior. */
exports.SOCIAL_FOOTER_HEIGHT = 130;
/** Hash estável dos campos que afetam a arte (sem URL assinada volátil). */
function computeSocialContentHash(input) {
    const coverKey = normalizeMediaKey(input.coverUrl || "");
    const galleryKey = normalizeMediaKey(input.galleryFallbackUrl || "");
    const payload = [
        exports.SOCIAL_TEMPLATE_VERSION,
        input.eventId.trim(),
        input.title.trim(),
        input.dateLabel.trim(),
        input.locationLabel.trim(),
        (input.category || "").trim(),
        coverKey || galleryKey,
    ].join("|");
    return crypto.createHash("sha256").update(payload, "utf8").digest("hex").slice(0, 20);
}
function normalizeMediaKey(url) {
    const t = (url || "").trim();
    if (!t)
        return "";
    try {
        const u = new URL(t);
        return `https://${u.hostname.toLowerCase()}${u.pathname.replace(/\/+$/, "") || "/"}`;
    }
    catch {
        return t;
    }
}
function pickCoverSource(input) {
    const cover = (input.coverUrl || "").trim();
    if (/^https:\/\//i.test(cover))
        return { url: cover, source: "cover" };
    const gal = (input.galleryFallbackUrl || "").trim();
    if (/^https:\/\//i.test(gal))
        return { url: gal, source: "gallery" };
    return { url: "", source: "brand_fallback" };
}
function escapeForSvg(text) {
    return text
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&apos;");
}
/** Quebra título em até `maxLines` sem cortar no meio da palavra quando possível. */
function wrapTitleLines(title, maxCharsPerLine, maxLines) {
    const words = title.replace(/\s+/g, " ").trim().split(" ").filter(Boolean);
    if (!words.length)
        return [];
    const lines = [];
    let current = "";
    for (const word of words) {
        const next = current ? `${current} ${word}` : word;
        if (next.length <= maxCharsPerLine) {
            current = next;
            continue;
        }
        if (current)
            lines.push(current);
        if (lines.length >= maxLines - 1) {
            // última linha: encaixa o restante sem ellipsis forçado no meio da palavra
            const rest = [word, ...words.slice(words.indexOf(word) + 1)].join(" ");
            lines.push(rest.length > maxCharsPerLine + 8 ? rest.slice(0, maxCharsPerLine) : rest);
            return lines.slice(0, maxLines);
        }
        current = word.length > maxCharsPerLine ? word.slice(0, maxCharsPerLine) : word;
    }
    if (current)
        lines.push(current);
    return lines.slice(0, maxLines);
}
function buildOverlaySvg(input) {
    const footerY = exports.SOCIAL_HEIGHT - exports.SOCIAL_FOOTER_HEIGHT;
    const titleLines = wrapTitleLines(input.title || "Evento Remdy", 28, 3);
    const titleStartY = 360;
    const titleSpans = titleLines
        .map((line, i) => {
        const y = titleStartY + i * 46;
        return `<text x="56" y="${y}" fill="#ffffff" font-size="40" font-weight="800" font-family="Arial, Helvetica, sans-serif">${escapeForSvg(line)}</text>`;
    })
        .join("");
    const metaY = Math.min(titleStartY + titleLines.length * 46 + 16, footerY - 28);
    const meta = [input.dateLabel, input.locationLabel]
        .map((s) => s.trim())
        .filter(Boolean)
        .join("  ·  ");
    const category = (input.category || "").trim();
    const badge = category
        ? `<rect x="56" y="292" rx="16" ry="16" width="${Math.min(220, 28 + category.length * 11)}" height="32" fill="rgba(20,24,45,0.45)"/>
       <text x="72" y="314" fill="#ffffff" font-size="16" font-weight="700" font-family="Arial, Helvetica, sans-serif">${escapeForSvg(category)}</text>`
        : "";
    const leftLabelY = footerY + Math.round(exports.SOCIAL_FOOTER_HEIGHT / 2) + 8;
    const svg = `<?xml version="1.0" encoding="UTF-8"?>
<svg width="${exports.SOCIAL_WIDTH}" height="${exports.SOCIAL_HEIGHT}" viewBox="0 0 ${exports.SOCIAL_WIDTH} ${exports.SOCIAL_HEIGHT}" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="g" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0%" stop-color="#14182D" stop-opacity="0.72"/>
      <stop offset="42%" stop-color="#14182D" stop-opacity="0.38"/>
      <stop offset="78%" stop-color="#14182D" stop-opacity="0.08"/>
      <stop offset="100%" stop-color="#14182D" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="gb" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="#14182D" stop-opacity="0"/>
      <stop offset="55%" stop-color="#14182D" stop-opacity="0.12"/>
      <stop offset="100%" stop-color="#14182D" stop-opacity="0.42"/>
    </linearGradient>
  </defs>
  <rect width="100%" height="${footerY}" fill="url(#g)"/>
  <rect width="100%" height="${footerY}" fill="url(#gb)"/>
  <rect x="0" y="${footerY}" width="1200" height="${exports.SOCIAL_FOOTER_HEIGHT}" fill="#F7F6F3"/>
  <rect x="0" y="${footerY}" width="1200" height="2" fill="#313A5F"/>
  ${badge}
  ${titleSpans}
  <text x="56" y="${metaY}" fill="#F3F4F6" font-size="22" font-weight="600" font-family="Arial, Helvetica, sans-serif">${escapeForSvg(meta)}</text>
  <text x="56" y="${leftLabelY}" fill="#313A5F" font-size="24" font-weight="700" font-family="Arial, Helvetica, sans-serif">Evento no Remdy</text>
</svg>`;
    return Buffer.from(svg);
}
async function navyFallbackBackground() {
    return (0, sharp_1.default)({
        create: {
            width: exports.SOCIAL_WIDTH,
            height: exports.SOCIAL_HEIGHT,
            channels: 3,
            background: exports.REMDY_NAVY_DARK,
        },
    })
        .jpeg({ quality: 85 })
        .toBuffer();
}
async function coverLayer(coverBytes) {
    return (0, sharp_1.default)(coverBytes)
        .rotate()
        .resize(exports.SOCIAL_WIDTH, exports.SOCIAL_HEIGHT, {
        fit: "cover",
        position: "attention",
        withoutEnlargement: false,
    })
        .modulate({ brightness: 1.06, saturation: 1.08 })
        .jpeg({ quality: 90 })
        .toBuffer();
}
async function encodeUnderLimit(composited) {
    let quality = 82;
    let buf = await composited.jpeg({ quality, mozjpeg: true }).toBuffer();
    while (buf.length > exports.SOCIAL_TARGET_BYTES && quality > 55) {
        quality -= 6;
        buf = await composited.jpeg({ quality, mozjpeg: true }).toBuffer();
    }
    if (buf.length > exports.SOCIAL_MAX_BYTES) {
        // última tentativa mais agressiva
        buf = await composited.jpeg({ quality: 48, mozjpeg: true }).toBuffer();
    }
    if (buf.length > exports.SOCIAL_MAX_BYTES) {
        throw new Error(`social_image_too_large:${buf.length}`);
    }
    return buf;
}
/**
 * Renderiza JPEG 1200×630.
 * `coverBytes` opcional — se ausente, usa fundo navy Remdy.
 */
async function renderSocialJpeg(input, coverBytes) {
    const contentHash = computeSocialContentHash(input);
    const picked = pickCoverSource(input);
    let source = picked.source;
    let base;
    if (coverBytes && coverBytes.length > 0) {
        base = await coverLayer(coverBytes);
        source = picked.source === "brand_fallback" ? "cover" : picked.source;
    }
    else {
        base = await navyFallbackBackground();
        source = "brand_fallback";
    }
    const overlay = buildOverlaySvg(input);
    const logo = await (0, sharp_1.default)(loadRemdyLogoPng())
        .resize({
        width: exports.SOCIAL_BRAND_WIDTH,
        fit: "inside",
        withoutEnlargement: false,
    })
        .png()
        .toBuffer();
    const logoMeta = await (0, sharp_1.default)(logo).metadata();
    const logoW = logoMeta.width || exports.SOCIAL_BRAND_WIDTH;
    const logoH = logoMeta.height || Math.round(exports.SOCIAL_BRAND_WIDTH / 3);
    const logoLeft = exports.SOCIAL_WIDTH - exports.SOCIAL_BRAND_MARGIN_RIGHT - logoW;
    const logoTop = exports.SOCIAL_HEIGHT - exports.SOCIAL_BRAND_MARGIN_BOTTOM - logoH;
    const composited = (0, sharp_1.default)(base)
        .composite([
        { input: overlay, top: 0, left: 0 },
        { input: logo, top: logoTop, left: logoLeft },
    ])
        .resize(exports.SOCIAL_WIDTH, exports.SOCIAL_HEIGHT, { fit: "fill" });
    const buffer = await encodeUnderLimit(composited);
    const meta = await (0, sharp_1.default)(buffer).metadata();
    if (meta.width !== exports.SOCIAL_WIDTH || meta.height !== exports.SOCIAL_HEIGHT) {
        throw new Error(`social_image_bad_dims:${meta.width}x${meta.height}`);
    }
    return {
        buffer,
        width: exports.SOCIAL_WIDTH,
        height: exports.SOCIAL_HEIGHT,
        mime: exports.SOCIAL_MIME,
        bytes: buffer.length,
        contentHash,
        source,
    };
}
function defaultFetchBytes(url) {
    return fetch(url, {
        headers: { "User-Agent": "RemdySocialImage/1.0" },
        signal: AbortSignal.timeout(12000),
    })
        .then(async (res) => {
        if (!res.ok)
            return null;
        const ct = (res.headers.get("content-type") || "").toLowerCase();
        if (ct && !ct.startsWith("image/"))
            return null;
        const ab = await res.arrayBuffer();
        const buf = Buffer.from(ab);
        // Recusar capas absurdamente grandes sem reencode prévio? sharp aguenta; limit 15MB
        if (buf.length > 15 * 1024 * 1024)
            return null;
        return buf;
    })
        .catch(() => null);
}
/**
 * Garante arte social idempotente em disco local.
 * - Reutiliza se hash igual e arquivo existe
 * - Escreve novo arquivo `og_{hash}.jpg` antes de apagar o antigo
 * - Falha não lança após retries esgotados? — lança para o caller decidir fallback
 */
async function ensureLocalSocialImage(options) {
    const hash = computeSocialContentHash(options.input);
    const dir = path.join(options.localDir, options.input.eventId);
    fs.mkdirSync(dir, { recursive: true });
    const fileName = `og_${hash}.jpg`;
    const localPath = path.join(dir, fileName);
    const publicUrl = `http://127.0.0.1:8787/social/${options.input.eventId}/${fileName}`;
    if (options.existingHash === hash &&
        options.existingUrl &&
        fs.existsSync(localPath)) {
        const st = fs.statSync(localPath);
        return {
            url: options.existingUrl || publicUrl,
            localPath,
            contentHash: hash,
            generated: false,
            reused: true,
            bytes: st.size,
            mime: exports.SOCIAL_MIME,
            width: exports.SOCIAL_WIDTH,
            height: exports.SOCIAL_HEIGHT,
            source: pickCoverSource(options.input).source,
        };
    }
    if (fs.existsSync(localPath)) {
        const st = fs.statSync(localPath);
        return {
            url: publicUrl,
            localPath,
            contentHash: hash,
            generated: false,
            reused: true,
            bytes: st.size,
            mime: exports.SOCIAL_MIME,
            width: exports.SOCIAL_WIDTH,
            height: exports.SOCIAL_HEIGHT,
            source: pickCoverSource(options.input).source,
        };
    }
    const retries = options.retries ?? 2;
    const fetchBytes = options.fetchBytes || defaultFetchBytes;
    let lastErr;
    for (let attempt = 0; attempt <= retries; attempt++) {
        try {
            const picked = pickCoverSource(options.input);
            let coverBytes = null;
            if (picked.url) {
                coverBytes = await fetchBytes(picked.url);
            }
            const rendered = await renderSocialJpeg(options.input, coverBytes);
            const tmpPath = path.join(dir, `.tmp_${hash}_${Date.now()}.jpg`);
            fs.writeFileSync(tmpPath, rendered.buffer);
            fs.renameSync(tmpPath, localPath);
            // Apaga versões antigas somente depois da nova pronta
            for (const name of fs.readdirSync(dir)) {
                if (name.startsWith("og_") &&
                    name.endsWith(".jpg") &&
                    name !== fileName) {
                    try {
                        fs.unlinkSync(path.join(dir, name));
                    }
                    catch {
                        /* ignore */
                    }
                }
            }
            return {
                url: publicUrl,
                localPath,
                contentHash: rendered.contentHash,
                generated: true,
                reused: false,
                bytes: rendered.bytes,
                mime: rendered.mime,
                width: rendered.width,
                height: rendered.height,
                source: rendered.source,
            };
        }
        catch (e) {
            lastErr = e;
        }
    }
    throw lastErr instanceof Error ? lastErr : new Error(String(lastErr));
}
/**
 * Resolve URL OG segura para SSR.
 * Nunca devolve capa Unsplash multi-MB quando há arte social.
 */
function resolveOgImageUrl(options) {
    const social = (options.socialShareImageUrl || "").trim();
    if (/^https:\/\//i.test(social) || /^http:\/\/127\.0\.0\.1:8787\//i.test(social)) {
        return { url: social, kind: "social" };
    }
    const brand = (options.brandFallbackUrl || "").trim();
    if (brand)
        return { url: brand, kind: "brand_fallback" };
    // Não usar coverUrl cru (pode ter vários MB / Unsplash).
    return { url: "", kind: "none" };
}
/** Campos Firestore que disparam regeneração. */
exports.SOCIAL_TRIGGER_FIELDS = [
    "title",
    "coverUrl",
    "photoUrls",
    "startAt",
    "endAt",
    "eventTimeZone",
    "city",
    "state",
    "stateName",
    "country",
    "countryCode",
    "placeName",
    "placeDisplay",
    "address",
    "category",
];
function socialInputsChanged(before, after) {
    if (!before)
        return true;
    for (const key of exports.SOCIAL_TRIGGER_FIELDS) {
        const a = JSON.stringify(after[key] ?? null);
        const b = JSON.stringify(before[key] ?? null);
        if (a !== b)
            return true;
    }
    return false;
}
//# sourceMappingURL=public_event_social_image.js.map