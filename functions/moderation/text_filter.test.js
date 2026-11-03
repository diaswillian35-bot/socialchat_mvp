const test = require("node:test");
const assert = require("node:assert/strict");
const { evaluateText, safeChatPreview } = require("./text_filter");

test("falsos positivos passam", () => {
  for (const sample of [
    "vou matar a fome",
    "sexta-feira",
    "Essex",
    "documento.pdf",
    "privacy policy do app",
    "sexualidade na escola",
    "batom nude",
    "odeio pedofilia, tem que denunciar",
    "violer la loi",
    "this will kill you",
  ]) {
    assert.equal(evaluateText(sample, {}), null, sample);
  }
});

test("leetspeak e letras separadas entram no filtro", () => {
  assert.equal(evaluateText("p0rn", {}).reason, "text_adult");
  assert.equal(evaluateText("0nlyfans", {}).reason, "text_adult");
  assert.equal(evaluateText("x v i d e o s", {}).reason, "text_adult");
});

test("casos positivos: link, texto adulto e csam", () => {
  assert.equal(evaluateText("onlyfans.com/x", {}).reason, "link_adult");
  assert.equal(evaluateText("https://www.pornhub.com/view", {}).reason, "link_adult");
  assert.equal(evaluateText("entra no onlyfans ponto com/x", {}).reason, "link_adult");
  assert.equal(evaluateText("only fans . com", {}).reason, "link_adult");
  assert.equal(evaluateText("vendo nudes", {}).reason, "text_adult");
  assert.equal(evaluateText("isso é pornografia", {}).reason, "text_adult");
  assert.equal(evaluateText("vou te matar", {}).reason, "text_adult");
  assert.equal(evaluateText("pornografia infantil", {}).reason, "csam");
  assert.equal(evaluateText("child porn", {}).reason, "csam");
});

test("domínio extra da config entra sem deploy", () => {
  assert.equal(
    evaluateText("veja exemplo.com/a", { blockedDomains: ["exemplo.com"] }).reason,
    "link_adult",
  );
});

test("preview não devolve o texto bloqueado", () => {
  assert.equal(safeChatPreview("onlyfans.com/x", { enabled: true }), "");
  assert.equal(safeChatPreview("vou matar a fome", { enabled: true }), "vou matar a fome");
  assert.equal(safeChatPreview("onlyfans.com/x", { enabled: false }), "onlyfans.com/x");
});
