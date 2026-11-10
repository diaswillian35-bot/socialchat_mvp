/** Strikes contam só dentro de uma janela (b44: padrão 90 dias; antes 30). */

const WINDOW_MS = 90 * 24 * 60 * 60 * 1000;

function eventsInWindow(events, nowMs, windowMs = WINDOW_MS) {
  const since = Number(nowMs) - Number(windowMs);
  const list = Array.isArray(events) ? events : [];
  return list
    .map((value) => Number(value))
    .filter((ms) => Number.isFinite(ms) && ms >= since);
}

function nextStrikeEvents(events, nowMs, windowMs = WINDOW_MS) {
  const recent = eventsInWindow(events, nowMs, windowMs);
  recent.push(Number(nowMs));
  return recent.slice(-50);
}

module.exports = {
  WINDOW_MS,
  eventsInWindow,
  nextStrikeEvents,
};
