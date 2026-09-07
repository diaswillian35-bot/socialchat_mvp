"use strict";

const assert = require("assert");
const {
  shouldNotifyJoinRequest,
  resolveJoinRequestAdminUids,
  formatJoinRequestPushCopy,
} = require("./group_join_request_push_logic");

function pass(name) {
  console.log(`PASS ${name}`);
}

function main() {
  assert.strictEqual(shouldNotifyJoinRequest(null, { status: "pending" }), true);
  assert.strictEqual(shouldNotifyJoinRequest(undefined, { status: "pending" }), true);
  assert.strictEqual(shouldNotifyJoinRequest(null, { status: "approved" }), false);
  assert.strictEqual(
    shouldNotifyJoinRequest({ status: "rejected" }, { status: "pending" }),
    true,
  );
  assert.strictEqual(
    shouldNotifyJoinRequest({ status: "approved" }, { status: "pending" }),
    true,
  );
  assert.strictEqual(
    shouldNotifyJoinRequest({ status: "pending" }, { status: "pending" }),
    false,
  );
  assert.strictEqual(
    shouldNotifyJoinRequest({ status: "pending" }, { status: "rejected" }),
    false,
  );
  pass("shouldNotifyJoinRequest create + re-request vs no-op");

  assert.deepStrictEqual(
    resolveJoinRequestAdminUids(
      { admins: ["admin1", "admin2", "req"], ownerId: "owner1" },
      "req",
    ),
    ["admin1", "admin2", "owner1"],
  );
  assert.deepStrictEqual(
    resolveJoinRequestAdminUids({ admins: ["req"], ownerId: "req" }, "req"),
    [],
  );
  assert.deepStrictEqual(
    resolveJoinRequestAdminUids({ admins: [], ownerId: "owner1" }, "req"),
    ["owner1"],
  );
  pass("resolveJoinRequestAdminUids excludes requester, includes owner");

  assert.deepStrictEqual(formatJoinRequestPushCopy("Willian Dias", "teste grupo"), {
    title: "Nova solicitação",
    body: "Willian Dias solicitou entrada no grupo teste grupo.",
  });
  assert.strictEqual(
    formatJoinRequestPushCopy("", "").title,
    "Nova solicitação",
  );
  assert.ok(
    formatJoinRequestPushCopy("", "").body.includes("solicitou entrada no grupo"),
  );
  assert.ok(!formatJoinRequestPushCopy("A", "B").body.includes("pediu"));
  assert.ok(!formatJoinRequestPushCopy("A", "B").body.includes("quer entrar"));
  pass("formatJoinRequestPushCopy Nova solicitação / solicitou entrada");

  console.log("All group_join_request_push_logic tests passed");
}

main();
