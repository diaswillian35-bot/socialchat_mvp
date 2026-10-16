"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const {
  buildDmUnreadUpdatePairs,
  confirmDmUnreadAfterCommit,
  commitDmUnreadOnce,
  initialNestedUnread,
  simulateOncePerMessageUnread,
} = require("./private_message_unread_logic");

test("dm unread steps nest the counter and delete the literal key", () => {
  const steps = buildDmUnreadUpdatePairs({
    senderId: "sender",
    targetUids: ["sender", "peer", ""],
  });
  assert.deepEqual(
    steps.map((step) => step.op),
    [
      "zero",
      "deleteLiteral",
      "deleteLiteral",
      "increment",
      "deleteLiteral",
      "deleteLiteral",
    ],
  );
  assert.equal(steps[0].uid, "sender");
  assert.equal(steps[1].literalKey, "unread.sender");
  assert.equal(steps[2].literalKey, "unread. sender");
  assert.equal(steps[3].uid, "peer");
  assert.equal(steps[4].literalKey, "unread.peer");
  assert.equal(steps[5].literalKey, "unread. peer");
  assert.equal(
    steps.some((step) => step.op === "increment" && step.uid === "sender"),
    false,
  );
});

test("a committed read of zero is not incremented again", () => {
  for (const mode of ["trigger_applied", "callable_applied", "already_processed"]) {
    const decision = confirmDmUnreadAfterCommit({ mode });
    assert.equal(decision.incrementAgain, false);
  }
  assert.equal(confirmDmUnreadAfterCommit({ mode: "trigger_applied" }).sendPush, true);
  assert.equal(confirmDmUnreadAfterCommit({ mode: "callable_applied" }).sendPush, true);
  assert.equal(confirmDmUnreadAfterCommit({ mode: "already_processed" }).sendPush, false);
});

test("the same processed DM is not incremented twice", () => {
  const once = simulateOncePerMessageUnread({
    before: { peer: 1 },
    recipientUid: "peer",
    senderUid: "sender",
    callableApplied: false,
    triggerRetry: false,
  });
  assert.equal(once.unread.peer, 2);
  assert.equal(once.unread.sender, 0);
  assert.equal(once.increments, 1);

  const retry = simulateOncePerMessageUnread({
    before: once.unread,
    recipientUid: "peer",
    senderUid: "sender",
    callableApplied: false,
    triggerRetry: true,
  });
  assert.equal(retry.unread.peer, 2);
  assert.equal(retry.increments, 0);
});

test("share and forward use one nested increment and ignore a retry", () => {
  const first = commitDmUnreadOnce({
    senderId: "sender",
    targetUids: ["sender", "peer"],
    alreadyProcessed: false,
  });
  assert.ok(first);
  assert.equal(
    first.some((step) => step.op === "increment" && step.uid === "sender"),
    false,
  );
  assert.equal(
    first.filter((step) => step.op === "increment").length,
    1,
  );
  assert.equal(commitDmUnreadOnce({
    senderId: "sender",
    targetUids: ["peer"],
    alreadyProcessed: true,
  }), null);
  assert.deepEqual(initialNestedUnread(["sender", "peer", "sender"]), {
    sender: 0,
    peer: 0,
  });
  assert.equal(Object.keys(initialNestedUnread(["a"])).some((k) => k.includes(".")), false);
});

test("share and forward sources do not create a literal unread field", () => {
  const root = __dirname;
  const share = fs.readFileSync(path.join(root, "share_extension.js"), "utf8");
  const forward = fs.readFileSync(path.join(root, "forward_message.js"), "utf8");
  const send = fs.readFileSync(path.join(root, "send_dm_message_core.js"), "utf8");
  for (const source of [share, forward, send]) {
    assert.equal(source.includes("[`unread.${"), false);
  }
  assert.equal(share.includes("appendDmUnreadArgs"), true);
  assert.equal(share.includes("buildServerUnreadApplied"), true);
  assert.equal(share.includes("buildDmUnreadUpdatePairs"), true);
  const shareDm = share.slice(share.indexOf('kind === "dm"'));
  assert.ok(shareDm.indexOf("idem.exists") < shareDm.indexOf("appendDmUnreadArgs"));
  assert.equal(forward.includes("appendDmUnreadArgs"), true);
  assert.equal(forward.includes("initialNestedUnread"), true);
  assert.equal(forward.includes("buildServerUnreadApplied"), true);
  const forwardHandler = forward.slice(forward.indexOf("const forwardMessage"));
  assert.ok(forwardHandler.indexOf("idemSnap.exists") >= 0);
  assert.ok(
    forwardHandler.indexOf("idemSnap.exists") <
      forwardHandler.indexOf("forwardToDestination"),
  );
  assert.equal(send.includes("unread"), false);
});

test("onPrivateMessageCreated does not set a dotted unread field", () => {
  const index = fs.readFileSync(path.join(__dirname, "index.js"), "utf8");
  const start = index.indexOf("exports.onPrivateMessageCreated");
  const end = index.indexOf("exports.askRemi");
  assert.ok(start >= 0 && end > start);
  const slice = index.slice(start, end);
  assert.equal(slice.includes("[`unread.${"), false);
  assert.equal(slice.includes("buildDmUnreadUpdatePairs"), true);
  assert.equal(slice.includes("appendDmUnreadArgs"), true);
  assert.equal(slice.includes("processedSnap.exists"), true);
  assert.equal(slice.includes("confirmDmUnreadAfterCommit"), true);
  assert.equal(slice.includes("buildDmLiteralDeleteSteps"), true);
  assert.equal(slice.includes("dm_unread_repair"), false);
  assert.equal(slice.includes("incrementAgain"), true);
});
