"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const {
  isAdultVerifiedUser,
  planOpsNewUserReconcile,
  projectedCountAfterSafeApply,
  buildReconcileLedgerDoc,
  buildReconcileAuditDoc,
  shouldBlockReconcileApply,
} = require("./ops_new_user_reconcile_logic");

test("isAdultVerifiedUser / hook criterion: verified + ageVerifiedAt only", () => {
  assert.equal(
    isAdultVerifiedUser({
      ageVerificationStatus: "verified",
      ageVerifiedAt: { seconds: 1 },
    }),
    true,
  );
  assert.equal(isAdultVerifiedUser({ ageVerificationStatus: "verified" }), false);
  assert.equal(isAdultVerifiedUser({ ageVerificationStatus: "pending" }), false);
  assert.equal(isAdultVerifiedUser({ ageVerificationStatus: "rejected" }), false);
  assert.equal(
    isAdultVerifiedUser({
      ageVerificationStatus: "Verified",
      ageVerifiedAt: { seconds: 1 },
    }),
    false,
  );
  assert.equal(
    isAdultVerifiedUser({
      ageVerificationStatus: "verified",
      ageVerifiedAt: { seconds: 1 },
      isBanned: true,
    }),
    true,
  );
});

test("plan: concurrency-safe strategy never absolute-sets count", () => {
  const users = [
    {
      uid: "a",
      data: { ageVerificationStatus: "verified", ageVerifiedAt: { s: 1 } },
    },
    {
      uid: "b",
      data: { ageVerificationStatus: "verified", ageVerifiedAt: { s: 1 } },
    },
    { uid: "c", data: { ageVerificationStatus: "pending" } },
    { uid: "d", data: { ageVerificationStatus: "verified" } },
  ];
  const plan = planOpsNewUserReconcile(users, new Set(["a"]), 18);
  assert.equal(plan.criterion, "confirmAdultAge_first_adult_verify");
  assert.equal(plan.verifiedCount, 2);
  assert.equal(plan.ledgerToCreate, 1);
  assert.deepEqual(plan.createUids, ["b"]);
  assert.equal(plan.countBefore, 18);
  assert.equal(plan.projectedCountAfterOurIncrements, 19);
  assert.equal(plan.strategy, "per_uid_ledger_create_plus_increment");
  assert.equal(plan.neverAbsoluteSet, true);
  assert.equal("setCountAbsolute" in plan, false);
});

test("projectedCountAfterSafeApply preserves concurrent headroom", () => {
  const p = projectedCountAfterSafeApply({ countBefore: 18, createsSucceeded: 1 });
  assert.equal(p.countLowerBoundAfter, 19);
  assert.equal(p.neverAbsoluteSet, true);
  // If live added 1 during reconcile, actual would be >= 20; we never clamp down.
});

test("ledger + audit docs have no PII keys and no push", () => {
  const led = buildReconcileLedgerDoc({
    uid: "u1",
    country: "BR",
    runId: "r1",
  });
  assert.equal(led.status, "reconciled_backfill");
  assert.equal(led.historicalBackfill, true);
  assert.equal(led.notify.fcm, false);
  assert.equal(led.notify.systemInbox, false);
  assert.equal(led.notify.retroactive, false);
  assert.equal(led.push.reason, "reconcile_no_push");
  assert.equal("email" in led, false);
  const { isHistoricalBackfillLedger } = require("./ops_new_user_reconcile_logic");
  assert.equal(isHistoricalBackfillLedger(led), true);
  assert.equal(isHistoricalBackfillLedger({ status: "sent" }), false);
  const audit = buildReconcileAuditDoc({
    runId: "r1",
    dryRun: true,
    plan: planOpsNewUserReconcile(
      [
        {
          uid: "u1",
          data: {
            ageVerificationStatus: "verified",
            ageVerifiedAt: { seconds: 1 },
          },
        },
      ],
      [],
      0,
    ),
    performedBy: "test",
  });
  assert.equal(audit.dryRun, true);
  assert.equal(audit.neverAbsoluteSet, true);
  assert.equal(audit.pushSent, 0);
  assert.match(audit.note, /No absolute count set|create\+increment/i);
});

test("second apply blocked unless force", () => {
  assert.equal(
    shouldBlockReconcileApply({ priorSuccessfulRunExists: true, force: false }),
    true,
  );
  assert.equal(
    shouldBlockReconcileApply({ priorSuccessfulRunExists: true, force: true }),
    false,
  );
  assert.equal(
    shouldBlockReconcileApply({ priorSuccessfulRunExists: false, force: false }),
    false,
  );
});

test("reconcile settings patch must not include pushPaused", () => {
  const fs = require("node:fs");
  const script = fs.readFileSync(
    "../deploy/admin_avisos_ops_isolated/reconcile_ops_new_users_once.js",
    "utf8",
  );
  assert.match(script, /NEVER touch pushPaused/);
  // No assignment of pushPaused in reconcile writes
  assert.doesNotMatch(script, /pushPaused\s*:/);
});
