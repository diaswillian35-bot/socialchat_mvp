/**
 * Log de moderação: só ids e a decisão.
 * Descarta URL, texto, e-mail e token.
 */

const ALLOWED = new Set([
  "uid",
  "conversationId",
  "messageId",
  "groupId",
  "decision",
  "reason",
  "pathHash",
  "reportId",
  "attempts",
  "source",
  "parentId",
]);

function looksSensitive(value) {
  if (typeof value !== "string") return false;
  const s = value.toLowerCase();
  if (s.includes("http://") || s.includes("https://") || s.includes("gs://")) {
    return true;
  }
  if (s.includes("@")) return true;
  if (s.length > 200) return true;
  return false;
}

function sanitizeModerationLog(event, fields) {
  const out = { event: String(event || "moderation") };
  const src = fields || {};
  for (const key of Object.keys(src)) {
    if (!ALLOWED.has(key)) continue;
    const value = src[key];
    if (value == null) continue;
    if (typeof value === "number" && Number.isFinite(value)) {
      out[key] = value;
      continue;
    }
    const asString = String(value);
    if (!asString || looksSensitive(asString)) continue;
    out[key] = asString.slice(0, 128);
  }
  return out;
}

function safeModerationLog(event, fields) {
  const line = sanitizeModerationLog(event, fields);
  console.log(JSON.stringify(line));
  return line;
}

module.exports = {
  sanitizeModerationLog,
  safeModerationLog,
};
