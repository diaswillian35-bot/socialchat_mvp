"use strict";

/**
 * One-time reconciliation helpers for ops new-user counter/ledger.
 * Pure — no Firebase I/O. Runtime script applies results.
 *
 * Count criterion = SAME as published confirmAdultAge → ops hook:
 *   isOpsCountableFirstAdultVerified (verified + ageVerifiedAt).
 *
 * Concurrency-safe apply strategy (NOT absolute set):
 *   For each missing ledger uid → transaction: create ledger + increment(1)
 *   Same shape as live notifyOpsAdminOfNewVerifiedUser.
 *   Concurrent live verifies keep their own increment; we never overwrite count.
 */

const {
  isOpsCountableFirstAdultVerified,
} = require("./ops_new_user_notify_logic");

/** @deprecated use isOpsCountableFirstAdultVerified — kept as alias for scripts */
function isAdultVerifiedUser(userData) {
  return isOpsCountableFirstAdultVerified(userData);
}

/**
 * Plan reconciliation from in-memory snapshots (tests + dry planning).
 * @param {{ uid: string, data: object }[]} users
 * @param {Set<string>|string[]} existingLedgerUids
 * @param {number|null|undefined} countBefore
 */
function planOpsNewUserReconcile(users, existingLedgerUids, countBefore) {
  const existing = existingLedgerUids instanceof Set
    ? existingLedgerUids
    : new Set(
        Array.isArray(existingLedgerUids)
          ? existingLedgerUids.map((u) => String(u || "").trim()).filter(Boolean)
          : [],
      );

  const verifiedUids = [];
  let scannedEligibleSkipped = 0;
  for (const row of users || []) {
    const uid = (row && row.uid != null ? String(row.uid) : "").trim();
    if (!uid) continue;
    if (!isOpsCountableFirstAdultVerified(row.data)) {
      scannedEligibleSkipped += 1;
      continue;
    }
    verifiedUids.push(uid);
  }
  const uniqueVerified = [...new Set(verifiedUids)].sort();

  const toCreate = [];
  const already = [];
  for (const uid of uniqueVerified) {
    if (existing.has(uid)) already.push(uid);
    else toCreate.push(uid);
  }

  const before =
    typeof countBefore === "number" && Number.isFinite(countBefore)
      ? Math.max(0, Math.floor(countBefore))
      : 0;

  return {
    criterion: "confirmAdultAge_first_adult_verify",
    criterionFields: ["ageVerificationStatus===verified", "ageVerifiedAt!=null"],
    /** Eligible population size by hook durable outcome (not forced). */
    verifiedCount: uniqueVerified.length,
    rowsNotMatchingHookCriterion: scannedEligibleSkipped,
    ledgerAlreadyExisted: already.length,
    ledgerToCreate: toCreate.length,
    countBefore: before,
    /** Projection if ONLY our creates run and count was consistent with ledger. */
    projectedCountAfterOurIncrements: before + toCreate.length,
    countDeltaFromCreates: toCreate.length,
    createUids: toCreate,
    /**
     * Apply must NEVER absolute-set count (would clobber concurrent live increments).
     * Use per-uid create + FieldValue.increment(1) only.
     */
    strategy: "per_uid_ledger_create_plus_increment",
    neverAbsoluteSet: true,
    pushSent: 0,
    inboxWritten: 0,
    pauseAffectsCount: false,
  };
}

/**
 * After N successful create+increment txs, expected count math (pure).
 * Concurrent live increments are additive and preserved (never overwritten).
 */
function projectedCountAfterSafeApply({ countBefore, createsSucceeded }) {
  const before =
    typeof countBefore === "number" && Number.isFinite(countBefore)
      ? Math.max(0, Math.floor(countBefore))
      : 0;
  const n =
    typeof createsSucceeded === "number" && Number.isFinite(createsSucceeded)
      ? Math.max(0, Math.floor(createsSucceeded))
      : 0;
  return {
    countBefore: before,
    incrementsApplied: n,
    /** Lower bound after apply; live concurrent increments may make actual higher. */
    countLowerBoundAfter: before + n,
    neverAbsoluteSet: true,
  };
}

function buildReconcileLedgerDoc({ uid, country, runId }) {
  return {
    newUid: String(uid || "").trim(),
    country: country || null,
    status: "reconciled_backfill",
    source: "one_time_reconcile",
    historicalBackfill: true,
    runId: String(runId || "").trim() || null,
    // Explicit: historical backfill never notifies anyone (users or ops admin).
    notify: {
      fcm: false,
      systemInbox: false,
      retroactive: false,
    },
    push: { sent: 0, skipped: true, reason: "reconcile_no_push" },
  };
}

/** True if ledger doc already prevents double-count / is historical backfill. */
function isHistoricalBackfillLedger(docData) {
  const d = docData && typeof docData === "object" ? docData : {};
  if (d.historicalBackfill === true) return true;
  if (d.status === "reconciled_backfill") return true;
  if (d.source === "one_time_reconcile") return true;
  return false;
}

function buildReconcileAuditDoc({
  runId,
  dryRun,
  plan,
  performedBy,
  createsSucceeded,
}) {
  const p = plan && typeof plan === "object" ? plan : {};
  const proj = projectedCountAfterSafeApply({
    countBefore: p.countBefore,
    createsSucceeded:
      typeof createsSucceeded === "number"
        ? createsSucceeded
        : dryRun
          ? 0
          : p.ledgerToCreate ?? 0,
  });
  return {
    runId: String(runId || "").trim(),
    dryRun: dryRun === true,
    criterion: p.criterion || "confirmAdultAge_first_adult_verify",
    strategy: "per_uid_ledger_create_plus_increment",
    neverAbsoluteSet: true,
    verifiedCount: p.verifiedCount ?? 0,
    ledgerAlreadyExisted: p.ledgerAlreadyExisted ?? 0,
    ledgerCreated: dryRun ? 0 : proj.incrementsApplied,
    ledgerToCreate: p.ledgerToCreate ?? 0,
    countBefore: proj.countBefore,
    countLowerBoundAfter: proj.countLowerBoundAfter,
    pushSent: 0,
    inboxWritten: 0,
    pauseAffectsCount: false,
    performedBy: String(performedBy || "ops_reconcile_script").trim(),
    note:
      "Backfill uses same create+increment as live hook. No absolute count set. No FCM, no systemInbox, no retroactive notify to users or ops admin.",
  };
}

/** Refuse second apply when a prior successful run is recorded (unless force). */
function shouldBlockReconcileApply({ priorSuccessfulRunExists, force }) {
  if (force === true) return false;
  return priorSuccessfulRunExists === true;
}

module.exports = {
  isAdultVerifiedUser,
  isOpsCountableFirstAdultVerified,
  planOpsNewUserReconcile,
  projectedCountAfterSafeApply,
  buildReconcileLedgerDoc,
  isHistoricalBackfillLedger,
  buildReconcileAuditDoc,
  shouldBlockReconcileApply,
};
