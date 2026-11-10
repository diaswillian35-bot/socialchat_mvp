/**
 * Decisão SafeSearch e casamento de path. Sem download do arquivo e sem log de URL.
 */

const crypto = require("crypto");

const RANK = Object.freeze({
  UNKNOWN: 0,
  VERY_UNLIKELY: 1,
  UNLIKELY: 2,
  POSSIBLE: 3,
  LIKELY: 4,
  VERY_LIKELY: 5,
});

function rankOf(value) {
  const key = String(value || "UNKNOWN").trim().toUpperCase();
  return Object.prototype.hasOwnProperty.call(RANK, key) ? RANK[key] : 0;
}

function decideSafeSearch(annotation, thresholds) {
  const t = thresholds || {};
  const adultAt = rankOf(t.adultBlockAt || "LIKELY");
  const racyBlockAt = rankOf(t.racyBlockAt || "VERY_LIKELY");
  const racyReviewAt = rankOf(t.racyReviewAt || "LIKELY");
  const adult = rankOf(annotation && annotation.adult);
  const racy = rankOf(annotation && annotation.racy);
  if (adult >= adultAt) return { action: "block", reason: "image_adult" };
  if (racy >= racyBlockAt) return { action: "block", reason: "image_racy" };
  if (racy >= racyReviewAt) return { action: "review", reason: "image_racy" };
  return { action: "allow", reason: "" };
}

function storagePathFromImageUrl(url) {
  const s = String(url || "").trim();
  if (!s) return "";
  if (s.startsWith("gs://")) {
    const slash = s.indexOf("/", 5);
    return slash < 0 ? "" : decodeURIComponent(s.slice(slash + 1));
  }
  const marker = "/o/";
  const idx = s.indexOf(marker);
  if (idx >= 0) {
    const rest = s.slice(idx + marker.length).split("?")[0];
    try {
      return decodeURIComponent(rest);
    } catch (_) {
      return rest;
    }
  }
  if (/^(?:chat_images|groups|users|events|places)\//.test(s)) return s.split("?")[0];
  return "";
}

function isModeratedImagePath(filePath) {
  const p = String(filePath || "");
  if (!p || p.startsWith("quarantine/")) return false;
  if (p.startsWith("chat_images/")) {
    const parts = p.split("/");
    return parts.length === 3 && Boolean(parts[1]) && Boolean(parts[2]);
  }
  if (/^groups\/[^/]+\/images\/[^/]+\/[^/]+$/.test(p)) return true;
  return assetContextFromPath(p).kind !== "";
}

/**
 * b44: fotos fora do chat que também passam pelo SafeSearch.
 * users/{uid}/(profile|gallery|...)/{file}  -> perfil/galeria
 * events/{eventId}/photos/{file}            -> evento
 * places/{placeId}/(photos|menu)/{file}     -> local (o PDF do cardápio fica de fora pelo contentType)
 * groups/{groupId}/avatar/{file}            -> avatar/capa do grupo
 */
function assetContextFromPath(filePath) {
  const p = String(filePath || "");
  let m = p.match(/^users\/([^/]+)\/(?:[^/]+\/)*[^/]+$/);
  if (m) return { kind: "profile", ownerUid: m[1], docId: m[1] };
  m = p.match(/^events\/([^/]+)\/photos\/[^/]+$/);
  if (m) return { kind: "event", docId: m[1], ownerUid: "" };
  m = p.match(/^places\/([^/]+)\/(?:photos|menu)\/[^/]+$/);
  if (m && m[1] !== "inbox") return { kind: "place", docId: m[1], ownerUid: "" };
  m = p.match(/^groups\/([^/]+)\/avatar\/[^/]+$/);
  if (m) return { kind: "group_avatar", docId: m[1], ownerUid: "" };
  return { kind: "", docId: "", ownerUid: "" };
}

/** Docs que podem apontar para a foto (o servidor limpa o campo quando bloqueia). */
function assetDocPaths(ctx) {
  switch (ctx && ctx.kind) {
    case "profile": return [`users/${ctx.docId}`, `publicUsers/${ctx.docId}`];
    case "event": return [`events/${ctx.docId}`];
    case "place": return [`places/${ctx.docId}`];
    case "group_avatar": return [`groups/${ctx.docId}`];
    default: return [];
  }
}

function refersTo(value, filePath) {
  return typeof value === "string" && value.length > 0 && storagePathFromImageUrl(value) === filePath;
}

/**
 * Patch que remove a foto de um doc: string vira "", lista perde o item,
 * item de lista que é mapa com a URL sai. Só campos de 1º nível.
 */
function scrubPatch(data, filePath) {
  const patch = {};
  for (const [k, v] of Object.entries(data || {})) {
    if (refersTo(v, filePath)) patch[k] = "";
    else if (Array.isArray(v)) {
      const next = v.filter((item) => {
        if (refersTo(item, filePath)) return false;
        if (item && typeof item === "object" && !Array.isArray(item)) {
          return !Object.values(item).some((x) => refersTo(x, filePath));
        }
        return true;
      });
      if (next.length !== v.length) patch[k] = next;
    }
  }
  return patch;
}

function pathHash(filePath) {
  return crypto.createHash("sha256").update(String(filePath || "")).digest("hex");
}

function quarantinePath(filePath) {
  return `quarantine/${String(filePath || "").replace(/^\/+/, "")}`;
}

function uploaderFromPath(filePath, metadata) {
  const meta = metadata || {};
  const fromMeta = String(meta.fromUid || meta.uploaderId || "").trim();
  if (fromMeta) return fromMeta;
  const p = String(filePath || "");
  const group = p.match(/^groups\/[^/]+\/images\/([^/]+)\//);
  if (group) return group[1];
  return "";
}

/**
 * Strike só com remetente confirmado.
 * Chat: metadata.fromUid. Grupo: o uid do path, e bate com fromUid se os dois existirem.
 */
function confirmedUploader(filePath, metadata) {
  const metaUid = String((metadata && metadata.fromUid) || "").trim();
  const p = String(filePath || "");
  const group = p.match(/^groups\/[^/]+\/images\/([^/]+)\//);
  const pathUid = group ? group[1] : "";
  if (p.startsWith("chat_images/")) return metaUid;
  // b44: users/{uid}/... só o próprio uid grava (storage.rules), então o path confirma.
  const asset = assetContextFromPath(p);
  if (asset.kind === "profile") return asset.ownerUid;
  if (asset.kind) return "";
  if (pathUid && metaUid && pathUid !== metaUid) return "";
  return metaUid || pathUid;
}

function isTemporaryVisionError(err) {
  const code = Number(err && (err.code || err.status || err.statusCode)) || 0;
  if ([408, 429, 500, 502, 503, 504].includes(code)) return true;
  const message = String((err && err.message) || "").toLowerCase();
  return /unavailable|deadline|econnreset|etimedout|socket hang up|temporar|resource exhausted/.test(
    message,
  );
}

function contextFromPath(filePath) {
  const p = String(filePath || "");
  const dm = p.match(/^chat_images\/([^/]+)\//);
  if (dm) return { kind: "dm", parentId: dm[1] };
  const group = p.match(/^groups\/([^/]+)\/images\//);
  if (group) return { kind: "group", parentId: group[1] };
  return { kind: "", parentId: "" };
}

function isImageContentType(contentType) {
  return String(contentType || "").toLowerCase().startsWith("image/");
}

/** attempts é o valor já gravado depois do incremento. */
function uncheckedOutcome(attempts) {
  const n = Number(attempts) || 0;
  if (n >= 3) return "stop";
  return "retry";
}

module.exports = {
  assetContextFromPath,
  assetDocPaths,
  scrubPatch,
  RANK,
  decideSafeSearch,
  storagePathFromImageUrl,
  isModeratedImagePath,
  pathHash,
  quarantinePath,
  uploaderFromPath,
  confirmedUploader,
  contextFromPath,
  isImageContentType,
  uncheckedOutcome,
  isTemporaryVisionError,
};
