const test = require("node:test");
const assert = require("node:assert/strict");
const { sanitizeModerationLog } = require("./safe_log");

test("log só fica com ids e a decisão", () => {
  const line = sanitizeModerationLog("moderate_image", {
    uid: "user_1",
    messageId: "m1",
    conversationId: "c1",
    decision: "blocked",
    reason: "image_adult",
    pathHash: "abc",
    text: "mensagem privada",
    imageUrl: "https://cdn.example/a.jpg",
    email: "a@b.com",
    token: "sekret",
  });
  const encoded = JSON.stringify(line);
  assert.equal(line.uid, "user_1");
  assert.equal(line.decision, "blocked");
  assert.equal(encoded.includes("mensagem privada"), false);
  assert.equal(encoded.includes("https://"), false);
  assert.equal(encoded.includes("a@b.com"), false);
  assert.equal(encoded.includes("sekret"), false);
  assert.equal(encoded.includes("imageUrl"), false);
});
