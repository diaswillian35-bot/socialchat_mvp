"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const {
  shouldNotifyOnFirstAdultVerify,
  resolveOpsAdminUid,
  buildOpsNewUserPayload,
  buildOpsInboxDoc,
  buildOpsPushCopy,
  buildOpsNewUsersDisplay,
  assertOpsPayloadSafe,
  assertDisplaySafe,
  shouldSendOpsPush,
  isOpsNewUserPushPaused,
  nextOpsNewUserCount,
  planOpsLedgerAndPush,
  simulateOpsCounterFromEvents,
  liveOpsDisplayFromSnapshots,
  OPS_LEDGER_COLLECTION,
  OPS_STATS_COLLECTION,
  OPS_STATS_DOC,
} = require("./ops_new_user_notify_logic");

test("notify only on first adult verify", () => {
  assert.equal(shouldNotifyOnFirstAdultVerify("", true), true);
  assert.equal(shouldNotifyOnFirstAdultVerify(undefined, true), true);
  assert.equal(shouldNotifyOnFirstAdultVerify("verified", true), false);
  assert.equal(shouldNotifyOnFirstAdultVerify("rejected", true), false);
  assert.equal(shouldNotifyOnFirstAdultVerify("", false), false);
});

test("isOpsCountableFirstAdultVerified matches hook durable outcome", () => {
  const { isOpsCountableFirstAdultVerified } = require("./ops_new_user_notify_logic");
  assert.equal(
    isOpsCountableFirstAdultVerified({
      ageVerificationStatus: "verified",
      ageVerifiedAt: "x",
    }),
    true,
  );
  assert.equal(
    isOpsCountableFirstAdultVerified({ ageVerificationStatus: "verified" }),
    false,
  );
  assert.equal(
    isOpsCountableFirstAdultVerified({
      ageVerificationStatus: "rejected",
      ageVerifiedAt: null,
    }),
    false,
  );
  // Equivalence: notify gate for first transition vs durable snapshot
  assert.equal(shouldNotifyOnFirstAdultVerify("", true), true);
  assert.equal(shouldNotifyOnFirstAdultVerify("verified", true), false);
});

test("resolveOpsAdminUid: env wins; else single isOwner; never isMaster", () => {
  assert.equal(
    resolveOpsAdminUid({
      envUid: "willian-uid",
      adminDocs: [{ uid: "other", data: { isOwner: true } }],
    }),
    "willian-uid",
  );
  assert.equal(
    resolveOpsAdminUid({
      adminDocs: [{ uid: "w1", data: { isOwner: true, isActive: true } }],
    }),
    "w1",
  );
  assert.equal(
    resolveOpsAdminUid({
      adminDocs: [
        { uid: "a", data: { isOwner: true } },
        { uid: "b", data: { isOwner: true } },
      ],
    }),
    "",
  );
  assert.equal(
    resolveOpsAdminUid({
      adminDocs: [{ uid: "m", data: { isMaster: true } }],
    }),
    "",
  );
});

test("pause/resume: push gated; counter independent", () => {
  assert.equal(isOpsNewUserPushPaused({ pushPaused: true }), true);
  assert.equal(shouldSendOpsPush({ pushPaused: true }), false);
  assert.equal(shouldSendOpsPush({ pushPaused: false }), true);
  assert.equal(shouldSendOpsPush({}), true);
  assert.equal(nextOpsNewUserCount(0), 1);
  assert.equal(nextOpsNewUserCount(41), 42);
  // Pause does not change counter math
  assert.equal(nextOpsNewUserCount(10), 11);
});

test("canonical counter advances 1, 2, 3… from zero", () => {
  let n = 0;
  n = nextOpsNewUserCount(n);
  assert.equal(n, 1);
  n = nextOpsNewUserCount(n);
  assert.equal(n, 2);
  n = nextOpsNewUserCount(n);
  assert.equal(n, 3);
  assert.equal(nextOpsNewUserCount(undefined), 1);
  assert.equal(nextOpsNewUserCount(null), 1);
  assert.equal(nextOpsNewUserCount(-5), 1);
});

test("no push replay on duplicate first-verify semantics", () => {
  // Re-verify after already verified must not notify again
  assert.equal(shouldNotifyOnFirstAdultVerify("verified", true), false);
});

test("payload and display have no PII", () => {
  const p = buildOpsNewUserPayload({
    newUid: "user123",
    country: "br",
    createdAtIso: "2026-09-14T12:00:00.000Z",
  });
  assert.equal(assertOpsPayloadSafe(p).ok, true);
  assert.equal(assertOpsPayloadSafe({ ...p, email: "x@y.com" }).ok, false);
  const push = buildOpsPushCopy(p);
  assert.equal(assertOpsPayloadSafe(push).ok, true);
  const inbox = buildOpsInboxDoc(p);
  assert.doesNotMatch(inbox.body, /user123/);
  assert.match(inbox.body, /Novo usuário · País: Brasil/);
  const display = buildOpsNewUsersDisplay({
    count: 7,
    lastAtIso: "2026-09-14T12:00:00.000Z",
    pushPaused: true,
  });
  assert.equal(display.label, "Novos usuários");
  assert.equal(display.count, 7);
  assert.equal(display.pushPaused, true);
  assert.equal(assertDisplaySafe(display).ok, true);
  assert.equal(
    assertDisplaySafe({ ...display, email: "a@b.com" }).ok,
    false,
  );
});

test("regional new_user_push remains unwired; ops hooked in age verify", () => {
  const index = fs.readFileSync("index.js", "utf8");
  assert.doesNotMatch(index, /new_user_push_logic/);
  const age = fs.readFileSync("age_verification.js", "utf8");
  assert.match(age, /notifyOpsAdminOfNewVerifiedUser/);
  assert.doesNotMatch(age, /new_user_push/);
  const notify = fs.readFileSync("ops_new_user_notify.js", "utf8");
  assert.match(notify, /FieldValue\.increment\(1\)/);
  assert.match(notify, /push_paused/);
  assert.match(notify, /systemInbox/);
});

test("owner-only pause callable exported", () => {
  const index = fs.readFileSync("index.js", "utf8");
  assert.match(index, /setOpsNewUserPushPaused/);
  assert.match(index, /getOpsNewUserStats/);
  const admin = fs.readFileSync("ops_new_user_admin.js", "utf8");
  assert.match(admin, /isOwner !== true/);
  // Persist only ops settings — no ledger replay / no avalanche on resume.
  assert.match(admin, /OPS_SETTINGS_COLLECTION/);
  assert.doesNotMatch(admin, /OPS_LEDGER_COLLECTION|opsNewUserNotices/);
  assert.doesNotMatch(admin, /sendEachForMulticast|messaging\(\)/);
});

test("pause does not gate manual Admin avisos", () => {
  const notice = fs.readFileSync("send_admin_system_notice.js", "utf8");
  assert.doesNotMatch(notice, /pushPaused|adminOpsSettings|newUserNotify/);
  const notify = fs.readFileSync("ops_new_user_notify.js", "utf8");
  // Skipped-while-paused entries are finalized; resume does not re-scan ledger.
  assert.match(notify, /reason: "push_paused"/);
  assert.match(notify, /status: "sent"/);
});

test("ops screen authorization: owner only", () => {
  const { canViewOpsNewUsersScreen } = require("./ops_new_users_screen_auth");
  assert.equal(canViewOpsNewUsersScreen({ isOwner: true, isActive: true }), true);
  assert.equal(canViewOpsNewUsersScreen({ isOwner: false, isActive: true }), false);
  assert.equal(canViewOpsNewUsersScreen({ isOwner: true, isActive: false }), false);
  assert.equal(canViewOpsNewUsersScreen(null), false);
});

test("live display label has no PII fields", () => {
  const display = buildOpsNewUsersDisplay({
    count: 3,
    lastAtIso: "2026-09-14T12:00:00.000Z",
    pushPaused: false,
  });
  assert.equal(display.label, "Novos usuários");
  assert.equal(display.count, 3);
  assert.ok(display.lastUpdatedAt);
  assert.equal("email" in display, false);
  assert.equal("uid" in display, false);
  assert.equal("users" in display, false);
});

test("firestore rules allow owner live read of ops stats/settings", () => {
  const rules = fs.readFileSync("../firestore.rules", "utf8");
  assert.match(rules, /match \/adminOpsStats\/\{docId\}/);
  assert.match(rules, /match \/adminOpsSettings\/\{docId\}/);
  assert.match(rules, /allow read: if isOwnerPortalAdmin\(\)/);
});

test("canonical source: ledger create increments; FCM not required", () => {
  assert.equal(OPS_LEDGER_COLLECTION, "opsNewUserNotices");
  assert.equal(OPS_STATS_COLLECTION, "adminOpsStats");
  assert.equal(OPS_STATS_DOC, "newUsers");

  const first = planOpsLedgerAndPush({ ledgerExists: false, pushPaused: false });
  assert.equal(first.createLedger, true);
  assert.equal(first.incrementCount, true);
  assert.equal(first.sendPush, true);
  assert.equal(first.writeInbox, true);

  // Pause: still increment + inbox; no push
  const paused = planOpsLedgerAndPush({ ledgerExists: false, pushPaused: true });
  assert.equal(paused.incrementCount, true);
  assert.equal(paused.writeInbox, true);
  assert.equal(paused.sendPush, false);
  assert.equal(paused.reason, "counted_inbox_push_paused");

  // Reprocess same uid: no second increment, no push replay
  const dup = planOpsLedgerAndPush({ ledgerExists: true, pushPaused: false });
  assert.equal(dup.incrementCount, false);
  assert.equal(dup.sendPush, false);
  assert.equal(dup.reason, "duplicate");
});

test("idempotency: reprocess same uid does not double-count", () => {
  const sim = simulateOpsCounterFromEvents(
    [
      { uid: "u1", priorStatus: "", newlyAdultVerified: true },
      { uid: "u1", priorStatus: "verified", newlyAdultVerified: true },
      { uid: "u1", priorStatus: "", newlyAdultVerified: true }, // would notify but ledger exists
    ],
    { pushPaused: false },
  );
  assert.equal(sim.count, 1);
  assert.equal(sim.ledgerSize, 1);
  assert.equal(sim.outcomes.filter((o) => o.incrementCount).length, 1);
  assert.equal(sim.outcomes.filter((o) => o.sendPush).length, 1);
});

test("pause/resume: counter advances during pause; resume does not replay", () => {
  const duringPause = simulateOpsCounterFromEvents(
    [
      { uid: "a", priorStatus: "", newlyAdultVerified: true },
      { uid: "b", priorStatus: "", newlyAdultVerified: true },
    ],
    { pushPaused: true },
  );
  assert.equal(duringPause.count, 2);
  assert.equal(duringPause.outcomes.every((o) => o.sendPush === false), true);
  assert.equal(duringPause.outcomes.every((o) => o.writeInbox === true), true);
  assert.equal(duringPause.outcomes.every((o) => o.incrementCount === true), true);

  // Resume does not replay skipped pushes for existing ledger rows
  const replayBlocked = planOpsLedgerAndPush({
    ledgerExists: true,
    pushPaused: false,
  });
  assert.equal(replayBlocked.sendPush, false);
  assert.equal(replayBlocked.incrementCount, false);
  assert.equal(replayBlocked.reason, "duplicate");

  // Only brand-new ledger creates get push after resume
  const freshAfterResume = planOpsLedgerAndPush({
    ledgerExists: false,
    pushPaused: false,
  });
  assert.equal(freshAfterResume.sendPush, true);
  assert.equal(freshAfterResume.incrementCount, true);
});

test("live update display from snapshots has no list/PII", () => {
  const d1 = liveOpsDisplayFromSnapshots({
    stats: { count: 18, lastAtIso: "2026-09-15T01:55:46.000Z" },
    settings: { pushPaused: false },
  });
  assert.equal(d1.count, 18);
  assert.equal(d1.label, "Novos usuários");
  assert.ok(d1.lastUpdatedAt);
  assert.equal(d1.pushPaused, false);
  assert.equal(assertDisplaySafe(d1).ok, true);

  const d2 = liveOpsDisplayFromSnapshots({
    stats: { count: 19, lastAtIso: "2026-09-15T02:00:00.000Z" },
    settings: { pushPaused: true },
  });
  assert.equal(d2.count, 19);
  assert.equal(d2.pushPaused, true);
  // No user list / PII keys
  assert.equal("users" in d2, false);
  assert.equal("items" in d2, false);
  assert.equal("email" in d2, false);
});

test("runtime notify path wires ledger-before-push and pause skip", () => {
  const notify = fs.readFileSync("ops_new_user_notify.js", "utf8");
  assert.match(notify, /opsNewUserNotices|OPS_LEDGER_COLLECTION/);
  assert.match(notify, /if \(snap\.exists\)/);
  assert.match(notify, /FieldValue\.increment\(1\)/);
  assert.match(notify, /reason: "push_paused"/);
  // Push only after ledger create path
  const ledgerIdx = notify.indexOf("tx.create(ledgerRef");
  const pushIdx = notify.indexOf("sendEachForMulticast");
  assert.ok(ledgerIdx > 0 && pushIdx > ledgerIdx);
});

const L = require("./ops_new_user_notify_logic");

test("aviso: nome com fallback e país legível", () => {
  assert.equal(L.readDisplayName({ name: " Ana " }), "Ana");
  assert.equal(L.readDisplayName({ displayName: "Bia" }), "Bia");
  assert.equal(L.readDisplayName({ username: "caio" }), "caio");
  assert.equal(L.readDisplayName({ email: "dani.souza@x.com" }), "dani.souza");
  assert.equal(L.readDisplayName({ email: "11987654321@x.com" }), "Novo usuário");
  assert.equal(L.readDisplayName({}), "Novo usuário");
  assert.equal(L.opsCountryLabel("br", ""), "Brasil");
  assert.equal(L.opsCountryLabel("ca", "Canada"), "Canada");
  assert.equal(L.opsCountryLabel("zz", ""), "ZZ");
  assert.equal(L.opsCountryLabel("", ""), "não informado");
  const p = L.buildOpsNewUserPayload({ newUid: "u1", country: "br", displayName: "Ana", createdAtIso: "2026-11-01T12:00:00.000Z" });
  assert.equal(L.assertOpsPayloadSafe(p).ok, true);
  assert.equal(L.buildOpsInboxDoc(p).body, "Ana · País: Brasil");
  assert.equal(L.buildOpsPushCopy(p).body, "Ana · País: Brasil");
  assert.equal(L.assertOpsPayloadSafe(L.buildOpsPushCopy(p)).ok, true);
});

test("aviso: só com nome E homeCountryCode; só na transição", () => {
  assert.equal(L.isProfileReadyForOpsNotice({ name: "Ana", homeCountryCode: "" }), false);
  assert.equal(L.isProfileReadyForOpsNotice({ name: "", homeCountryCode: "br" }), false);
  assert.equal(L.isProfileReadyForOpsNotice({ name: "Ana", homeCountryCode: "br" }), true);
  const ready = { name: "Ana", homeCountryCode: "br" };
  assert.equal(L.shouldCheckOpsNoticeOnWrite({ name: "Ana" }, ready), true);
  assert.equal(L.shouldCheckOpsNoticeOnWrite(null, ready), true);
  assert.equal(L.shouldCheckOpsNoticeOnWrite(ready, { ...ready, lastSeenAt: 1 }), false);
  assert.equal(L.shouldCheckOpsNoticeOnWrite({ name: "Ana" }, { name: "Ana" }), false);
  assert.equal(L.shouldCheckOpsNoticeOnWrite(ready, null), false);
});

test("aviso: registros antigos contam como já enviados", () => {
  assert.equal(L.isOpsNoticeAlreadySent({ status: "sent" }), true);
  assert.equal(L.isOpsNoticeAlreadySent({ status: "pending" }), true);
  assert.equal(L.isOpsNoticeAlreadySent({ status: "reconciled_backfill" }), true);
  assert.equal(L.isOpsNoticeAlreadySent({ status: "counted_no_admin" }), true);
  assert.equal(L.isOpsNoticeAlreadySent(null), true);
  assert.equal(L.isOpsNoticeAlreadySent({ status: "awaiting_profile", noticeSentAt: 1 }), true);
  assert.equal(L.isOpsNoticeAlreadySent({ status: "awaiting_profile" }), false);
});
