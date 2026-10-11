const test = require("node:test");
const assert = require("node:assert/strict");
const {
  applyGroupMessageUnread,
  readGroupUnreadState,
} = require("./group_unread_logic");

test("a message from someone else increments only the other members", () => {
  const applied = applyGroupMessageUnread({
    groupData: { unread: { owner: 0 } },
    senderId: "owner",
    memberUids: ["owner", "member"],
    bannedUids: [],
    alreadyProcessed: false,
  });
  assert.equal(applied.unread.owner, 0);
  assert.equal(applied.unread.member, 1);
  assert.deepEqual(applied.targets, ["member"]);
});

test("own message does not increment the sender", () => {
  const applied = applyGroupMessageUnread({
    groupData: { unread: { owner: 4, member: 1 } },
    senderId: "owner",
    memberUids: ["owner", "member"],
    bannedUids: [],
    alreadyProcessed: false,
  });
  assert.equal(applied.unread.owner, 0);
  assert.equal(applied.unread.member, 2);
});

test("retry does not increment again", () => {
  const applied = applyGroupMessageUnread({
    groupData: { unread: { member: 2 } },
    senderId: "owner",
    memberUids: ["owner", "member"],
    bannedUids: [],
    alreadyProcessed: true,
  });
  assert.equal(applied, null);
});

test("several messages accumulate and a literal dotted count is folded once", () => {
  const first = applyGroupMessageUnread({
    groupData: { "unread.member": 2, unread: { owner: 0 } },
    senderId: "owner",
    memberUids: ["owner", "member"],
    bannedUids: [],
    alreadyProcessed: false,
  });
  assert.equal(first.unread.member, 3);
  assert.deepEqual(first.literalKeys, ["unread.member"]);
  const second = applyGroupMessageUnread({
    groupData: { unread: first.unread },
    senderId: "owner",
    memberUids: ["owner", "member"],
    bannedUids: [],
    alreadyProcessed: false,
  });
  assert.equal(second.unread.member, 4);
  assert.deepEqual(second.literalKeys, []);
});

test("explicit nested zero is not replaced by a stale literal field", () => {
  const state = readGroupUnreadState({
    unread: { member: 0 },
    "unread.member": 5,
  });
  assert.equal(state.nested.member, 0);
  assert.deepEqual(state.literalKeys, ["unread.member"]);
});
