/**
 * b44: punição em degraus. Pontos válidos na janela (padrão 90 dias):
 * 1 = aviso; 2 = 24 h sem falar; 3 = 7 dias sem falar; 4+ = banimento
 * pendente (status "suspended_pending_review", o admin confirma).
 * appConfig/moderation.ladder = { windowDays, muteHours: [24, 168] } ajusta sem deploy.
 */

const DAY = 24 * 60 * 60 * 1000;
const DEFAULT_WINDOW_DAYS = 90;
const DEFAULT_MUTE_HOURS = [24, 168];

function ladderConfig(cfg) {
  const l = (cfg && cfg.ladder) || {};
  const days = Number(l.windowDays);
  const mh = Array.isArray(l.muteHours) ? l.muteHours.map(Number) : [];
  return {
    windowMs: (Number.isFinite(days) && days > 0 ? days : DEFAULT_WINDOW_DAYS) * DAY,
    muteHours: [
      Number.isFinite(mh[0]) && mh[0] > 0 ? mh[0] : DEFAULT_MUTE_HOURS[0],
      Number.isFinite(mh[1]) && mh[1] > 0 ? mh[1] : DEFAULT_MUTE_HOURS[1],
    ],
  };
}

/**
 * @param {number} points pontos válidos já contando o atual
 * @param {number} nowMs
 * @param {object} cfg config de moderação
 * @returns {{level:number, action:'warn'|'mute'|'suspend', mutedUntilMs?:number}}
 */
function ladderStep(points, nowMs, cfg) {
  const { muteHours } = ladderConfig(cfg);
  const n = Math.max(1, Number(points) || 1);
  if (n === 1) return { level: 1, action: "warn" };
  if (n === 2) return { level: 2, action: "mute", mutedUntilMs: nowMs + muteHours[0] * 3600 * 1000 };
  if (n === 3) return { level: 3, action: "mute", mutedUntilMs: nowMs + muteHours[1] * 3600 * 1000 };
  return { level: 4, action: "suspend" };
}

/** Nunca rebaixa banido/suspenso, nem encurta um "sem falar" maior que já existe. */
function moderationPatch(prevModeration, step, nowMs) {
  const prev = prevModeration || {};
  const st = String(prev.status || "");
  if (st === "banned" || st === "suspended_pending_review") return null;
  if (step.action === "suspend") {
    return { status: "suspended_pending_review", level: 4, reason: "strikes" };
  }
  if (step.action === "mute") {
    const prevUntil = toMs(prev.mutedUntil);
    const until = Math.max(step.mutedUntilMs, prevUntil && prevUntil > nowMs ? prevUntil : 0);
    return { status: "muted", level: step.level, mutedUntilMs: until, reason: "strikes" };
  }
  return { status: st === "muted" && toMs(prev.mutedUntil) > nowMs ? "muted" : "warned", level: 1, reason: "strikes" };
}

function toMs(v) {
  if (!v) return 0;
  if (typeof v === "number") return v;
  if (v instanceof Date) return v.getTime();
  if (typeof v.toMillis === "function") return v.toMillis();
  if (typeof v._seconds === "number") return v._seconds * 1000;
  if (typeof v.seconds === "number") return v.seconds * 1000;
  return 0;
}

/** Sem falar agora? (PV, grupo, comentário de evento, sala de áudio só-ouvir) */
function isMutedNow(userData, nowMs = Date.now()) {
  const m = userData && userData.moderation;
  if (!m || m.status !== "muted") return false;
  return toMs(m.mutedUntil) > nowMs;
}

module.exports = { DAY, DEFAULT_WINDOW_DAYS, ladderConfig, ladderStep, moderationPatch, isMutedNow, toMs };
