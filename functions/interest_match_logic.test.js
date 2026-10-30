const test = require("node:test");
const assert = require("node:assert");
const L = require("./interest_match_logic");

const V = { ageVerificationStatus: "verified", profileComplete: true, nearbyEnabled: true, homeCountryCode: "br", cityName: "Campo Mourão" };

test("20 chaves, sanitize e comum", () => {
  assert.strictEqual(L.KEYS.length, 21);
  assert.strictEqual(L.formatPush("br", "Ana", ["cars"]).body, "Conheça Ana: também curte carros");
  assert.deepStrictEqual(L.sanitizeInterests(["hiking", "x", "music", "music"]), ["music", "hiking"]);
  assert.deepStrictEqual(L.commonInterests(["music", "hiking", "art"], ["art", "music"]), ["music", "art"]);
});

test("dispara quando interesses mudam ou perfil fica completo", () => {
  assert.ok(L.shouldTrigger({ interests: ["music"] }, { interests: ["music", "art"] }));
  assert.ok(!L.shouldTrigger({ interests: ["music"], profileComplete: true }, { interests: ["music"], profileComplete: true }));
  assert.ok(L.shouldTrigger({ interests: ["music"] }, { interests: ["music"], profileComplete: true }));
  assert.ok(!L.shouldTrigger(null, { interests: [] }));
});

test("texto nos 5 idiomas, neutro", () => {
  assert.strictEqual(L.formatPush("br", "Ana", ["music", "hiking"]).body, "Conheça Ana: também curte música e trilha");
  assert.strictEqual(L.formatPush("pt", "Ana", ["hiking"]).body, "Conheça Ana: também gosta de caminhadas");
  assert.strictEqual(L.formatPush("en", "Ana", ["music", "hiking"]).body, "Meet Ana: also into music and hiking");
  assert.strictEqual(L.formatPush("es", "Ana", ["music"]).body, "Conoce a Ana: también le gusta música");
  assert.strictEqual(L.formatPush("fr", "Ana", ["music", "beach"]).body, "Découvrez Ana : aime aussi musique et plage");
  assert.strictEqual(L.langOf({ appLanguageCode: "pt_PT" }), "pt");
  assert.strictEqual(L.langOf({ appLanguageCode: "pt_BR" }), "br");
  assert.strictEqual(L.langOf({ appLanguageCode: "fr" }), "fr");
  assert.strictEqual(L.langOf({}), "br");
});

test("filtros: mín. 2 iguais, Só explorar, oculto, switch, bloqueio, país; cidade, depois estado; fan-out", () => {
  const MH = ["music", "hiking"];
  const subject = { ...V, stateName: "Paraná", interests: ["music", "hiking", "art"] };
  const cands = [
    { uid: "other_state", data: { ...V, cityName: "Rio", stateName: "RJ", interests: MH } },
    { uid: "same_state", data: { ...V, cityName: "Maringá", stateName: "Paraná", interests: MH } },
    { uid: "ok_city", data: { ...V, stateName: "Paraná", interests: MH } },
    { uid: "only_one", data: { ...V, interests: ["music"] } },
    { uid: "explore", data: { ...V, exploreOnly: true, interests: MH } },
    { uid: "hidden", data: { ...V, nearbyEnabled: false, interests: MH } },
    { uid: "off", data: { ...V, interestPushEnabled: false, interests: MH } },
    { uid: "blk", data: { ...V, blocked: ["s"], interests: MH } },
    { uid: "ca", data: { ...V, homeCountryCode: "ca", interests: MH } },
    { uid: "s", data: subject },
  ];
  const r = L.pickRecipients({ subjectUid: "s", subject, candidates: cands });
  assert.deepStrictEqual(r.map((x) => x.uid), ["ok_city", "same_state", "other_state"]);
  assert.strictEqual(L.MIN_SHARED_FOR_PUSH, 2);
  const many = Array.from({ length: 50 }, (_, i) => ({ uid: "u" + String(i).padStart(2, "0"), data: { ...V, interests: MH } }));
  assert.strictEqual(L.pickRecipients({ subjectUid: "s", subject, candidates: many }).length, L.MAX_RECIPIENTS_PER_TRIGGER);
  assert.ok(!L.isVisibleActive({ ...subject, exploreOnly: true }));
  assert.ok(!L.isVisibleActive({ ...subject, nearbyEnabled: false }));
  assert.deepStrictEqual(
    L.pickRecipients({ subjectUid: "s", subject: { ...subject, blocked: ["ok_city"] }, candidates: cands }).map((x) => x.uid),
    ["same_state", "other_state"]);
});

test("1 por dia por destinatário", () => {
  const now = Date.now();
  const d = { ...V };
  assert.ok(L.canReceive(d, now, undefined));
  assert.ok(!L.canReceive(d, now, now - 60 * 60 * 1000));
  assert.ok(L.canReceive(d, now, now - L.COOLDOWN_MS - 1));
  assert.ok(!L.canReceive({ ...d, interestPushEnabled: false }, now, undefined));
});
