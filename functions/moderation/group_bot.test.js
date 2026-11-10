const test = require("node:test");
const assert = require("node:assert/strict");
const b = require("./group_bot");

const PHONES = [
  "me chama no (11) 98765-4321", "+55 11 98765 4321", "11987654321", "ligue 912 345 678",
  "+351 912 345 678", "+1 416 555 1234", "416-555-1234", "(416) 555-1234", "zap 98765-4321",
  "whats 9 8765 4321", "+44 20 7946 0958",
];
const NOT_PHONES = [
  "encontro dia 10/11/2026 às 19:30", "19h30 no bar", "custa R$ 1.500,00", "$1,299.99",
  "CEP 01310-100", "1000-001 Lisboa", "anos 2024 2025 2026", "2026-11-10", "nota 9.5",
  "12,50 €", "1 500 €", "id 123456", "M5V 2T6 Toronto", "das 9h às 18h", "10/11 19:58",
  "3 de dezembro de 2026", "R$ 25 mil", "07/12/2026 20:00", "sala 1203 andar 12",
];
test("telefones BR/PT/CA/internacional são pegos", () => {
  for (const s of PHONES) assert.equal(b.hasPhone(s), true, s);
});
test("datas, horas, preços e CEPs não são telefone", () => {
  for (const s of NOT_PHONES) assert.equal(b.hasPhone(s), false, s);
});

const LINKS = ["https://site.com", "www.site.com.br", "veja meusite.com.br", "bit.ly/abc", "t.me/grupo",
  "wa.me/5511987654321", "chat.whatsapp.com/XYZ", "ana@gmail.com", "loja ponto com", "site.pt/abc"];
const NOT_LINKS = ["https://remdy.app/g/abc", "remdy.app", "www.remdy.app/e/1", "convite.remdy.app",
  "sr.silva chegou", "ok... vamos", "vou.de carro", "ok.me liga", "nota 9.5", "fim.Vamos", "e.g. isso"];
test("links bloqueados (menos remdy.app)", () => {
  for (const s of LINKS) assert.equal(b.hasBlockedLink(s), true, s);
  for (const s of NOT_LINKS) assert.equal(b.hasBlockedLink(s), false, s);
});

test("config padrão recomendada e por grupo", () => {
  assert.deepEqual(b.botConfig({}), { welcomeEnabled: true, rules: "", blockLinks: true, blockPhones: true, blockProfanity: false });
  const g = { modBot: { blockLinks: false, blockPhones: false, blockProfanity: true } };
  assert.equal(b.evaluateGroupMessage("www.site.com", g, {}), null);
  assert.equal(b.evaluateGroupMessage("(11) 98765-4321", g, {}), null);
  assert.deepEqual(b.evaluateGroupMessage("que porra", g, {}), { reason: "profanity" });
  assert.equal(b.evaluateGroupMessage("que porra", {}, {}), null);
  assert.deepEqual(b.evaluateGroupMessage("seu idiota", { modBot: { blockProfanity: false } }, {}), { reason: "insult" });
  assert.deepEqual(b.evaluateGroupMessage("www.site.com", {}, {}), { reason: "bot_link" });
  assert.deepEqual(b.evaluateGroupMessage("zap 98765-4321", {}, {}), { reason: "bot_phone" });
  assert.equal(b.evaluateGroupMessage("seu idiota", {}, { profanityLevel: "off" }), null);
});

test("sanitizeBotChanges só aceita os campos e tipos certos", () => {
  assert.deepEqual(b.sanitizeBotChanges({ welcomeEnabled: false, rules: "  Sem spam  " }), { welcomeEnabled: false, rules: "Sem spam" });
  assert.throws(() => b.sanitizeBotChanges({ welcomeEnabled: "sim" }));
  assert.throws(() => b.sanitizeBotChanges({ ownerId: "x" }));
  assert.throws(() => b.sanitizeBotChanges({ rules: "x".repeat(601) }));
  assert.throws(() => b.sanitizeBotChanges({}));
});
