"use strict";
// Requires the isolated demo emulators. Never points at a real Firebase project.
const test=require("node:test"), assert=require("node:assert/strict"), fs=require("node:fs"), vm=require("node:vm");
const project="demo-group-owner-protection";
if(process.env.FIRESTORE_EMULATOR_HOST!=="127.0.0.1:18080" || process.env.GCLOUD_PROJECT!==project) throw Error("Refusing non-demo environment");
const admin=require("firebase-admin");
const functions=require("./index");
const db=admin.firestore();
const {HttpsError}=require("firebase-functions/v2/https");
const {uidList}=require("./group_role_policy");
const uid=(name)=>"roles-e2e-"+name;
const now=Math.floor(Date.now()/1000);
function token(name,claims={}) { const enc=v=>Buffer.from(JSON.stringify(v)).toString("base64url"); return enc({alg:"none",typ:"JWT"})+"."+enc({iss:`https://securetoken.google.com/${project}`,aud:project,auth_time:now,iat:now,exp:now+3600,sub:uid(name),user_id:uid(name),firebase:{identities:{},sign_in_provider:"custom"},...claims})+"."; }
async function call(name,actor,data,expectedKey=null,claims={}) {
  console.log("CALL (exported callable .run, NOT HTTP)",name,actor);
  let body;
  try {
    const result=await functions[name].run({auth:{uid:uid(actor),token:{...claims}},data});
    body={result};
  } catch(error) {
    body={error:{details:error.details,status:error.code.toUpperCase().replaceAll("-","_"),message:error.message}};
  }
  if(expectedKey) { assert.ok(body.error,`${name} unexpectedly allowed: ${JSON.stringify(body)}`); assert.equal(body.error.details?.localizationKey || body.error.status,expectedKey,JSON.stringify(body)); }
  else { assert.equal(body.error,undefined,JSON.stringify(body)); assert.ok(body.result && (body.result.success || body.result.joined || body.result.alreadyMember),JSON.stringify(body)); }
  return body.result;
}
let groupId;
async function groupData(){ return (await db.doc(`groups/${groupId}`).get()).data(); }
async function seed(name) {await db.doc(`users/${uid(name)}`).set({name,ageVerificationStatus:"verified",isBanned:false,isActive:true,countryCode:"CA",homeCountryCode:"CA",country:"Canada"});}
async function direct(actor,path,fields,method="PATCH",claims={}) {
 const query=method==="PATCH" ? "?"+Object.keys(fields).map(k=>"updateMask.fieldPaths="+encodeURIComponent(k)).join("&") : "";
 const response=await fetch(`http://127.0.0.1:18080/v1/projects/${project}/databases/(default)/documents/${path}${query}`,{method,headers:{"Content-Type":"application/json",Authorization:"Bearer "+token(actor,claims)},...(method==="DELETE"?{}:{body:JSON.stringify({fields})})});
 return response;
}
function baseline(name) {
 const code=fs.readFileSync(`../docs/group-owner-protection/${name}.deployed.js.txt`,"utf8");
 const context={exports:{},onCall:(_,handler)=>handler,socialOnCall:(_,handler)=>handler,HttpsError,admin,asUidList:uidList,isGroupOwnerOrAdminData:(g,id)=>g.ownerId===id||uidList(g.admins).includes(id),console:{log(){},error(){}}};
 new Function(...Object.keys(context), code)(...Object.values(context));return context.exports[name];
}
test("group roles: live-source reproduction, exported callables + real Firestore/rules integration (NO HTTP)",async(t)=>{
 for(const name of ["owner","A","B","mod","member","outsider","joiner"]) await seed(name);
 await t.test("create as owner through exported callable",async()=>{
 const result=await call("createGroup","owner",{requestId:"roles_e2e_"+Date.now(),name:"Local role policy test",bio:"Local only",scope:"country",country:"Canada",countryCode:"CA",joinPolicy:"open"});groupId=result.groupId; assert.equal((await groupData()).ownerId,uid("owner"));
 });
 for(const name of ["A","B","mod","member"]) await t.test("join open "+name,async()=>call("joinOpenGroup",name,{groupId}));
 for(const name of ["A","B"]) await t.test("owner promotes "+name,async()=>call("promoteGroupAdmin","owner",{groupId,targetUid:uid(name)}));
 await t.test("deployed source: admin cannot ban/remove/demote owner",async()=>{
 for(const name of ["banGroupMember","removeGroupMember","demoteGroupAdmin"]) await assert.rejects(baseline(name)({auth:{uid:uid("A")},data:{groupId,targetUid:uid("owner")}}));
 });
 await t.test("deployed source BUG: admin A can ban admin B",async()=>{
 await baseline("banGroupMember")({auth:{uid:uid("A")},data:{groupId,targetUid:uid("B")}});
 const g=await groupData(); assert.ok(!g.members.includes(uid("B"))); assert.ok(!g.admins.includes(uid("B")));
 await db.doc(`groups/${groupId}/bannedUsers/${uid("B")}`).set({isActive:false},{merge:true});
 await call("joinOpenGroup","B",{groupId});await call("promoteGroupAdmin","owner",{groupId,targetUid:uid("B")});
 });
 await t.test("deployed source indirect BUG: transfer then new owner can remove creator",async()=>{
 await baseline("transferGroupOwnership")({auth:{uid:uid("owner")},data:{groupId,newOwnerUid:uid("B")}});
 await baseline("removeGroupMember")({auth:{uid:uid("B")},data:{groupId,targetUid:uid("owner")}});
 assert.ok(!(await groupData()).members.includes(uid("owner")));
 await db.doc(`groups/${groupId}`).set({ownerId:uid("owner"),members:[uid("owner"),uid("A"),uid("B"),uid("mod"),uid("member")],admins:[uid("owner"),uid("A"),uid("B")],membersCount:5},{merge:true});
 });
 for(const target of ["owner","B"]) for(const fn of ["removeGroupMember","banGroupMember","demoteGroupAdmin"]) await t.test(`fixed A cannot ${fn} ${target}`,async()=>{
 const before=await groupData();await call(fn,"A",{groupId,targetUid:uid(target)},target==="owner"?"group_owner_protected":"group_admin_protected");assert.deepEqual(await groupData(),before);
 });
 for(const fn of ["removeGroupMember","banGroupMember","demoteGroupAdmin"]) await t.test("no superadmin override "+fn,async()=>call(fn,"outsider",{groupId,targetUid:uid("owner")},"group_owner_protected",{superAdmin:true,admin:true}));
 await t.test("owner may demote and remove admin A",async()=>{await call("demoteGroupAdmin","owner",{groupId,targetUid:uid("A")});await call("promoteGroupAdmin","owner",{groupId,targetUid:uid("A")});await call("removeGroupMember","owner",{groupId,targetUid:uid("A")});assert.ok(!(await groupData()).members.includes(uid("A")));});
 await t.test("owner promotes moderator",async()=>{await call("promoteGroupAdmin","owner",{groupId,targetUid:uid("mod"),role:"moderator"});assert.ok((await groupData()).moderators.includes(uid("mod")));});
 for(const target of ["owner","B"]) for(const fn of ["removeGroupMember","banGroupMember","demoteGroupAdmin"]) await t.test(`mod cannot ${fn} ${target}`,async()=>call(fn,"mod",{groupId,targetUid:uid(target)},target==="owner"?"group_owner_protected":"group_admin_protected"));
 await t.test("moderator can remove regular member",async()=>call("removeGroupMember","mod",{groupId,targetUid:uid("member")}));
 await t.test("owner cannot transfer or leave",async()=>{await call("transferGroupOwnership","owner",{groupId,newOwnerUid:uid("B")},"group_owner_transfer_disabled");await call("leaveGroup","owner",{groupId},"group_owner_cannot_leave");});
 await t.test("admin and superadmin cannot delete group",async()=>{for(const actor of ["B","outsider"])await call("deleteGroup",actor,{groupId},"PERMISSION_DENIED",{superAdmin:true});});
 await t.test("settings reject forged ownership/role fields",async()=>{for(const key of ["ownerId","admins","members","moderators","mods","roles"])await call("updateGroupSettings","owner",{groupId,changes:{[key]:key==="ownerId"?uid("B"):[]}},"INVALID_ARGUMENT");});
 await t.test("bio editing regression",async()=>{await call("updateGroupSettings","B",{groupId,changes:{bio:"Bio local atualizada"}});assert.equal((await groupData()).bio,"Bio local atualizada");});
 await t.test("invite regression",async()=>{await call("updateGroupSettings","owner",{groupId,changes:{joinPolicy:"inviteOnly"}});const g=await groupData();await call("joinGroupByInviteCode","member",{inviteCode:g.inviteCode});});
 await t.test("approval adds member without changing roles",async()=>{
 await call("updateGroupSettings","owner",{groupId,changes:{joinPolicy:"approval"}});
 await db.doc(`groups/${groupId}/pendingRequests/${uid("joiner")}`).set({uid:uid("joiner"),status:"pending"});
 const before=await groupData();await call("approveGroupJoinRequest","B",{groupId,requestUid:uid("joiner")});const after=await groupData();assert.deepEqual(after.admins,before.admins);assert.deepEqual(after.moderators,before.moderators);assert.equal(after.ownerId,before.ownerId);assert.ok(after.members.includes(uid("joiner")));
 });
 // REST exercises the actual Firestore rules engine (no rules-unit-testing install).
 await db.doc(`admins/${uid("outsider")}`).set({role:"super_admin",isActive:true,permissions:{groups:true}});
 await t.test("rules positive control: signed-in read works",async()=>{
 const r=await fetch(`http://127.0.0.1:18080/v1/projects/${project}/databases/(default)/documents/groups/${groupId}`,{headers:{Authorization:"Bearer "+token("member")}});assert.equal(r.status,200);
 });
 for(const actor of ["owner","B","mod","member","outsider"]) {
  for(const [key,value] of Object.entries({ownerId:{stringValue:uid("B")},admins:{arrayValue:{values:[]}},members:{arrayValue:{values:[]}},moderators:{arrayValue:{values:[]}},roles:{mapValue:{fields:{}}}})) await t.test(`rules deny ${actor} direct ${key}`,async()=>assert.equal((await direct(actor,`groups/${groupId}`,{[key]:value},"PATCH",{admin:true,superAdmin:true})).status,403));
  for(const sub of ["members","roles","bannedUsers"]) await t.test(`rules deny ${actor} ${sub} owner write`,async()=>assert.equal((await direct(actor,`groups/${groupId}/${sub}/${uid("owner")}`,{isActive:{booleanValue:true}})).status,403));
  await t.test(`rules deny ${actor} root delete`,async()=>assert.equal((await direct(actor,`groups/${groupId}`,{},"DELETE")).status,403));
 }
 await t.test("rules deny self-approved request",async()=>assert.equal((await direct("member",`groups/${groupId}/pendingRequests/${uid("member")}`,{uid:{stringValue:uid("member")},status:{stringValue:"approved"}})).status,403));
 await t.test("member leaves without touching owner",async()=>{await call("leaveGroup","member",{groupId});assert.equal((await groupData()).ownerId,uid("owner"));});
 await t.test("owner may ban admin B, admin may remove moderator",async()=>{
 await call("banGroupMember","owner",{groupId,targetUid:uid("B")});assert.ok(!(await groupData()).admins.includes(uid("B")));
 await call("unbanGroupMember","owner",{groupId,targetUid:uid("B")});
 await call("updateGroupSettings","owner",{groupId,changes:{joinPolicy:"open"}});
 await call("joinOpenGroup","B",{groupId});await call("promoteGroupAdmin","owner",{groupId,targetUid:uid("B")});
 await call("removeGroupMember","B",{groupId,targetUid:uid("mod")});assert.ok(!(await groupData()).moderators.includes(uid("mod")));
 });
 await t.test("legacy mod outside members may leave without retaining privileges",async()=>{
 await db.doc(`groups/${groupId}`).set({mods:[uid("mod")]},{merge:true});
 await call("leaveGroup","mod",{groupId});assert.ok(!(await groupData()).mods.includes(uid("mod")));
 });
 await t.test("account-deletion group cleanup preserves owner and closes group",async()=>{
 const before=await groupData();
 const {_processGroupsForTest}=require("./delete_my_account");
 const count=await _processGroupsForTest(db,uid("owner"),{deleteMedia:async()=>true});
 assert.ok(count>=1);const after=await groupData();assert.equal(after.deleted,true);assert.equal(after.ownerId,before.ownerId);assert.deepEqual(after.members,before.members);assert.deepEqual(after.admins,before.admins);
 });
 console.log("Integration groupId (DEMO ONLY):",groupId);
 await admin.app().delete();
});
