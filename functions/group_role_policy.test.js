"use strict";
const test = require("node:test"), assert = require("node:assert/strict");
const {roleOf, permissionError, accountDeletionGroupPatch} = require("./group_role_policy");
const group = {ownerId:"owner", admins:["owner","admin","admin2"], moderators:["mod","mod2"], members:["owner","admin","admin2","mod","mod2","member","member2"]};
const roles = ["owner","admin","mod","member","outsider"];
for (const actor of roles) for (const target of roles) for (const action of ["promote","demote","remove","ban"]) {
  test(`${actor} -> ${target}: ${action}`, () => {
    const expected = target !== "owner" && actor !== target && (
      actor === "owner" || ((action === "remove" || action === "ban") &&
      (actor === "admin" && target !== "admin" || actor === "mod" && target === "member")));
    assert.equal(permissionError(group,actor,target === "owner" ? target : target+"2",action) === null, expected);
  });
}
test("owner wins even if absent from role/member lists", () => {
  const g={ownerId:"owner",admins:[],members:[]};
  assert.equal(roleOf(g,"owner"),"owner");
  for(const action of ["promote","demote","remove","ban"]) assert.equal(permissionError(g,"admin","owner",action),"group_owner_protected");
});
test("no platform-admin or forged roles-map override", () => {
  const g={...group, roles:{outsider:"owner"}, superAdmins:["outsider"]};
  assert.equal(permissionError(g,"outsider","member","ban"),"group_role_not_allowed");
});
test("legacy mods are recognized below admins", () => {
  const g={...group,moderators:[],mods:["mod"]};
  assert.equal(roleOf(g,"mod"),"moderator");
  assert.equal(permissionError(g,"mod","admin","ban"),"group_admin_protected");
});
test("unknown actions fail closed",()=>assert.ok(permissionError(group,"owner","member","change-owner")));
test("account deletion closes owned group without owner/member/role transfer", () => {
  const patch=accountDeletionGroupPatch(group,"owner");
  assert.equal(patch.deleted,true); assert.equal(patch.isActive,false);
  for(const key of ["ownerId","members","admins","moderators"]) assert.equal(key in patch,false);
});
for(const uid of ["admin","mod","member"]) test(`account deletion removes only ${uid}`,()=>{
  const patch=accountDeletionGroupPatch(group,uid);
  assert.ok(!patch.members.includes(uid)); assert.ok(patch.members.includes("owner"));
  assert.ok(patch.admins.includes("owner")); assert.equal("ownerId" in patch,false);
});

for(const actor of roles) for(const action of ["promote","demote","remove","ban"]) test(`self ${actor}: ${action}`,()=>assert.ok(permissionError(group,actor,actor,action)));
