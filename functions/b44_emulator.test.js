"use strict";
// b44 (segurança): regras do Firestore/Storage + núcleos das functions no
// Firebase Emulator. Projeto demo-*, nunca aponta para produção.
// Rodar: firebase emulators:exec --config emulator_b44.json --project demo-b44-seguranca \
//   --only firestore,storage "cd functions && node --test b44_emulator.test.js"
const test = require("node:test");
const assert = require("node:assert/strict");
const project = "demo-b44-seguranca";
if (process.env.FIRESTORE_EMULATOR_HOST !== "127.0.0.1:18080" || process.env.GCLOUD_PROJECT !== project) {
  throw Error("Refusing non-demo environment");
}
process.env.FIREBASE_STORAGE_EMULATOR_HOST = process.env.FIREBASE_STORAGE_EMULATOR_HOST || "127.0.0.1:19199";
const admin = require("firebase-admin");
admin.initializeApp({ projectId: project, storageBucket: `${project}.appspot.com` });
const db = admin.firestore();
const { executeSendDmMessage } = require("./send_dm_message_core");
const { moderateCreatedMessage } = require("./moderate_message_text");
const { runImageModeration } = require("./moderate_chat_image");
const sec = require("./security_b44");
const { resetModerationConfigCache } = require("./moderation/config");
const L = require("./audio_room_logic");

const FS = `http://127.0.0.1:18080/v1/projects/${project}/databases/(default)/documents`;
const now = Math.floor(Date.now() / 1000);
function token(uid, claims = {}) {
  const enc = (v) => Buffer.from(JSON.stringify(v)).toString("base64url");
  return enc({ alg: "none", typ: "JWT" }) + "." + enc({
    iss: `https://securetoken.google.com/${project}`, aud: project, auth_time: now, iat: now, exp: now + 3600,
    sub: uid, user_id: uid, firebase: { identities: {}, sign_in_provider: "custom" }, ...claims,
  }) + ".";
}
function val(v) {
  if (v === null) return { nullValue: null };
  if (v instanceof Date) return { timestampValue: v.toISOString() };
  if (typeof v === "boolean") return { booleanValue: v };
  if (typeof v === "number") return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === "string") return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(val) } };
  return { mapValue: { fields: Object.fromEntries(Object.entries(v).map(([k, x]) => [k, val(x)])) } };
}
/** Escrita do cliente (passa pelas regras). serverTime = campos com request.time. */
async function clientWrite(uid, path, fields, { create = true, serverTime = [], claims = {}, merge = false } = {}) {
  const name = `projects/${project}/databases/(default)/documents/${path}`;
  const write = { update: { name, fields: Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, val(v)])) } };
  if (create) write.currentDocument = { exists: false };
  if (merge) write.updateMask = { fieldPaths: Object.keys(fields) };
  if (serverTime.length) write.updateTransforms = serverTime.map((f) => ({ fieldPath: f, setToServerValue: "REQUEST_TIME" }));
  const r = await fetch(`${FS}:commit`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer " + token(uid, claims) },
    body: JSON.stringify({ writes: [write] }),
  });
  return r.status;
}
async function clientGet(uid, path) {
  const r = await fetch(`${FS}/${path}`, { headers: { Authorization: "Bearer " + token(uid) } });
  return r.status;
}
const ALLOW = 200;
const DENY = 403;
const T = Date.now();
let seq = 0;
const id = (p) => `${p}_${T}_${++seq}`;

async function seedUser(uid, extra = {}) {
  await db.doc(`users/${uid}`).set({ name: uid, countryCode: "BR", homeCountryCode: "BR", ageVerificationStatus: "verified", isActive: true, ...extra });
  await db.doc(`publicUsers/${uid}`).set({ name: uid, countryCode: "BR" });
}
async function seedConv(a, b, lastMessage = "") {
  const cid = id("conv");
  await db.doc(`conversations/${cid}`).set({ participants: [a, b], lastMessage });
  return cid;
}
function dmMsg(from, to, text = "oi") {
  return { type: "text", text, senderId: from, fromUid: from, toUid: to };
}
async function sendDm(from, to, cid, claims = {}) {
  return clientWrite(from, `conversations/${cid}/messages/${id("m")}`, { ...dmMsg(from, to), createdAt: new Date() }, { claims });
}

test.before(async () => {
  await db.doc("appConfig/moderation").set({ enabled: true });
  resetModerationConfigCache();
});

// ---------------- 1. Bloquear PV: regras ----------------
test("regras: ninguém cria conversa com quem bloqueou PV (nem quem bloqueou)", async () => {
  const a = id("a"), b = id("b"), c = id("c");
  await seedUser(a); await seedUser(b, { dmBlocked: true }); await seedUser(c);
  assert.equal(await clientWrite(a, `conversations/${id("cv")}`, { participants: [a, b] }), DENY, "a -> b bloqueado");
  assert.equal(await clientWrite(b, `conversations/${id("cv")}`, { participants: [b, c] }), DENY, "b bloqueado -> c");
  assert.equal(await clientWrite(a, `conversations/${id("cv")}`, { participants: [a, c] }), ALLOW, "a -> c livre");
});

test("regras: mensagem em conversa antiga — bloqueio total, 'Manter conversas', mão dupla e admin", async () => {
  const a = id("a"), b = id("b"), k = id("k"), adm = id("adm");
  await seedUser(a); await seedUser(b, { dmBlocked: true }); await seedUser(k, { dmBlocked: true, dmAllowExisting: true }); await seedUser(adm);
  const ab = await seedConv(a, b, "oi antigo");
  assert.equal(await sendDm(a, b, ab), DENY, "para quem bloqueou");
  assert.equal(await sendDm(b, a, ab), DENY, "quem bloqueou também não manda");
  const ak = await seedConv(a, k, "oi antigo");
  assert.equal(await sendDm(a, k, ak), ALLOW, "Manter conversas: antiga com histórico continua");
  assert.equal(await sendDm(k, a, ak), ALLOW, "Manter conversas: nos dois sentidos");
  const akEmpty = await seedConv(a, k, "");
  assert.equal(await sendDm(a, k, akEmpty), DENY, "Manter conversas: conversa vazia não vale");
  const admB = await seedConv(adm, b, "oi");
  assert.equal(await sendDm(adm, b, admB, { admin: true }), DENY, "sem exceção para admin (claim)");
  const free = await seedConv(a, adm, "");
  assert.equal(await sendDm(a, adm, free), ALLOW, "sem bloqueio segue normal");
});

test("regras: dmBlocked/dmAllowExisting só bool; o próprio usuário liga/desliga", async () => {
  const a = id("a");
  await seedUser(a);
  assert.equal(await clientWrite(a, `users/${a}`, { dmBlocked: true, dmAllowExisting: false }, { create: false, merge: true }), ALLOW);
  assert.equal(await clientWrite(a, `users/${a}`, { dmBlocked: "sim" }, { create: false, merge: true }), DENY);
  assert.equal(await clientWrite(a, `publicUsers/${a}`, { dmBlocked: true }, { create: false, merge: true }), ALLOW);
  const other = id("o"); await seedUser(other);
  assert.equal(await clientWrite(a, `users/${other}`, { dmBlocked: true }, { create: false, merge: true }), DENY, "não liga no doc de outro");
});

// ---------------- 2. Selo: regras ----------------
test("regras: cliente não se autoverifica (users, publicUsers, verificationPhones)", async () => {
  const a = id("a");
  await seedUser(a);
  assert.equal(await clientWrite(a, `users/${a}`, { verification: { status: "verified" } }, { create: false, merge: true }), DENY);
  assert.equal(await clientWrite(a, `users/${a}`, { verified: true }, { create: false, merge: true }), DENY);
  assert.equal(await clientWrite(a, `publicUsers/${a}`, { verified: true }, { create: false, merge: true }), DENY);
  const n = id("n");
  assert.equal(await clientWrite(n, `publicUsers/${n}`, { name: "x", verified: true }), DENY, "create com verified");
  assert.equal(await clientWrite(n, `users/${n}`, { name: "x", verification: { status: "verified" } }), DENY, "create com verification");
  assert.equal(await clientWrite(a, `verificationPhones/abc`, { uid: a }), DENY);
  assert.equal(await clientGet(a, `verificationPhones/abc`), DENY);
  assert.equal(await clientWrite(a, `publicUsers/${a}`, { about: "oi" }, { create: false, merge: true }), ALLOW, "resto do perfil segue");
});

// ---------------- 3. Sem falar: regras ----------------
test("regras: 'sem falar' barra PV e grupo até mutedUntil; depois libera", async () => {
  const m = id("m"), x = id("x"), p = id("p");
  const until = admin.firestore.Timestamp.fromMillis(Date.now() + 3600e3);
  await seedUser(m, { moderation: { status: "muted", mutedUntil: until } });
  await seedUser(x);
  await seedUser(p, { moderation: { status: "muted", mutedUntil: admin.firestore.Timestamp.fromMillis(Date.now() - 1000) } });
  const cm = await seedConv(m, x, "oi");
  assert.equal(await sendDm(m, x, cm), DENY, "PV mudo");
  const cp = await seedConv(p, x, "oi");
  assert.equal(await sendDm(p, x, cp), ALLOW, "prazo vencido");
  const gid = id("g");
  await db.doc(`groups/${gid}`).set({ ownerId: x, admins: [x], members: [x, m, p], countryCode: "BR", deleted: false });
  const gm = { type: "text", text: "oi", senderId: m };
  assert.equal(await clientWrite(m, `groups/${gid}/messages/${id("gm")}`, gm, { serverTime: ["createdAt"] }), DENY, "grupo mudo");
  assert.equal(await clientWrite(p, `groups/${gid}/messages/${id("gm")}`, { ...gm, senderId: p }, { serverTime: ["createdAt"] }), ALLOW, "grupo prazo vencido");
});

test("regras: cliente não se passa pelo bot (senderId remdy_bot / campos bot)", async () => {
  const x = id("x"); await seedUser(x);
  const gid = id("g");
  await db.doc(`groups/${gid}`).set({ ownerId: x, admins: [x], members: [x], countryCode: "BR", deleted: false });
  assert.equal(await clientWrite(x, `groups/${gid}/messages/${id("gm")}`, { type: "text", text: "oi", senderId: "remdy_bot" }, { serverTime: ["createdAt"] }), DENY);
  assert.equal(await clientWrite(x, `groups/${gid}/messages/${id("gm")}`, { type: "text", text: "oi", senderId: x, bot: true }, { serverTime: ["createdAt"] }), DENY);
  assert.equal(await clientWrite(x, `groups/${gid}`, { modBot: { blockLinks: false } }, { create: false, merge: true }), DENY, "config do bot só via callable");
});

// ---------------- Storage rules ----------------
test("storage: quarentena ilegível e perfil só pelo dono", async () => {
  const bucket = `${project}.appspot.com`;
  const up = async (uid, path) => {
    const B = "b44bound";
    const meta = JSON.stringify({ name: path, contentType: "image/jpeg" });
    const body = Buffer.concat([
      Buffer.from(`--${B}\r\nContent-Type: application/json; charset=utf-8\r\n\r\n${meta}\r\n--${B}\r\nContent-Type: image/jpeg\r\n\r\n`),
      Buffer.from([0xff, 0xd8, 0xff, 0xd9]), Buffer.from(`\r\n--${B}--`),
    ]);
    return (await fetch(`http://127.0.0.1:19199/v0/b/${bucket}/o?name=${encodeURIComponent(path)}`, {
      method: "POST",
      headers: { Authorization: "Firebase " + token(uid), "Content-Type": `multipart/related; boundary=${B}`, "X-Goog-Upload-Protocol": "multipart" },
      body,
    })).status;
  };
  const a = id("a"), b = id("b");
  assert.equal(await up(a, `users/${a}/profile/x.jpg`), 200);
  assert.ok([401, 403].includes(await up(b, `users/${a}/profile/y.jpg`)));
  await admin.storage().bucket(bucket).file(`quarantine/users/${a}/profile/z.jpg`).save(Buffer.from([1, 2]), { contentType: "image/jpeg" });
  const r = await fetch(`http://127.0.0.1:19199/v0/b/${bucket}/o/${encodeURIComponent(`quarantine/users/${a}/profile/z.jpg`)}?alt=media`, { headers: { Authorization: "Firebase " + token(a) } });
  assert.ok([401, 403].includes(r.status), String(r.status));
});

// ---------------- Functions no emulador ----------------
async function dmCall(uid, cid, text) {
  try {
    return await executeSendDmMessage(db, uid, { conversationId: cid, text, requestId: id("req") }, { quotaConfig: { enabled: false } });
  } catch (e) {
    return { error: e.code, reason: e.details && (e.details.reason || e.details.code), message: e.message };
  }
}

test("sendDmMessage: dm-blocked, Manter conversas, sem falar e insulto", async () => {
  const a = id("a"), b = id("b"), k = id("k"), m = id("m");
  await seedUser(a); await seedUser(b, { dmBlocked: true }); await seedUser(k, { dmBlocked: true, dmAllowExisting: true });
  await seedUser(m, { moderation: { status: "muted", mutedUntil: admin.firestore.Timestamp.fromMillis(Date.now() + 3600e3) } });
  const ab = await seedConv(a, b, "oi");
  assert.equal((await dmCall(a, ab, "olá")).reason, "dm-blocked");
  assert.equal((await dmCall(b, ab, "olá")).reason, "dm-blocked", "mão dupla");
  const ak = await seedConv(a, k, "oi");
  assert.equal((await dmCall(a, ak, "olá")).ok, true, "Manter conversas");
  const akNew = await seedConv(a, k, "");
  assert.equal((await dmCall(a, akNew, "olá")).reason, "dm-blocked");
  const ma = await seedConv(m, a, "oi");
  assert.equal((await dmCall(m, ma, "olá")).reason, "muted");
  const free = await seedConv(a, m, "oi");
  assert.equal((await dmCall(a, free, "seu idiota")).reason, "insult");
});

async function groupWithMsg(text, modBot) {
  const owner = id("own"), u = id("u");
  await seedUser(owner); await seedUser(u);
  const gid = id("g");
  await db.doc(`groups/${gid}`).set({ ownerId: owner, admins: [owner], members: [owner, u], countryCode: "BR", ...(modBot ? { modBot } : {}) });
  const mid = id("gm");
  const data = { type: "text", text, senderId: u, createdAt: admin.firestore.FieldValue.serverTimestamp() };
  await db.doc(`groups/${gid}/messages/${mid}`).set(data);
  await moderateCreatedMessage("group", gid, mid, data);
  return { gid, mid, u, msg: (await db.doc(`groups/${gid}/messages/${mid}`).get()).data() };
}

test("bot do grupo: remove link e telefone, deixa remdy.app/data/preço e respeita a config", async () => {
  let r = await groupWithMsg("entra no www.meusite.com.br");
  assert.equal(r.msg.deleted, true); assert.equal(r.msg.deletedBy, "remdy_bot"); assert.equal(r.msg.text, ""); assert.equal(r.msg.moderation.reason, "bot_link");
  r = await groupWithMsg("me chama no zap (11) 98765-4321");
  assert.equal(r.msg.deleted, true); assert.equal(r.msg.moderation.reason, "bot_phone");
  const s = await db.doc(`moderationStrikes/${r.u}`).get();
  assert.equal(s.data().count, 1, "conta ponto");
  const inbox = await db.collection(`users/${r.u}/systemInbox`).get();
  assert.equal(inbox.size, 1); assert.equal(inbox.docs[0].data().key, "mod_warning_notice");
  for (const ok of ["convite: https://remdy.app/g/abc", "dia 10/11/2026 às 19:30, custa R$ 25,00", "CEP 01310-100"]) {
    r = await groupWithMsg(ok);
    assert.notEqual(r.msg.deleted, true, ok); assert.equal(r.msg.text, ok);
  }
  r = await groupWithMsg("www.meusite.com.br", { blockLinks: false });
  assert.notEqual(r.msg.deleted, true, "dono desligou o filtro de links");
  r = await groupWithMsg("que porra é essa");
  assert.notEqual(r.msg.deleted, true, "palavrão solto liberado por padrão");
  r = await groupWithMsg("que porra é essa", { blockProfanity: true });
  assert.equal(r.msg.deleted, true); assert.equal(r.msg.moderation.reason, "profanity");
  r = await groupWithMsg("seu idiota", { blockProfanity: false });
  assert.equal(r.msg.deleted, true, "insulto sempre"); assert.equal(r.msg.moderation.reason, "insult");
  const rep = await db.collection("reports").where("groupId", "==", r.gid).get();
  assert.equal(rep.size, 1, "insulto vira denúncia");
});

test("degraus: 2º ponto = 24 h, 3º = 7 dias, 4º = banimento pendente; admin perdoa", async () => {
  const a = id("a"), b = id("b");
  await seedUser(a); await seedUser(b);
  const cid = await seedConv(a, b, "oi");
  const send = async (text) => {
    const mid = id("dm");
    const data = { ...dmMsg(a, b, text), createdAt: admin.firestore.FieldValue.serverTimestamp() };
    await db.doc(`conversations/${cid}/messages/${mid}`).set(data);
    await moderateCreatedMessage("dm", cid, mid, data);
    return (await db.doc(`conversations/${cid}/messages/${mid}`).get()).data();
  };
  const m1 = await send("seu idiota");
  assert.equal(m1.text, ""); assert.equal(m1.moderation.reason, "insult");
  let u = (await db.doc(`users/${a}`).get()).data();
  assert.equal(u.moderation.status, "warned");
  await send("vai se foder");
  u = (await db.doc(`users/${a}`).get()).data();
  assert.equal(u.moderation.status, "muted"); assert.equal(u.moderation.level, 2);
  const h = (u.moderation.mutedUntil.toMillis() - Date.now()) / 3600e3;
  assert.ok(h > 23.5 && h <= 24.01, String(h));
  await send("babaca");
  u = (await db.doc(`users/${a}`).get()).data();
  const d = (u.moderation.mutedUntil.toMillis() - Date.now()) / 86400e3;
  assert.equal(u.moderation.level, 3); assert.ok(d > 6.9 && d <= 7.01, String(d));
  await send("otário");
  u = (await db.doc(`users/${a}`).get()).data();
  assert.equal(u.moderation.status, "suspended_pending_review");
  assert.equal(u.isBanned, undefined, "banimento só com o admin");
  const keys = (await db.collection(`users/${a}/systemInbox`).get()).docs.map((x) => x.data().key).sort();
  assert.deepEqual(keys, ["mod_banned_notice", "mod_muted_notice", "mod_muted_notice", "mod_warning_notice"]);
  await sec.adjustModerationCore(db, a, "forgive", { by: "admin1" });
  u = (await db.doc(`users/${a}`).get()).data();
  assert.equal(u.moderation.status, "ok"); assert.equal(u.moderation.mutedUntil, undefined);
  assert.equal((await db.doc(`moderationStrikes/${a}`).get()).data().count, 0);
  await sec.adjustModerationCore(db, a, "confirm_ban", { by: "admin1" });
  u = (await db.doc(`users/${a}`).get()).data();
  assert.equal(u.isBanned, true); assert.equal(u.moderation.status, "banned");
});

test("boas-vindas do bot: só para quem entrou, com as regras do grupo; desligável", async () => {
  const gid = id("g"), owner = id("own"), n1 = id("n");
  const before = { ownerId: owner, members: [owner] };
  const after = { ownerId: owner, members: [owner, n1], modBot: { rules: "Sem spam. Respeito sempre." } };
  await db.doc(`groups/${gid}`).set(after);
  assert.deepEqual(await sec.welcomeNewMembersCore(db, gid, before, after), { sent: 1 });
  const w = (await db.doc(`groups/${gid}/messages/bot_welcome_${n1}`).get()).data();
  assert.equal(w.type, "bot_welcome"); assert.equal(w.botFor, n1); assert.equal(w.senderId, "remdy_bot"); assert.equal(w.text, "Sem spam. Respeito sempre.");
  const off = { ...after, members: [owner, n1, "x2"], modBot: { welcomeEnabled: false } };
  assert.deepEqual(await sec.welcomeNewMembersCore(db, gid, after, off), { sent: 0 });
});

test("config do bot: só dono/admin do grupo, valida campos e texto", async () => {
  const gid = id("g"), owner = id("own"), adm = id("adm"), mem = id("mem");
  await db.doc(`groups/${gid}`).set({ ownerId: owner, admins: [owner, adm], members: [owner, adm, mem] });
  await assert.rejects(sec.updateGroupModBotCore(db, { uid: mem, token: {} }, gid, { blockLinks: false }), /not_group_admin/);
  const r = await sec.updateGroupModBotCore(db, { uid: adm, token: {} }, gid, { blockLinks: false, rules: "Sem spam" });
  assert.equal(r.modBot.blockLinks, false); assert.equal(r.modBot.blockPhones, true);
  await assert.rejects(sec.updateGroupModBotCore(db, { uid: owner, token: {} }, gid, { blockLinks: "não" }), /invalid/);
  await assert.rejects(sec.updateGroupModBotCore(db, { uid: owner, token: {} }, gid, { rules: "seu idiota" }), /content_filter_blocked/);
  const g = (await db.doc(`groups/${gid}`).get()).data();
  assert.equal(g.modBot.rules, "Sem spam"); assert.equal(g.modBot.updatedBy, adm);
});

test("selo: telefone do Auth, um número por conta, revogar libera", async () => {
  const a = id("a"), b = id("b");
  await seedUser(a); await seedUser(b);
  const phone = "+5511987654321";
  assert.deepEqual(await sec.markPhoneVerifiedCore(db, a, { phoneNumber: phone, pepper: "t" }), { verified: true });
  assert.equal((await db.doc(`publicUsers/${a}`).get()).data().verified, true);
  assert.equal((await db.doc(`users/${a}`).get()).data().verification.status, "verified");
  await assert.rejects(sec.markPhoneVerifiedCore(db, b, { phoneNumber: phone, pepper: "t" }), /phone_in_use/);
  await assert.rejects(sec.markPhoneVerifiedCore(db, b, { phoneNumber: "", pepper: "t" }), /no_phone/);
  await sec.revokeVerificationCore(db, a, { by: "admin1", reason: "teste" });
  assert.equal((await db.doc(`publicUsers/${a}`).get()).data().verified, false);
  assert.deepEqual(await sec.markPhoneVerifiedCore(db, b, { phoneNumber: phone, pepper: "t" }), { verified: true }, "número liberado");
  await assert.rejects(sec.markPhoneVerifiedCore(db, a, { phoneNumber: "", pepper: "t" }), /no_phone/);
  const banned = id("ban"); await seedUser(banned, { isBanned: true });
  await assert.rejects(sec.markPhoneVerifiedCore(db, banned, { phoneNumber: "+351912345678", pepper: "t" }), /not_allowed/);
});

test("filtro de fotos: perfil bloqueado sai do perfil, vai para quarentena, ponto e aviso", async () => {
  const a = id("a");
  const path = `users/${a}/profile/p.jpg`;
  const url = `https://firebasestorage.googleapis.com/v0/b/x/o/${encodeURIComponent(path)}?alt=media`;
  await seedUser(a, { photoUrl: url, gallery: [url, "https://x/o/other.jpg"] });
  await db.doc(`publicUsers/${a}`).set({ photoUrl: url }, { merge: true });
  const moved = [];
  const r = await runImageModeration({ name: path, contentType: "image/jpeg", bucket: "b" }, {
    db, bucketName: "b", loadConfig: async () => ({ enabled: true }),
    annotate: async () => ({ adult: "VERY_LIKELY", racy: "LIKELY" }),
    moveToQuarantine: async (p) => moved.push(p),
  });
  assert.equal(r.status, "blocked"); assert.equal(r.kind, "profile");
  assert.deepEqual(moved, [path]);
  const u = (await db.doc(`users/${a}`).get()).data();
  assert.equal(u.photoUrl, ""); assert.deepEqual(u.gallery, ["https://x/o/other.jpg"]);
  assert.equal((await db.doc(`publicUsers/${a}`).get()).data().photoUrl, "");
  assert.equal((await db.doc(`moderationStrikes/${a}`).get()).data().count, 1);
  const keys = (await db.collection(`users/${a}/systemInbox`).get()).docs.map((x) => x.data().key).sort();
  assert.deepEqual(keys, ["mod_warning_notice", "photo_blocked_notice"]);
});

test("filtro de fotos: evento em revisão vira denúncia e a foto fica; grupo/local bloqueados limpam o campo", async () => {
  const e = id("ev"), g = id("g"), p = id("pl"), owner = id("own");
  await seedUser(owner);
  const mk = (path) => `https://firebasestorage.googleapis.com/v0/b/x/o/${encodeURIComponent(path)}?alt=media`;
  await db.doc(`events/${e}`).set({ ownerId: owner, coverUrl: mk(`events/${e}/photos/c.jpg`) });
  await db.doc(`groups/${g}`).set({ ownerId: owner, avatarUrl: mk(`groups/${g}/avatar/a.jpg`) });
  await db.doc(`places/${p}`).set({ photoUrls: [mk(`places/${p}/photos/f.jpg`)], moderationStatus: "approved" });
  const deps = (ann) => ({ db, bucketName: "b", loadConfig: async () => ({ enabled: true }), annotate: async () => ann, moveToQuarantine: async () => {} });
  const rev = await runImageModeration({ name: `events/${e}/photos/c.jpg`, contentType: "image/jpeg" }, deps({ adult: "UNLIKELY", racy: "LIKELY" }));
  assert.equal(rev.status, "review");
  assert.notEqual((await db.doc(`events/${e}`).get()).data().coverUrl, "");
  const gr = await runImageModeration({ name: `groups/${g}/avatar/a.jpg`, contentType: "image/jpeg" }, deps({ adult: "LIKELY" }));
  assert.equal(gr.status, "blocked");
  assert.equal((await db.doc(`groups/${g}`).get()).data().avatarUrl, "");
  const ownerInbox = (await db.collection(`users/${owner}/systemInbox`).get()).docs.map((x) => x.data().key);
  assert.ok(ownerInbox.includes("photo_blocked_notice"), "dono do grupo avisado");
  const pl = await runImageModeration({ name: `places/${p}/photos/f.jpg`, contentType: "image/jpeg" }, deps({ adult: "VERY_LIKELY" }));
  assert.equal(pl.status, "blocked");
  const pd = (await db.doc(`places/${p}`).get()).data();
  assert.deepEqual(pd.photoUrls, []); assert.equal(pd.moderationStatus, "review");
});

test("sala de áudio: 'sem falar' entra só para ouvir (inclusive dono)", () => {
  const group = { ownerId: "o", admins: ["o"], members: ["o", "u"] };
  assert.equal(L.grantFor({ group, room: {}, uid: "u" }).canPublish, true);
  const g1 = L.grantFor({ group, room: {}, uid: "u", muted: true });
  assert.equal(g1.canPublish, false); assert.equal(g1.canPublishData, false); assert.equal(g1.canSubscribe, true);
  assert.equal(L.grantFor({ group, room: {}, uid: "o", muted: true }).canPublish, false);
});
