"use strict";

/** Aviso aos admins quando um local entra em análise (5 idiomas). */
const placeModerationPush = require("./place_moderation_push_logic");

const MAX_ADMINS = 50;

const COPY = {
  br: { title: "Novo local em análise", body: "{name} ({place}) aguarda aprovação." },
  pt: { title: "Novo local em análise", body: "{name} ({place}) aguarda aprovação." },
  en: { title: "New place to review", body: "{name} ({place}) is waiting for approval." },
  es: { title: "Nuevo lugar para revisar", body: "{name} ({place}) espera aprobación." },
  fr: { title: "Nouveau lieu à vérifier", body: "{name} ({place}) attend une validation." },
};

/** true só quando o local passa a "pending" (criação ou reenvio). */
function shouldNotify(before, after) {
  if (!after || after.moderationStatus !== "pending") return false;
  if (after.deleted === true) return false;
  return !before || before.moderationStatus !== "pending";
}

/** Admins ativos com acesso a Locais: dono (isOwner) ou permissions.places. */
function adminUidsFrom(docs) {
  const out = [];
  for (const d of docs || []) {
    const data = (d && d.data) || {};
    if (!d || !d.id || data.isActive === false) continue;
    const perms = data.permissions && typeof data.permissions === "object" ? data.permissions : {};
    if (data.isOwner !== true && perms.places !== true) continue;
    out.push(String(d.id));
    if (out.length >= MAX_ADMINS) break;
  }
  return [...new Set(out)];
}

function placeLabel(p) {
  const city = String((p && p.cityName) || "").trim();
  const cc = String((p && p.countryCode) || "").trim().toUpperCase();
  return [city, cc].filter(Boolean).join(" · ") || "—";
}

function formatNotice(lang, place) {
  const c = COPY[lang] || COPY.br;
  const name = String((place && place.name) || "").trim().slice(0, 80) || "—";
  return {
    title: c.title,
    body: c.body.replace("{name}", name).replace("{place}", placeLabel(place)),
  };
}

function pushData(placeId, place) {
  return {
    type: "place_pending_admin",
    placeId: String(placeId),
    countryCode: String((place && place.countryCode) || "").toUpperCase(),
  };
}

module.exports = {
  COPY,
  MAX_ADMINS,
  shouldNotify,
  adminUidsFrom,
  formatNotice,
  pushData,
  langOf: placeModerationPush.langOf,
};
