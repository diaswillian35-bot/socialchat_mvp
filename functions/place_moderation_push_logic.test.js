const test = require("node:test");
const assert = require("node:assert");
const L = require("./place_moderation_push_logic");
const S = require("./place_submission_logic");

test("só notifica na transição pendente → aprovado/recusado", () => {
  assert.strictEqual(L.moderationOutcome({ moderationStatus: "pending" }, { moderationStatus: "published" }), "approved");
  assert.strictEqual(L.moderationOutcome({ moderationStatus: "pending" }, { moderationStatus: "rejected" }), "rejected");
  assert.strictEqual(L.moderationOutcome({ moderationStatus: "published" }, { moderationStatus: "published" }), null);
  assert.strictEqual(L.moderationOutcome({ moderationStatus: "pending" }, { moderationStatus: "pending" }), null);
});

test("texto nos 5 idiomas, com motivo na recusa", () => {
  assert.strictEqual(L.formatModerationPush("br", "approved", "Bar X").body, "Bar X foi aprovado e já aparece em Locais.");
  assert.strictEqual(L.formatModerationPush("br", "rejected", "Bar X", "Faltam fotos").body, "Bar X não foi aprovado. Motivo: Faltam fotos");
  assert.strictEqual(L.formatModerationPush("en", "rejected", "Bar X", "No photos").body, "Bar X was not approved. Reason: No photos");
  assert.strictEqual(L.formatModerationPush("es", "approved", "Bar X").title, "Lugar aprobado");
  assert.strictEqual(L.formatModerationPush("fr", "rejected", "Bar X", "x").body, "Bar X n'a pas été approuvé. Motif : x");
  assert.strictEqual(L.formatModerationPush("pt", "rejected", "Bar X").body, "Bar X não foi aprovado.");
  assert.strictEqual(L.langOf({ appLanguageCode: "pt_PT" }), "pt");
  assert.strictEqual(L.langOf({ appLanguageCode: "es" }), "es");
});

test("motivo limpo e limitado a 300; dono; dados do toque", () => {
  assert.strictEqual(L.cleanReason("  a \n b ").length, 3);
  assert.strictEqual(L.cleanReason("x".repeat(500)).length, 300);
  assert.strictEqual(L.ownerUidOf({ ownerId: "o1" }, null), "o1");
  assert.strictEqual(L.ownerUidOf({ ownerId: "o1" }, { ownerUid: "o2" }), "o2");
  assert.deepStrictEqual(L.pushData("approved", "p1"), { type: "place_approved", placeId: "p1" });
  assert.deepStrictEqual(L.pushData("rejected", "p1"), { type: "place_rejected", placeId: "p1" });
});

test("moderationPatch grava o motivo na recusa e limpa na aprovação", () => {
  const r = S.moderationPatch("reject", "  Faltam fotos ");
  assert.strictEqual(r.moderationReason, "Faltam fotos");
  assert.strictEqual(r.status, "rejected");
  const a = S.moderationPatch("approve", "ignorado");
  assert.strictEqual(a.moderationReason, "");
  assert.strictEqual(S.moderationPatch("x"), null);
});
