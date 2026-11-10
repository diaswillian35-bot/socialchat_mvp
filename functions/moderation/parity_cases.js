// Corpus de paridade servidor x app. Gera parity_cases.json (lido pelo teste Flutter).
const { evaluateProfanity, LISTS } = require("./profanity");
const { evaluateGroupMessage } = require("./group_bot");

const EXTRA = [
  "seu idiota", "SEU IDIOTA!!!", "vai tomar no cuuuu", "f.d.p", "F D P", "0tári0", "b1tch", "f u c k you",
  "p o r r a", "foda-se", "que merda", "Moro em Cuiabá", "computador", "je suis en retard", "ele pede ajuda",
  "me chama no (11) 98765-4321", "+55 11 98765 4321", "ligue 912 345 678", "+1 416 555 1234", "416-555-1234",
  "zap 98765-4321", "encontro dia 10/11/2026 às 19:30", "19h30 no bar", "custa R$ 1.500,00", "$1,299.99",
  "CEP 01310-100", "1000-001 Lisboa", "anos 2024 2025 2026", "2026-11-10", "12,50 €", "id 123456",
  "https://remdy.app/g/abc", "www.site.com", "veja meusite.com.br", "ana@gmail.com", "bit.ly/xyz", "t.me/grupo",
  "vou.de carro", "ok.me liga", "site.pt/abc", "loja ponto com", "sr.silva chegou", "nota 9.5", "Ça va, Zoë? Ñandú",
];

function cases() {
  const texts = new Set(EXTRA);
  for (const sec of ["insults", "loose"]) for (const l of Object.keys(LISTS[sec])) for (const t of LISTS[sec][l]) texts.add(t);
  for (const t of LISTS.mustNotBlock) texts.add(t);
  return Array.from(texts).map((text) => ({
    text,
    insultsOnly: (evaluateProfanity(text) || {}).reason || null,
    loose: (evaluateProfanity(text, { loose: true }) || {}).reason || null,
    groupDefault: (evaluateGroupMessage(text, {}, {}) || {}).reason || null,
    groupStrict: (evaluateGroupMessage(text, { modBot: { blockProfanity: true } }, {}) || {}).reason || null,
  }));
}

if (require.main === module) {
  require("fs").writeFileSync(require("path").join(__dirname, "parity_cases.json"), JSON.stringify(cases(), null, 1) + "\n");
  console.log("parity_cases.json ok");
}
module.exports = { cases };
