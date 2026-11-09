"use strict";
// Regras puras das salas de áudio dos grupos (sem firebase-admin).
// O país segue RemdyLaunchAccess.canAccessGroupCountry do app (lançamento
// gratuito BR/CA: mesmo país aberto; admin total vê todos).
const { roleOf } = require("./group_role_policy");

const MAX_PARTICIPANTS = 50;
const FREE_COUNTRY_CODES = Object.freeze(["br", "ca"]);
// Teste: o push "sala ao vivo" só sai para estes grupos (Papo de Boteco).
const AUDIO_PUSH_TEST_GROUP_IDS = Object.freeze(["8ehlhwLZj9twQ47TSOIu"]);
const LIVEKIT_URL = "wss://remdy-ngb7mimi.livekit.cloud";
const LIVEKIT_HOST = "https://remdy-ngb7mimi.livekit.cloud";

const norm = (v) => (v == null ? "" : String(v)).trim().toLowerCase();

function isCountryOpen(code) {
  const c = norm(code);
  if (!c || c === "world" || c === "mundo") return false;
  return FREE_COUNTRY_CODES.includes(c);
}

function userCountry(user) {
  return norm(user?.homeCountryCode) || norm(user?.countryCode);
}

function groupCountry(group) {
  return norm(group?.countryCode);
}

/** Espelho de canAccessGroupCountry (isFreeBrazilLaunch = true no app). */
function canAccessGroupCountry(homeCountry, groupCountryCode, isAdmin) {
  if (isAdmin) return true;
  const home = norm(homeCountry), target = norm(groupCountryCode);
  if (!home || !target) return false;
  if (!isCountryOpen(home) || !isCountryOpen(target)) return false;
  return home === target;
}

function isModeratorRole(role) {
  return role === "owner" || role === "admin" || role === "moderator";
}


/**
 * Pode entrar na sala? Retorna null ou um código de erro.
 * Membro do grupo + país; admin total não ganha papel no grupo.
 */
function joinError({ group, user, uid, isAdmin, banned }) {
  if (!uid) return "unauthenticated";
  if (!group || group.deleted === true || group.isActive === false) {
    return "group_not_found";
  }
  if (banned === true) return "banned";
  if (roleOf(group, uid) === "outsider") return "not_member";
  if (!canAccessGroupCountry(userCountry(user), groupCountry(group), isAdmin)) {
    return "country_blocked";
  }
  return null;
}

/** Abrir ou fechar a sala: só dono, admin do grupo ou moderador. */
function manageError(args) {
  const e = joinError(args);
  if (e) return e;
  return isModeratorRole(roleOf(args.group, args.uid)) ? null : "not_moderator";
}

/** Permissões do token LiveKit para o participante. */
function grantFor({ group, room, uid }) {
  const role = roleOf(group, uid);
  const speakers = Array.isArray(room?.speakerUids) ? room.speakerUids : [];
  const canPublish = isModeratorRole(role) || speakers.includes(uid);
  return {
    role,
    canPublish,
    canSubscribe: true,
    canPublishData: true,
    canPublishSources: canPublish ? ["microphone"] : [],
  };
}

function capacityError(room, uid) {
  const present = Array.isArray(room?.presentUids) ? room.presentUids : [];
  if (present.includes(uid)) return null;
  const count = Number(room?.participantCount || 0);
  return count >= MAX_PARTICIPANTS ? "room_full" : null;
}

function roomNameFor(groupId) {
  return `grp_${String(groupId)}`;
}

function groupIdFromRoomName(name) {
  const s = String(name || "");
  return s.startsWith("grp_") ? s.slice(4) : "";
}

function isLive(room) {
  return Boolean(room) && room.status === "live";
}

/** Aprovar/revogar fala: moderador, alvo membro (não pode mexer em mod). */
function speakerChangeError({ group, uid, targetUid }) {
  if (!isModeratorRole(roleOf(group, uid))) return "not_moderator";
  const t = roleOf(group, targetUid);
  if (t === "outsider") return "not_member";
  if (isModeratorRole(t)) return "target_is_moderator";
  return null;
}

function shouldSendLivePush(groupId, allowlist = AUDIO_PUSH_TEST_GROUP_IDS) {
  return allowlist.includes(String(groupId));
}

/** Membro desligou o push de sala ao vivo neste grupo? */
function audioPushMuted(groupPref) {
  return groupPref?.audioRoomPush === false;
}

const PUSH_TEXTS = Object.freeze({
  "pt-BR": { title: "{group} está ao vivo", body: "{name} abriu uma sala de áudio. Toque para ouvir." },
  "pt-PT": { title: "{group} está em direto", body: "{name} abriu uma sala de áudio. Toque para ouvir." },
  en: { title: "{group} is live", body: "{name} opened an audio room. Tap to listen." },
  es: { title: "{group} está en directo", body: "{name} abrió una sala de audio. Toca para escuchar." },
  fr: { title: "{group} est en direct", body: "{name} a ouvert un salon audio. Touchez pour écouter." },
});

function pushLocale(user) {
  const raw = norm(user?.appLanguage || user?.language || user?.locale).replace("_", "-");
  if (raw === "pt-pt") return "pt-PT";
  if (raw.startsWith("pt")) return "pt-BR";
  const p = raw.split("-")[0];
  if (p === "en" || p === "es" || p === "fr") return p;
  return userCountry(user) === "ca" ? "en" : "pt-BR";
}

function livePushText(locale, groupName, openerName) {
  const t = PUSH_TEXTS[locale] || PUSH_TEXTS["pt-BR"];
  const fill = (s) => s.replace("{group}", groupName || "Remdy").replace("{name}", openerName || "Remdy");
  return { title: fill(t.title), body: fill(t.body) };
}

module.exports = {
  MAX_PARTICIPANTS, FREE_COUNTRY_CODES, AUDIO_PUSH_TEST_GROUP_IDS, LIVEKIT_URL, LIVEKIT_HOST,
  isCountryOpen, userCountry, groupCountry, canAccessGroupCountry, isModeratorRole,
  joinError, manageError, grantFor, capacityError, roomNameFor, groupIdFromRoomName,
  isLive, speakerChangeError, shouldSendLivePush, audioPushMuted, PUSH_TEXTS, pushLocale,
  livePushText,
};
