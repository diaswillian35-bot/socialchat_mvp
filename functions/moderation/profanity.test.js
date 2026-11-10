const test = require("node:test");
const assert = require("node:assert/strict");
const { evaluateProfanity, profanityOpts, LISTS, prepare } = require("./profanity");

const MUST_BLOCK = [
  "seu idiota", "SEU IDIOTA!!!", "vai tomar no cu", "vai tomar no cuuuu", "f.d.p", "F D P",
  "vtnc", "vsf mano", "sua vagabunda", "seu macaco", "filho da puta", "filha da puta não",
  "otário", "0tári0", "arrombado", "cuzão", "babaca", "corno manso",
  "cabrão", "paneleiro", "vai-te foder", "vai para o caralho", "atrasado mental", "seu anormal",
  "bitch", "b1tch", "fuck you", "f u c k you", "asshole", "go fuck yourself", "son of a bitch", "you retard", "kys",
  "hijo de puta", "pendejo", "gilipollas", "vete a la mierda", "chinga tu madre", "maricón",
  "fils de pute", "connard", "salope", "enculé", "nique ta mère", "va te faire foutre", "sale con",
];
const LOOSE_ONLY = ["porra", "que merda", "caralho!", "puta que pariu", "foda-se", "fuck", "shit", "mierda", "joder", "putain", "merde", "p o r r a"];

test("insultos sempre bloqueados (5 idiomas, leet, repetição, f.d.p)", () => {
  for (const s of MUST_BLOCK) assert.deepEqual(evaluateProfanity(s), { reason: "insult" }, s);
});

test("palavrão solto: só bloqueia com o filtro ligado", () => {
  for (const s of LOOSE_ONLY) {
    assert.equal(evaluateProfanity(s), null, `livre: ${s}`);
    assert.deepEqual(evaluateProfanity(s, { loose: true }), { reason: "profanity" }, `ligado: ${s}`);
  }
});

test("falsos positivos não são bloqueados (nem com o filtro de palavrão)", () => {
  const extra = [
    "Vamos ao computador da disputa", "Moro em Cuiabá", "Pacuí é longe", "Scunthorpe United",
    "Bitche fica na França", "pau-brasil", "café negro", "o veado correu", "fila da bicha",
    "macaco no zoológico", "piranha é um peixe", "ele pede ajuda", "je suis en retard",
    "el cono de helado", "a reunião é às 19:30", "custa R$ 10,50", "2024 foi bom", "classic cocktail",
    "Dickens", "Shiitake", "putz", "Sussex", "Essex", "therapist", "grape", "pedestre", "pedido", "cuco",
    "con plaisir", "contre", "conte", "Concha y Toro", "la zorra corre en el bosque", "zorro",
  ];
  for (const s of [...LISTS.mustNotBlock, ...extra]) {
    assert.equal(evaluateProfanity(s), null, s);
    assert.equal(evaluateProfanity(s, { loose: true }), null, `loose: ${s}`);
  }
});

test("lista tem as duas seções nos 5 idiomas", () => {
  for (const sec of ["insults", "loose"]) {
    for (const lang of ["pt-BR", "pt-PT", "en", "es", "fr"]) {
      assert.ok(Array.isArray(LISTS[sec][lang]) && LISTS[sec][lang].length > 0, `${sec}/${lang}`);
    }
  }
});

test("profanityLevel: off desliga, strict liga palavrão em todo lugar", () => {
  assert.equal(profanityOpts({ profanityLevel: "off" }, true), null);
  assert.deepEqual(profanityOpts({}, false), { loose: false });
  assert.deepEqual(profanityOpts({}, true), { loose: true });
  assert.deepEqual(profanityOpts({ profanityLevel: "strict" }, false), { loose: true });
});

test("prepare não estraga números", () => {
  assert.equal(prepare("2024 10 13"), "2024 10 13");
});

test("parity_cases.json (lido pelo app) está atualizado", () => {
  const { cases } = require("./parity_cases");
  const saved = JSON.parse(require("fs").readFileSync(require("path").join(__dirname, "parity_cases.json"), "utf8"));
  assert.deepEqual(saved, cases(), "rode: node functions/moderation/parity_cases.js");
});
