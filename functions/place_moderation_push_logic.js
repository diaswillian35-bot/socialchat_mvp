"use strict";

/** Push ao dono com o resultado da moderação do local (5 idiomas). */
const MAX_REASON = 300;

const COPY = {
  br: {
    approvedTitle: "Local aprovado",
    approved: "{name} foi aprovado e já aparece em Locais.",
    rejectedTitle: "Local não aprovado",
    rejected: "{name} não foi aprovado.",
    reason: "Motivo: {reason}",
  },
  pt: {
    approvedTitle: "Local aprovado",
    approved: "{name} foi aprovado e já aparece em Locais.",
    rejectedTitle: "Local não aprovado",
    rejected: "{name} não foi aprovado.",
    reason: "Motivo: {reason}",
  },
  en: {
    approvedTitle: "Place approved",
    approved: "{name} was approved and now shows in Places.",
    rejectedTitle: "Place not approved",
    rejected: "{name} was not approved.",
    reason: "Reason: {reason}",
  },
  es: {
    approvedTitle: "Lugar aprobado",
    approved: "{name} fue aprobado y ya aparece en Lugares.",
    rejectedTitle: "Lugar no aprobado",
    rejected: "{name} no fue aprobado.",
    reason: "Motivo: {reason}",
  },
  fr: {
    approvedTitle: "Lieu approuvé",
    approved: "{name} a été approuvé et apparaît maintenant dans Lieux.",
    rejectedTitle: "Lieu non approuvé",
    rejected: "{name} n'a pas été approuvé.",
    reason: "Motif : {reason}",
  },
};

function cleanReason(raw) {
  return String(raw == null ? "" : raw).replace(/\s+/g, " ").trim().slice(0, MAX_REASON);
}

function langOf(userData) {
  const raw = String(
    (userData && (userData.appLanguageCode || userData.appLang || userData.languageCode)) || "pt_BR",
  ).toLowerCase().replace("-", "_");
  if (raw.startsWith("pt")) return raw === "pt_pt" ? "pt" : "br";
  const two = raw.substring(0, 2);
  return COPY[two] ? two : "br";
}

/** "approved" | "rejected" | null — só na transição a partir de pendente. */
function moderationOutcome(before, after) {
  if (!before || !after) return null;
  if (before.moderationStatus !== "pending") return null;
  if (after.moderationStatus === "published") return "approved";
  if (after.moderationStatus === "rejected") return "rejected";
  return null;
}

function ownerUidOf(placeData, accessData) {
  return String((accessData && accessData.ownerUid) || (placeData && placeData.ownerId) || "").trim();
}

function formatModerationPush(lang, outcome, placeName, reason) {
  const c = COPY[lang] || COPY.br;
  const name = String(placeName || "").trim() || "Remdy";
  if (outcome === "approved") {
    return {
      title: c.approvedTitle,
      body: c.approved.replace("{name}", name),
    };
  }
  const r = cleanReason(reason);
  const body = c.rejected.replace("{name}", name) + (r ? " " + c.reason.replace("{reason}", r) : "");
  return { title: c.rejectedTitle, body };
}

function pushData(outcome, placeId) {
  return outcome === "approved"
    ? { type: "place_approved", placeId }
    : { type: "place_rejected", placeId };
}

module.exports = {
  MAX_REASON,
  cleanReason,
  langOf,
  moderationOutcome,
  ownerUidOf,
  formatModerationPush,
  pushData,
};
