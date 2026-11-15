"use strict";

/**
 * Ops notify: first adult verification → ONLY configured portal admin (Willian).
 * Never fan-out; never use isMaster; never regional new_user_push.
 *
 * Counter: adminOpsStats/newUsers — incremented only when opsNewUserNotices/{uid}
 * is first created (idempotent). Independent of FCM delivery / push pause.
 */

const SENSITIVE_KEYS = [
  "email",
  "phone",
  "phoneNumber",
  "dateOfBirth",
  "password",
  "fcmToken",
];

const OPS_STATS_COLLECTION = "adminOpsStats";
const OPS_STATS_DOC = "newUsers";
const OPS_SETTINGS_COLLECTION = "adminOpsSettings";
const OPS_SETTINGS_DOC = "newUserNotify";
const OPS_LEDGER_COLLECTION = "opsNewUserNotices";

function asTrimmed(value, max = 128) {
  const s = (value == null ? "" : String(value)).trim();
  if (s.length <= max) return s;
  return s.slice(0, max);
}

function normalizeCountry(value) {
  return asTrimmed(value, 8).toUpperCase();
}

function readHomeCountry(userData) {
  const data = userData && typeof userData === "object" ? userData : {};
  return (
    normalizeCountry(data.homeCountryCode) ||
    normalizeCountry(data.countryCode) ||
    normalizeCountry(data.country) ||
    ""
  );
}

/**
 * First successful adult verify only (not re-verify / rejected).
 * Same gate used by confirmAdultAge → notifyOpsAdminOfNewVerifiedUser.
 */
function shouldNotifyOnFirstAdultVerify(priorStatus, newlyAdultVerified) {
  if (newlyAdultVerified !== true) return false;
  const prior = (priorStatus || "").toString().trim().toLowerCase();
  if (prior === "verified") return false;
  if (prior === "rejected") return false;
  return true;
}

/**
 * Durable snapshot of users who completed the SAME path that fires the ops hook:
 * confirmAdultAge sets ageVerificationStatus="verified" and ageVerifiedAt when
 * result.adult === true (newlyAdultVerified). Rejected / pending / re-verify-only
 * do not count. Does NOT add extra filters the hook does not apply (ban/delete).
 */
function isOpsCountableFirstAdultVerified(userData) {
  const d = userData && typeof userData === "object" ? userData : {};
  // Exact write from age_verification.js on adult success (trim, case-sensitive).
  const status = (d.ageVerificationStatus || "").toString().trim();
  if (status !== "verified") return false;
  // Hook: ageVerifiedAt: result.adult ? now : null — required for adult success.
  if (d.ageVerifiedAt == null || d.ageVerifiedAt === "") return false;
  return true;
}

/**
 * Pick exactly one recipient from admins docs + optional env UID.
 * Prefers env OPS_ADMIN_UID when present; else single active isOwner.
 */
function resolveOpsAdminUid({ adminDocs = [], envUid = "" } = {}) {
  const fromEnv = asTrimmed(envUid, 128);
  if (fromEnv) return fromEnv;

  const owners = [];
  for (const entry of adminDocs) {
    const uid = asTrimmed(entry && entry.uid != null ? entry.uid : entry?.id, 128);
    const data = entry && entry.data ? entry.data : entry;
    if (!uid || !data || typeof data !== "object") continue;
    if (data.isActive === false) continue;
    if (data.isOwner === true) owners.push(uid);
  }
  const unique = [...new Set(owners)];
  if (unique.length === 1) return unique[0];
  return "";
}

function isOpsNewUserPushPaused(settingsDoc) {
  const d = settingsDoc && typeof settingsDoc === "object" ? settingsDoc : {};
  return d.pushPaused === true;
}

/** Push to phone only when not paused. Counter/inbox always proceed. */
function shouldSendOpsPush(settingsDoc) {
  return !isOpsNewUserPushPaused(settingsDoc);
}

/**
 * Canonical counter next state (pure). Used in tests; runtime uses FieldValue.increment.
 */
function nextOpsNewUserCount(currentCount) {
  const n = typeof currentCount === "number" && Number.isFinite(currentCount)
    ? Math.max(0, Math.floor(currentCount))
    : 0;
  return n + 1;
}

/**
 * Minimal durable + push payload — no PII.
 */
const OPS_FALLBACK_NAME = "Novo usuário";
const OPS_STATUS_AWAITING_PROFILE = "awaiting_profile";

const COUNTRY_NAMES_PT = {
  BR: "Brasil", PT: "Portugal", CA: "Canadá", US: "Estados Unidos",
  AR: "Argentina", UY: "Uruguai", PY: "Paraguai", CL: "Chile",
  CO: "Colômbia", MX: "México", PE: "Peru", BO: "Bolívia",
  VE: "Venezuela", EC: "Equador", ES: "Espanha", FR: "França",
  IT: "Itália", DE: "Alemanha", GB: "Reino Unido", IE: "Irlanda",
  NL: "Países Baixos", BE: "Bélgica", CH: "Suíça", AO: "Angola",
  MZ: "Moçambique", JP: "Japão", AU: "Austrália",
};

function isSafeOpsText(value) {
  const s = asTrimmed(value, 80);
  if (!s) return false;
  return assertOpsPayloadSafe({ v: s }).ok === true;
}

/** Nome: name → displayName → username → início do e-mail → "Novo usuário". */
function readDisplayName(userData) {
  const d = userData && typeof userData === "object" ? userData : {};
  for (const v of [d.name, d.displayName, d.username]) {
    const s = asTrimmed(v, 60);
    if (s && isSafeOpsText(s)) return s;
  }
  const email = asTrimmed(d.email, 200);
  const local = email.includes("@") ? asTrimmed(email.split("@")[0], 40) : "";
  if (local && isSafeOpsText(local)) return local;
  return OPS_FALLBACK_NAME;
}

/** País legível: nome gravado → nome pelo código → código → "não informado". */
function opsCountryLabel(code, countryName) {
  const n = asTrimmed(countryName, 40);
  if (n && isSafeOpsText(n)) return n;
  const c = normalizeCountry(code);
  return COUNTRY_NAMES_PT[c] || c || "não informado";
}

/** Opção aprovada: aviso só com nome E homeCountryCode preenchidos. */
function isProfileReadyForOpsNotice(userData) {
  const d = userData && typeof userData === "object" ? userData : {};
  const name = asTrimmed(d.name, 60);
  const home = normalizeCountry(d.homeCountryCode);
  return name.length > 0 && home.length > 0;
}

/**
 * Registro antigo (status "sent", "counted_*", etc.) ou com noticeSentAt
 * conta como já enviado — nada é reenviado para usuários antigos.
 */
function isOpsNoticeAlreadySent(ledgerData) {
  const d = ledgerData && typeof ledgerData === "object" ? ledgerData : null;
  if (!d) return true;
  if (d.noticeSentAt != null) return true;
  return d.status !== OPS_STATUS_AWAITING_PROFILE;
}

/** Gatilho: só age na transição para "perfil pronto" (sem leitura em toda escrita). */
function shouldCheckOpsNoticeOnWrite(beforeData, afterData) {
  if (!afterData) return false;
  if (!isProfileReadyForOpsNotice(afterData)) return false;
  if (beforeData && isProfileReadyForOpsNotice(beforeData)) return false;
  return true;
}

function buildOpsNewUserPayload({ newUid, country, countryName, displayName, createdAtIso }) {
  const uid = asTrimmed(newUid, 128);
  const c = normalizeCountry(country);
  const createdAt = asTrimmed(createdAtIso, 40);
  const name = asTrimmed(displayName, 60);
  return {
    type: "ops_new_user",
    newUid: uid,
    country: c,
    countryName: opsCountryLabel(c, countryName),
    displayName: name && isSafeOpsText(name) ? name : OPS_FALLBACK_NAME,
    createdAt,
  };
}

function buildOpsInboxDoc(payload) {
  const p = payload && typeof payload === "object" ? payload : {};
  const countryLabel = p.countryName || opsCountryLabel(p.country, "");
  const name = p.displayName || OPS_FALLBACK_NAME;
  return {
    title: "Novo usuário Remdy",
    body: `${name} · País: ${countryLabel}`,
    type: "ops_new_user",
    isRead: false,
    source: "ops_new_user_notify",
    newUid: p.newUid || null,
    country: p.country || null,
    displayName: name,
  };
}

function buildOpsPushCopy(payload) {
  const p = payload && typeof payload === "object" ? payload : {};
  const countryLabel = p.countryName || opsCountryLabel(p.country, "");
  const name = p.displayName || OPS_FALLBACK_NAME;
  return {
    title: "Novo usuário Remdy",
    body: `${name} · País: ${countryLabel}`,
    data: {
      type: "ops_new_user",
      newUid: String(p.newUid || ""),
      country: String(p.country || ""),
      createdAt: String(p.createdAt || ""),
    },
  };
}

/** Public TV/dashboard view model — no UID/email/phone. */
function buildOpsNewUsersDisplay({ count, lastAtIso, pushPaused }) {
  const n =
    typeof count === "number" && Number.isFinite(count)
      ? Math.max(0, Math.floor(count))
      : 0;
  return {
    label: "Novos usuários",
    count: n,
    lastUpdatedAt: asTrimmed(lastAtIso, 40) || null,
    pushPaused: pushPaused === true,
  };
}

/** Fail if payload accidentally includes sensitive keys or values shaped like email. */
function assertOpsPayloadSafe(payload) {
  const p = payload && typeof payload === "object" ? payload : {};
  for (const key of SENSITIVE_KEYS) {
    if (Object.prototype.hasOwnProperty.call(p, key)) {
      return { ok: false, reason: `forbidden_key:${key}` };
    }
    if (p.data && Object.prototype.hasOwnProperty.call(p.data, key)) {
      return { ok: false, reason: `forbidden_data_key:${key}` };
    }
  }
  const blob = JSON.stringify(p);
  if (/[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/i.test(blob)) {
    return { ok: false, reason: "email_like_value" };
  }
  // Avoid false positives on ISO timestamps (2026-09-14T12:00:00.000Z).
  const withoutIso = blob.replace(
    /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z?/g,
    "",
  );
  if (/\+?\d[\d\s().-]{8,}\d/.test(withoutIso)) {
    return { ok: false, reason: "phone_like_value" };
  }
  return { ok: true };
}

function assertDisplaySafe(display) {
  const d = display && typeof display === "object" ? display : {};
  if (d.newUid || d.email || d.phone) {
    return { ok: false, reason: "display_pii" };
  }
  return assertOpsPayloadSafe(d);
}

/**
 * Canonical ledger decision (pure). Counter increments ONLY when ledger is first created.
 * Independent of FCM success/failure and of push pause (pause only gates sendPush).
 */
function planOpsLedgerAndPush({ ledgerExists, pushPaused }) {
  if (ledgerExists === true) {
    return {
      createLedger: false,
      incrementCount: false,
      writeInbox: false,
      sendPush: false,
      reason: "duplicate",
    };
  }
  const paused = pushPaused === true;
  return {
    createLedger: true,
    incrementCount: true,
    writeInbox: true,
    sendPush: !paused,
    reason: paused ? "counted_inbox_push_paused" : "counted_inbox_push",
  };
}

/**
 * Simulate sequential first-verify events against an in-memory ledger (idempotency).
 * Returns final count and per-event outcomes — no FCM dependency.
 */
function simulateOpsCounterFromEvents(events, { pushPaused = false } = {}) {
  const ledger = new Set();
  let count = 0;
  const outcomes = [];
  for (const ev of events || []) {
    const uid = (ev && ev.uid != null ? String(ev.uid) : "").trim();
    const notify = shouldNotifyOnFirstAdultVerify(
      ev && ev.priorStatus,
      ev && ev.newlyAdultVerified,
    );
    if (!notify || !uid) {
      outcomes.push({ uid, skipped: true, reason: "not_first_adult_verify" });
      continue;
    }
    const plan = planOpsLedgerAndPush({
      ledgerExists: ledger.has(uid),
      pushPaused,
    });
    if (plan.createLedger) {
      ledger.add(uid);
      count = nextOpsNewUserCount(count);
    }
    outcomes.push({
      uid,
      skipped: !plan.createLedger,
      reason: plan.reason,
      incrementCount: plan.incrementCount,
      sendPush: plan.sendPush,
      writeInbox: plan.writeInbox,
      countAfter: count,
    });
  }
  return { count, ledgerSize: ledger.size, outcomes, pushPaused: pushPaused === true };
}

/** Live TV view model from stats+settings snapshots (no PII, no list). */
function liveOpsDisplayFromSnapshots({ stats, settings }) {
  const s = stats && typeof stats === "object" ? stats : {};
  const set = settings && typeof settings === "object" ? settings : {};
  let lastAtIso = null;
  if (typeof s.lastAtIso === "string") lastAtIso = s.lastAtIso;
  else if (s.lastAt && typeof s.lastAt.toDate === "function") {
    lastAtIso = s.lastAt.toDate().toISOString();
  }
  return buildOpsNewUsersDisplay({
    count: typeof s.count === "number" ? s.count : 0,
    lastAtIso,
    pushPaused: isOpsNewUserPushPaused(set),
  });
}

module.exports = {
  OPS_FALLBACK_NAME,
  OPS_STATUS_AWAITING_PROFILE,
  readDisplayName,
  opsCountryLabel,
  isProfileReadyForOpsNotice,
  isOpsNoticeAlreadySent,
  shouldCheckOpsNoticeOnWrite,
  SENSITIVE_KEYS,
  OPS_STATS_COLLECTION,
  OPS_STATS_DOC,
  OPS_SETTINGS_COLLECTION,
  OPS_SETTINGS_DOC,
  OPS_LEDGER_COLLECTION,
  shouldNotifyOnFirstAdultVerify,
  isOpsCountableFirstAdultVerified,
  resolveOpsAdminUid,
  readHomeCountry,
  isOpsNewUserPushPaused,
  shouldSendOpsPush,
  nextOpsNewUserCount,
  planOpsLedgerAndPush,
  simulateOpsCounterFromEvents,
  liveOpsDisplayFromSnapshots,
  buildOpsNewUserPayload,
  buildOpsInboxDoc,
  buildOpsPushCopy,
  buildOpsNewUsersDisplay,
  assertOpsPayloadSafe,
  assertDisplaySafe,
};
