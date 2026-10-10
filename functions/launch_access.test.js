"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {
  freeLaunchActive,
  premiumGrantsEnabled,
  premiumGrantDeniedBody,
} = require("./launch_access");
const invite = require("./invite_premium");

const denied = {
  success: false,
  available: false,
  granted: false,
  applied: false,
  rewardGranted: false,
};

test("free launch keeps premium grants off behind one switch", () => {
  assert.equal(freeLaunchActive, true);
  assert.equal(premiumGrantsEnabled(), false);
  assert.deepEqual(premiumGrantDeniedBody(), denied);
  const source = fs.readFileSync(
    path.join(__dirname, "launch_access.js"),
    "utf8"
  );
  assert.match(source, /const freeLaunchActive = true/);
});

test("direct claimInvitePremiumReward does not grant", async () => {
  const result = await invite._claimInvitePremiumRewardHandler({
    auth: { uid: "direct-call-user" },
    data: {},
  });
  assert.deepEqual(result, denied);
  assert.equal("premiumUntil" in result, false);
  assert.equal("invitesCount" in result, false);
  assert.equal("isPremium" in result, false);
});

test("direct applyInviteCode does not grant a reward", async () => {
  const result = await invite._applyInviteCodeHandler({
    auth: { uid: "direct-call-user" },
    data: { inviteCode: "SHOULD-NOT-BE-LOOKED-UP" },
  });
  assert.deepEqual(result, denied);
  assert.equal("invitesCount" in result, false);
  assert.equal("rewardDays" in result, false);
});

test("no other function grants an invite reward; store sync stays separate", () => {
  const rewardPatterns = [
    /premiumUntil:\s*admin\.firestore\.Timestamp/,
    /rewardDays/,
    /inviteRewardLevel/,
  ];
  const storeFile = fs.readFileSync(
    path.join(__dirname, "revenuecat_webhook.js"),
    "utf8"
  );
  assert.match(storeFile, /isPremium:\s*true/);
  assert.doesNotMatch(storeFile, /premiumGrantsEnabled\(\)/);
  assert.doesNotMatch(storeFile, /premiumUntil:\s*admin\.firestore\.Timestamp/);

  const rewardWriters = [];
  for (const name of fs.readdirSync(__dirname)) {
    if (!name.endsWith(".js") || name.endsWith(".test.js")) continue;
    const full = path.join(__dirname, name);
    if (!fs.statSync(full).isFile()) continue;
    const source = fs.readFileSync(full, "utf8");
    const grantsReward =
      /premiumUntil:\s*admin\.firestore\.Timestamp/.test(source) &&
      /buildInviteRewardPatch|rewardDays/.test(source);
    if (!grantsReward) continue;
    rewardWriters.push(name);
    assert.match(source, /if \(!premiumGrantsEnabled\(\)\)/, name);
    assert.ok(rewardPatterns.every((pattern) => pattern.test(source)), name);
  }

  assert.deepEqual(rewardWriters, ["invite_premium.js"]);

  const scripts = fs.readdirSync(path.join(__dirname, "scripts"));
  for (const name of scripts) {
    if (!name.endsWith(".js")) continue;
    const source = fs.readFileSync(path.join(__dirname, "scripts", name), "utf8");
    assert.doesNotMatch(
      source,
      /premiumUntil:\s*admin\.firestore\.Timestamp/,
      name
    );
    assert.doesNotMatch(source, /exports\.\w+\s*=\s*onCall/, name);
  }
});
