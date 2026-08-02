/**
 * node event_editorial.test.js
 */
"use strict";
const assert = require("assert");
const {
  validateEventEditorial,
  formatScheduleLines,
  formatAttractionLines,
  EVENT_CREATE_ALLOWED,
} = require("./event_editorial");

function pass(m) {
  console.log("PASS", m);
}

function base(over = {}) {
  return {
    title: "Festival QA",
    description: "Descrição completa do evento QA",
    category: "Festival",
    startAtMs: Date.parse("2026-09-01T21:00:00.000Z"),
    endAtMs: Date.parse("2026-09-02T02:00:00.000Z"),
    eventTimeZone: "America/Sao_Paulo",
    city: "Navegantes",
    placeName: "Orla",
    countryCode: "br",
    ...over,
  };
}

function main() {
  const min = validateEventEditorial(base(), {
    forUpdate: false,
    nowMs: Date.parse("2026-07-31T12:00:00Z"),
  });
  assert.strictEqual(min.title, "Festival QA");
  pass("create mínimo válido");

  const full = validateEventEditorial(
    base({
      shortDescription: "Resumo SEO",
      subcategories: ["música", "food"],
      primaryLanguage: "pt-BR",
      ticketType: "free",
      expectedAudience: 2500,
      logoUrl: "https://cdn.example.com/logo.png",
      coverUrl: "https://cdn.example.com/cover.jpg",
      photoUrls: [
        "https://cdn.example.com/p1.jpg",
        "https://cdn.example.com/p1.jpg?w=800",
        "https://cdn.example.com/p2.jpg",
      ],
      schedule: [
        { title: "Abertura", day: "22 ago", startTime: "18:00", order: 1 },
        { title: "Shows", day: "22 ago", startTime: "20:30", order: 0 },
      ],
      attractions: [{ name: "DJ", description: "Local" }],
      publicContact: "contato@evento.com",
      publicContactConsent: true,
      websiteUrl: "https://example.com",
    }),
    { forUpdate: false, nowMs: Date.parse("2026-07-31T12:00:00Z") },
  );
  assert.strictEqual(full.shortDescription, "Resumo SEO");
  assert.strictEqual(full.isFree, true);
  assert.strictEqual(full.expectedAudience, 2500);
  assert.strictEqual(full.photoUrls.length, 2); // dedupe same path
  assert.strictEqual(full.schedule[0].title, "Shows"); // order
  assert.ok(EVENT_CREATE_ALLOWED.has("schedule"));
  pass("create completo + dedupe + order");

  assert.throws(
    () =>
      validateEventEditorial(base({ endAtMs: base().startAtMs - 1000 }), {
        forUpdate: false,
      }),
    /endAtMs must be after/,
  );
  pass("término antes do início");

  assert.throws(
    () =>
      validateEventEditorial(base(), {
        forUpdate: false,
        nowMs: Date.parse("2030-01-01T00:00:00Z"),
      }),
    /past/,
  );
  pass("create não termina no passado");

  assert.throws(
    () =>
      validateEventEditorial(base({ ticketUrl: "http://insecure.example.com" }), {
        forUpdate: false,
        nowMs: Date.parse("2026-07-01"),
      }),
    /ticketUrl/,
  );
  pass("URL insegura rejeitada");

  assert.throws(
    () =>
      validateEventEditorial(base({ status: "approved" }), {
        forUpdate: false,
        nowMs: Date.parse("2026-07-01"),
      }),
    /Field not allowed/,
  );
  pass("campo admin bloqueado");

  const paid = validateEventEditorial(
    base({ ticketType: "paid", price: "50", priceCurrency: "BRL" }),
    { forUpdate: false, nowMs: Date.parse("2026-07-01") },
  );
  assert.strictEqual(paid.isFree, false);
  pass("ingresso pago");

  const inquire = validateEventEditorial(
    base({ ticketType: "inquire", ticketInfo: "Consulte no app" }),
    { forUpdate: false, nowMs: Date.parse("2026-07-01") },
  );
  assert.strictEqual(inquire.ticketType, "inquire");
  pass("ingresso consultar");

  assert.throws(
    () =>
      validateEventEditorial(base({ expectedAudience: 0 }), {
        forUpdate: false,
        nowMs: Date.parse("2026-07-01"),
      }),
    /expectedAudience/,
  );
  pass("público esperado inválido");

  assert.throws(
    () =>
      validateEventEditorial(
        base({ publicContact: "a@b.com", publicContactConsent: false }),
        { forUpdate: false, nowMs: Date.parse("2026-07-01") },
      ),
    /publicContactConsent/,
  );
  pass("contato sem consentimento");

  const legacySched = validateEventEditorial(
    base({ schedule: ["18h Abertura", "20h Show"] }),
    { forUpdate: true },
  );
  assert.strictEqual(legacySched.schedule.length, 2);
  pass("schedule legado string[]");

  const lines = formatScheduleLines(full.schedule);
  assert.ok(lines[0].includes("Shows"));
  assert.ok(formatAttractionLines(full.attractions)[0].includes("DJ"));
  pass("format lines");

  // update parcial
  const upd = validateEventEditorial(
    { title: "Novo título", shortDescription: "" },
    { forUpdate: true },
  );
  assert.strictEqual(upd.title, "Novo título");
  assert.strictEqual(upd.shortDescription, "");
  pass("update parcial + clear shortDescription");

  console.log("\nAll event_editorial tests passed.");
}

main();
