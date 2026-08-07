/** Lógica pura — contadores atômicos, mirror, admin, paginação. */

/** Alinhado a PresenceRtdbConfig.connectionStaleAfter (3 min). */
const CONNECTION_STALE_MS = 3 * 60 * 1000;

function normalizeCountryCode(raw) {
  return String(raw || "")
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_-]/g, "")
    .slice(0, 16);
}

/**
 * Remove conexões com timestamp velho (ms ServerValue).
 * Retorna { removed, remaining } — remaining só com timestamps frescos.
 */
function pruneStaleConnectionsMap(connections, nowMs = Date.now(), staleMs = CONNECTION_STALE_MS) {
  const src =
    connections && typeof connections === "object" ? connections : {};
  const updates = {};
  const remaining = {};
  let removed = 0;
  for (const [id, ts] of Object.entries(src)) {
    if (typeof ts === "number" && Number.isFinite(ts)) {
      if (nowMs - ts > staleMs) {
        updates[id] = null;
        removed += 1;
        continue;
      }
      remaining[id] = ts;
      continue;
    }
    // Legado sem timestamp numérico: tratar como morto (não renovável).
    updates[id] = null;
    removed += 1;
  }
  return { updates, remaining, removed, freshCount: Object.keys(remaining).length };
}

function counterDeltaFromCounts({ wasOnline, isOnline }) {
  if (!wasOnline && isOnline) return "enter";
  if (wasOnline && !isOnline) return "leave";
  return "none";
}

function clientWritePlan() {
  return {
    writesConnection: true,
    writesIndex: false,
    writesCounters: false,
  };
}

/**
 * Patch atômico. País vazio↔válido é country_move (worldDelta=0).
 */
function computeAtomicPresencePatch({
  wasOnline,
  prevCountry,
  isOnline,
  nextCountry,
}) {
  const prev = normalizeCountryCode(prevCountry);
  const next = normalizeCountryCode(nextCountry);

  if (!wasOnline && isOnline) {
    const countryDeltas = {};
    if (next) countryDeltas[next] = 1;
    return {
      op: "enter",
      nextOnline: true,
      nextCountry: next,
      worldDelta: 1,
      countryDeltas,
    };
  }

  if (wasOnline && !isOnline) {
    const countryDeltas = {};
    if (prev) countryDeltas[prev] = -1;
    return {
      op: "leave",
      nextOnline: false,
      nextCountry: "",
      worldDelta: -1,
      countryDeltas,
    };
  }

  // Online contínuo: troca de país (inclui "" → br, br → "", br → ca)
  if (wasOnline && isOnline && prev !== next) {
    const countryDeltas = {};
    if (prev) countryDeltas[prev] = -1;
    if (next) countryDeltas[next] = 1;
    return {
      op: "country_move",
      nextOnline: true,
      nextCountry: next,
      worldDelta: 0,
      countryDeltas,
    };
  }

  return {
    op: "none",
    nextOnline: wasOnline,
    nextCountry: wasOnline ? prev : "",
    worldDelta: 0,
    countryDeltas: {},
  };
}

function applyCounterDeltas(counters, { worldDelta, countryDeltas }) {
  const next = {
    world: Math.max(0, (counters.world || 0) + (worldDelta || 0)),
    byCountry: { ...(counters.byCountry || {}) },
  };
  for (const [cc, d] of Object.entries(countryDeltas || {})) {
    const cur = next.byCountry[cc] || 0;
    const v = Math.max(0, cur + d);
    if (v === 0) delete next.byCountry[cc];
    else next.byCountry[cc] = v;
  }
  return next;
}

function simulateConcurrentPatches(initialState, patchesDesired) {
  let state = {
    online: !!initialState.online,
    country: normalizeCountryCode(initialState.country || ""),
  };
  let counters = {
    world: initialState.world || 0,
    byCountry: { ...(initialState.byCountry || {}) },
  };
  const applied = [];

  for (const desired of patchesDesired) {
    const patch = computeAtomicPresencePatch({
      wasOnline: state.online,
      prevCountry: state.country,
      isOnline: desired.isOnline,
      nextCountry: desired.country,
    });
    if (patch.op !== "none") {
      counters = applyCounterDeltas(counters, patch);
      state = { online: patch.nextOnline, country: patch.nextCountry };
    }
    applied.push(patch.op);
  }

  return { state, counters, applied };
}

function counterDrift({
  expectedByCountry,
  expectedWorld,
  actualByCountry,
  actualWorld,
}) {
  const drift = {
    world: (actualWorld || 0) - (expectedWorld || 0),
    countries: {},
  };
  const keys = new Set([
    ...Object.keys(expectedByCountry || {}),
    ...Object.keys(actualByCountry || {}),
  ]);
  for (const k of keys) {
    const d = (actualByCountry[k] || 0) - (expectedByCountry[k] || 0);
    if (d !== 0) drift.countries[k] = d;
  }
  return drift;
}

/** Países a zerar: existiam no counter, ausentes no rebuild (count>0). */
function countriesToZero(existingCountryCodes, rebuiltByCountry) {
  const rebuilt = rebuiltByCountry || {};
  const out = [];
  for (const cc of existingCountryCodes || []) {
    const n = normalizeCountryCode(cc);
    if (!n) continue;
    if (!(n in rebuilt)) out.push(n);
  }
  return [...new Set(out)];
}

/**
 * Mirror: se op=none mas mirrorPending, ainda precisa espelhar (sem novo delta).
 */
function shouldMirrorAfterSync({ op, changed, mirrorPending }) {
  if (changed) return true;
  if (mirrorPending) return true;
  if (op === "none" && mirrorPending) return true;
  return false;
}

/** Validação de parâmetros da callable. */
function parseReconcileCallArgs(data = {}) {
  const errors = [];
  let pageSize = Number(data.pageSize);
  if (!Number.isFinite(pageSize)) pageSize = 50;
  pageSize = Math.floor(pageSize);
  if (pageSize < 1 || pageSize > 100) {
    errors.push("pageSize must be 1..100");
    pageSize = Math.min(100, Math.max(1, pageSize || 50));
  }

  let startAfterId = data.startAfterId;
  if (startAfterId == null || startAfterId === "") {
    startAfterId = null;
  } else if (typeof startAfterId !== "string") {
    errors.push("startAfterId must be string");
    startAfterId = null;
  } else if (!/^[A-Za-z0-9_-]{1,128}$/.test(startAfterId)) {
    errors.push("startAfterId invalid");
    startAfterId = null;
  }

  return {
    ok: errors.length === 0,
    errors,
    pageSize,
    startAfterId,
  };
}

/**
 * Admin oficial da callable de reconciliação — NÃO confiar em campos
 * forjáveis no doc users (isAdmin / isPlatformAdmin / role).
 *
 * Permitido somente:
 * 1) custom claim admin|isMaster
 * 2) documento admins/{uid} (só servidor)
 * 3) users.isMaster == true (campo já protegido nas Rules)
 */
function evaluatePresenceReconcileAdmin({
  authenticated,
  token = {},
  userData = null,
  adminDocExists = false,
}) {
  if (!authenticated) {
    return { allowed: false, code: "unauthenticated" };
  }
  if (token.admin === true || token.isMaster === true) {
    return { allowed: true, via: "claim" };
  }
  if (adminDocExists) {
    return { allowed: true, via: "adminsDoc" };
  }
  if (userData && userData.isMaster === true) {
    return { allowed: true, via: "isMaster" };
  }
  return { allowed: false, code: "permission-denied" };
}

/**
 * Checkpoint de reconciliação agendada.
 * @returns next checkpoint state
 */
function advanceReconcileCheckpoint(cp, pageResult, { maxPagesThisRun, pagesDone }) {
  const phase = cp?.phase || "sync";
  if (phase === "sync") {
    if (pageResult.nextPage) {
      return {
        phase: "sync",
        cursor: pageResult.nextPage,
        incomplete: true,
        readyForRebuild: false,
        pagesDone: (pagesDone || 0) + 1,
      };
    }
    return {
      phase: "rebuild",
      cursor: null,
      incomplete: false,
      readyForRebuild: true,
      pagesDone: (pagesDone || 0) + 1,
    };
  }
  return {
    phase: "idle",
    cursor: null,
    incomplete: false,
    readyForRebuild: false,
    pagesDone: pagesDone || 0,
  };
}

/** Simula falha de mirror entre etapas e retry sem duplicar delta. */
function simulateMirrorFailureRetry({
  initialState,
  desiredOnline,
  country,
  failAt, // 'after_firestore' | 'after_world' | 'after_country' | 'after_presenceOnline'
}) {
  const patch1 = computeAtomicPresencePatch({
    wasOnline: initialState.online,
    prevCountry: initialState.country,
    isOnline: desiredOnline,
    nextCountry: country,
  });

  let counters = {
    world: initialState.world || 0,
    byCountry: { ...(initialState.byCountry || {}) },
  };
  let state = {
    online: initialState.online,
    country: initialState.country || "",
    mirrorPending: false,
  };

  // Commit Firestore (sempre)
  if (patch1.op !== "none") {
    counters = applyCounterDeltas(counters, patch1);
    state = {
      online: patch1.nextOnline,
      country: patch1.nextCountry,
      mirrorPending: false,
    };
  }

  const mirrorSteps = ["world", "country", "presenceOnline"];
  let mirrored = { world: false, country: false, presenceOnline: false };
  const failIndex = {
    after_firestore: -1,
    after_world: 0,
    after_country: 1,
    after_presenceOnline: 2,
  }[failAt];

  if (failIndex < 0) {
    state.mirrorPending = true;
  } else {
    for (let i = 0; i < mirrorSteps.length; i++) {
      if (i === failIndex) {
        state.mirrorPending = true;
        break;
      }
      mirrored[mirrorSteps[i]] = true;
    }
  }

  // Retry: op none, mas mirrorPending → espelha sem novo delta
  const patch2 = computeAtomicPresencePatch({
    wasOnline: state.online,
    prevCountry: state.country,
    isOnline: desiredOnline,
    nextCountry: country,
  });
  assertNoSecondDelta(patch2);

  const needsMirror = shouldMirrorAfterSync({
    op: patch2.op,
    changed: false,
    mirrorPending: state.mirrorPending,
  });

  if (needsMirror) {
    mirrored = { world: true, country: true, presenceOnline: true };
    state.mirrorPending = false;
  }

  return {
    firstOp: patch1.op,
    secondOp: patch2.op,
    counters,
    state,
    mirrored,
  };
}

function assertNoSecondDelta(patch) {
  if (patch.op !== "none") {
    throw new Error(`retry must not re-apply delta, got ${patch.op}`);
  }
}

module.exports = {
  normalizeCountryCode,
  CONNECTION_STALE_MS,
  pruneStaleConnectionsMap,
  counterDeltaFromCounts,
  clientWritePlan,
  computeAtomicPresencePatch,
  applyCounterDeltas,
  simulateConcurrentPatches,
  counterDrift,
  countriesToZero,
  shouldMirrorAfterSync,
  parseReconcileCallArgs,
  evaluatePresenceReconcileAdmin,
  advanceReconcileCheckpoint,
  simulateMirrorFailureRetry,
};
