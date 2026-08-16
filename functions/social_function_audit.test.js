"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const { entries } = require("./social_function_policy");

const indexSource = fs.readFileSync("index.js", "utf8");
const exported = [...indexSource.matchAll(/^exports\.([A-Za-z0-9_]+)\s*=/gm)]
  .map((match) => match[1]);

const delegatedAdultMarkers = {
  forwardMessage: ["forward_message.js", "assertVerifiedAdult"],
  sendDmMessage: ["send_dm_message.js", "assertVerifiedAdult"],
  issueShareExtensionSession: ["share_extension.js", "assertVerifiedAdult(request"],
  listShareDestinations: ["share_extension.js", "assertVerifiedAdultUid"],
  sendShareMessage: ["share_extension.js", "assertVerifiedAdultUid"],
  claimInvitePremiumReward: ["invite_premium.js", "assertVerifiedAdult"],
  applyInviteCode: ["invite_premium.js", "assertVerifiedAdult"],
  fetchLinkPreview: ["link_preview.js", "assertVerifiedAdult"],
};

test("every deployed export has an explicit age policy and justification", () => {
  assert.deepEqual([...Object.keys(entries)].sort(), [...exported].sort());
  for (const [name, policy] of Object.entries(entries)) {
    assert.ok(policy[0] && policy[1], `${name} lacks policy/justification`);
  }
});

test("every user-initiated social callable uses the central adult guard", () => {
  for (const [name, [mode]] of Object.entries(entries)) {
    if (mode !== "adult") continue;
    const delegated = delegatedAdultMarkers[name];
    if (delegated) {
      assert.ok(fs.readFileSync(delegated[0], "utf8").includes(delegated[1]), name);
      continue;
    }
    assert.match(indexSource,
      new RegExp(`exports\\.${name}\\s*=\\s*socialOnCall\\s*\\(`), name);
  }
});

test("essential and admin exceptions remain outside the social wrapper", () => {
  for (const name of [
    "confirmAdultAge", "deleteMyAccount", "revokeShareExtensionSessions",
    "syncRevenueCatEntitlement", "reconcilePresenceCountersNow",
    "approveEventPendingChanges", "rejectEventPendingChanges",
  ]) {
    assert.doesNotMatch(indexSource,
      new RegExp(`exports\\.${name}\\s*=\\s*socialOnCall\\s*\\(`));
  }
  assert.match(indexSource, /approveEventPendingChanges[\s\S]*assertPortalEventAdmin/);
  assert.match(indexSource, /rejectEventPendingChanges[\s\S]*assertPortalEventAdmin/);
  assert.doesNotMatch(fs.readFileSync("age_verification.js", "utf8"),
    /assertVerifiedAdult/);
  assert.doesNotMatch(fs.readFileSync("delete_my_account.js", "utf8"),
    /assertVerifiedAdult/);
  assert.doesNotMatch(fs.readFileSync("share_extension.js", "utf8")
    .match(/const revokeShareExtensionSessions[\s\S]*?const listShareDestinations/)[0],
  /assertVerifiedAdult/);
});

test("automatic social push fan-out filters unverified recipients", () => {
  assert.match(indexSource,
    /function pushAllowed[\s\S]*ageVerificationStatus !== "verified"/);
});
