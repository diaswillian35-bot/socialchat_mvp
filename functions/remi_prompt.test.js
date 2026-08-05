/**
 * Prompt Remi — tamanho, modelo, max tokens, idiomas.
 * Executar: node remi_prompt.test.js
 */
const assert = require("assert");
const {
  REMI_MODEL,
  REMI_MAX_OUTPUT_TOKENS,
  buildRemiSystemPrompt,
  estimateApproxTokens,
} = require("./remi_prompt");

assert.strictEqual(REMI_MODEL, "gemini-2.5-flash");
assert.strictEqual(REMI_MAX_OUTPUT_TOKENS, 300);

const prompt = buildRemiSystemPrompt({
  memoryText: "User memory:\n- Learning language: English",
  language: "English",
  languageCode: "en",
  uiLanguageCode: "pt",
  goal: "Travel",
  lesson: "Coffee Shop",
  showPronunciation: false,
  history: "User: Hi\nRemi: Hello!",
  text: "Can I get a coffee?",
});

// Versão média: bem menor que o prompt antigo (~3500+ chars estáticos).
assert.ok(prompt.length < 2800, `prompt too large: ${prompt.length}`);
assert.ok(prompt.length > 800, `prompt too small: ${prompt.length}`);
assert.ok(prompt.includes("Remi"));
assert.ok(prompt.includes("Target language code: en"));
assert.ok(prompt.includes("UI / explanation language code: pt"));
assert.ok(prompt.includes("Never end mid-sentence"));
assert.ok(!prompt.includes("uóts iór nêim")); // exemplo longo removido
assert.ok(!prompt.includes("Good afternoon. May I see your passport?"));

const approx = estimateApproxTokens(prompt);
assert.ok(approx > 200 && approx < 900);

const withPron = buildRemiSystemPrompt({
  memoryText: "",
  language: "French",
  languageCode: "fr",
  uiLanguageCode: "en",
  goal: "Friends",
  lesson: "Meeting People",
  showPronunciation: true,
  history: "",
  text: "Bonjour",
});
assert.ok(withPron.includes("Pronunciation mode ON"));
assert.ok(withPron.includes("Target language code: fr"));

console.log("remi_prompt.test.js: all tests passed", {
  promptChars: prompt.length,
  approxInputTokens: approx,
  maxOutputTokens: REMI_MAX_OUTPUT_TOKENS,
  model: REMI_MODEL,
});
