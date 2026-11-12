"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const S = require("./serverTexts");
const H = require("./httpsError");

test("todas as chaves existem nos 5 idiomas", () => {
  for (const key of S.KEYS) {
    const row = S.TEXTS[key];
    assert.ok(row, key);
    for (const lang of S.LANGS) {
      const v = row[lang];
      assert.equal(typeof v, "string", `${key}/${lang}`);
      assert.ok(String(v).trim(), `${key}/${lang} vazio`);
    }
  }
});

test("langFromUser lê appLanguageCode e os fallbacks", () => {
  assert.equal(S.langFromUser({ appLanguageCode: "pt-PT" }), "pt-PT");
  assert.equal(S.langFromUser({ appLanguageCode: "pt_PT" }), "pt-PT");
  assert.equal(S.langFromUser({ appLang: "es" }), "es");
  assert.equal(S.langFromUser({ languageCode: "fr-CA" }), "fr");
  assert.equal(S.langFromUser({ appLanguage: "en-US" }), "en");
  assert.equal(S.langFromUser({ language: "pt-BR" }), "pt-BR");
  assert.equal(S.langFromUser({ locale: "pt_PT" }), "pt-PT");
  assert.equal(S.langFromUser({ appLanguageCode: "pt" }), "pt-BR");
  assert.equal(S.langFromUser({}), "pt-BR");
  assert.equal(S.langFromUser(null), "pt-BR");
  assert.equal(S.langFromUser({ appLanguageCode: "de" }), "en");
  assert.equal(S.langFromUser({ homeCountryCode: "ca" }, { countryFallback: true }), "en");
  assert.equal(S.langFromUser({ homeCountryCode: "br" }, { countryFallback: true }), "pt-BR");
});

test("t preenche variáveis e cai para pt-BR", () => {
  assert.equal(
    S.t("push_join_request_title", "pt-BR"),
    "Nova solicitação",
  );
  assert.match(
    S.t("push_event_approved_body", "en", { title: "Festa" }),
    /Festa/,
  );
  assert.equal(S.t("notice_title", "xx"), "Remdy");
});

test("httpsError mantém a message e anexa i18nKey", () => {
  const err = H.httpsError("failed-precondition", "Premium required for international groups.");
  assert.equal(err instanceof H.HttpsError, true);
  assert.equal(err.message, "Premium required for international groups.");
  assert.equal(err.details.i18nKey, "group_premium_other_country");
  const kept = H.httpsError("invalid-argument", "photo_required");
  assert.equal(kept.message, "photo_required");
  assert.equal(kept.details && kept.details.i18nKey, undefined);
  const withLoc = H.httpsError("permission-denied", "not_admin", { localizationKey: "group_edit_no_permission" });
  assert.equal(withLoc.details.localizationKey, "group_edit_no_permission");
  assert.equal(withLoc.details.i18nKey, "group_edit_no_permission");
});
