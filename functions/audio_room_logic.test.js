"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const L = require("./audio_room_logic");

const group = { ownerId: "own", moderators: ["mod"], admins: ["adm"], members: ["own", "mod", "adm", "m1", "m2"], countryCode: "BR" };
const br = { homeCountryCode: "br" }, ca = { homeCountryCode: "ca" };

test("país: mesma regra do canAccessGroupCountry do app", () => {
  const cases = [
    ["br", "br", false, true], ["ca", "ca", false, true], ["br", "ca", false, false],
    ["ca", "br", false, false], ["", "br", false, false], ["br", "", false, false],
    ["pt", "pt", false, false], ["world", "world", false, false], [" BR ", "br", false, true],
    ["br", "ca", true, true], ["", "", true, true],
  ];
  for (const [home, target, admin, want] of cases) {
    assert.equal(L.canAccessGroupCountry(home, target, admin), want, `${home}->${target} admin=${admin}`);
  }
  assert.equal(L.userCountry({ countryCode: "CA" }), "ca");
  assert.equal(L.userCountry({ homeCountryCode: "br", countryCode: "ca" }), "br");
});

test("entrar: membro do mesmo país", () => {
  assert.equal(L.joinError({ group, user: br, uid: "m1" }), null);
  assert.equal(L.joinError({ group, user: ca, uid: "m1" }), "country_blocked");
  assert.equal(L.joinError({ group, user: {}, uid: "m1" }), "country_blocked");
  assert.equal(L.joinError({ group, user: br, uid: "x" }), "not_member");
  assert.equal(L.joinError({ group, user: br, uid: "m1", banned: true }), "banned");
  assert.equal(L.joinError({ group, user: br, uid: "" }), "unauthenticated");
  assert.equal(L.joinError({ group: null, user: br, uid: "m1" }), "group_not_found");
  assert.equal(L.joinError({ group: { ...group, deleted: true }, user: br, uid: "m1" }), "group_not_found");
  assert.equal(L.joinError({ group, user: ca, uid: "m1", isAdmin: true }), null);
  assert.equal(L.joinError({ group, user: ca, uid: "x", isAdmin: true }), "not_member");
});

test("abrir/fechar: só dono, admin do grupo e moderador", () => {
  for (const uid of ["own", "mod", "adm"]) assert.equal(L.manageError({ group, user: br, uid }), null);
  assert.equal(L.manageError({ group, user: br, uid: "m1" }), "not_moderator");
  assert.equal(L.manageError({ group, user: ca, uid: "own" }), "country_blocked");
});

test("token: ouvinte sem microfone; dono/mod e falante aprovado com microfone", () => {
  assert.equal(L.grantFor({ group, room: {}, uid: "m1" }).canPublish, true);
  assert.deepEqual(L.grantFor({ group, room: {}, uid: "m1" }).canPublishSources, ["microphone"]);
  assert.equal(L.grantFor({ group, room: { blockedUids: ["m1"] }, uid: "m1" }).canPublish, false);
  assert.deepEqual(L.grantFor({ group, room: { blockedUids: ["m1"] }, uid: "m1" }).canPublishSources, []);
  assert.equal(L.grantFor({ group, room: { blockedUids: ["mod"] }, uid: "mod" }).canPublish, true);
  assert.equal(L.grantFor({ group, room: {}, uid: "own" }).canPublish, true);
  assert.equal(L.grantFor({ group, room: {}, uid: "mod" }).canPublish, true);
  assert.equal(L.grantFor({ group, room: {}, uid: "m1" }).canSubscribe, true);
});

test("limite de 50", () => {
  assert.equal(L.MAX_PARTICIPANTS, 50);
  assert.equal(L.capacityError({ participantCount: 49 }, "m1"), null);
  assert.equal(L.capacityError({ participantCount: 50 }, "m1"), "room_full");
  assert.equal(L.capacityError({ participantCount: 50, presentUids: ["m1"] }, "m1"), null);
});

test("aprovar/revogar fala", () => {
  assert.equal(L.speakerChangeError({ group, uid: "mod", targetUid: "m1" }), null);
  assert.equal(L.speakerChangeError({ group, uid: "m2", targetUid: "m1" }), "not_moderator");
  assert.equal(L.speakerChangeError({ group, uid: "own", targetUid: "mod" }), "target_is_moderator");
  assert.equal(L.speakerChangeError({ group, uid: "own", targetUid: "x" }), "not_member");
});

test("nome da sala", () => {
  assert.equal(L.roomNameFor("abc"), "grp_abc");
  assert.equal(L.groupIdFromRoomName("grp_abc"), "abc");
  assert.equal(L.groupIdFromRoomName("other"), "");
});

test("push: só grupos liberados, opt-out por grupo e 5 línguas", () => {
  assert.equal(L.shouldSendLivePush("g1", []), false);
  assert.equal(L.shouldSendLivePush("g1", ["g1"]), true);
  assert.equal(L.audioPushMuted({ audioRoomPush: false }), true);
  assert.equal(L.audioPushMuted({}), false);
  assert.equal(L.audioPushMuted(undefined), false);
  assert.deepEqual(Object.keys(L.PUSH_TEXTS).sort(), ["en", "es", "fr", "pt-BR", "pt-PT"]);
  assert.equal(L.pushLocale({ homeCountryCode: "ca" }), "en");
  assert.equal(L.pushLocale({ homeCountryCode: "br" }), "pt-BR");
  assert.equal(L.pushLocale({ locale: "pt_PT" }), "pt-PT");
  assert.equal(L.pushLocale({ locale: "fr-CA" }), "fr");
  const t = L.livePushText("pt-BR", "Papo de Boteco", "Ana");
  assert.equal(t.title, "Papo de Boteco está ao vivo");
  assert.match(t.body, /^Ana abriu uma sala de áudio/);
});

test("sem gravação: o código nunca usa Egress", () => {
  const src = require("node:fs").readFileSync(require("node:path").join(__dirname, "audio_room.js"), "utf8");
  assert.doesNotMatch(src, /Egress/);
});

test("opção B: mensagem de sistema desligada até o 42 estar nas lojas", () => {
  assert.equal(L.AUDIO_ROOM_SYSTEM_MESSAGE_ENABLED, false);
});
