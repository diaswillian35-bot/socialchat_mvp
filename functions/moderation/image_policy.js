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
  if (s.startsWith("chat_images/") || s.startsWith("groups/")) return s.split("?")[0];
  return "";
}

function isModeratedImagePath(filePath) {
  const p = String(filePath || "");
  if (!p || p.startsWith("quarantine/")) return false;
  if (p.startsWith("chat_images/")) {
    const parts = p.split("/");
    return parts.length === 3 && Boolean(parts[1]) && Boolean(parts[2]);
  }
  return /^groups\/[^/]+\/images\/[^/]+\/[^/]+$/.test(p);
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
