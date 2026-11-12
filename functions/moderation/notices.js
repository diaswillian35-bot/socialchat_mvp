const { langFromUser, t: serverT } = require("../i18n/serverTexts");
/**
 * b44: Avisos Remdy (users/{uid}/systemInbox) da moderação, nos 5 idiomas.
 * Mesmos textos das chaves do app (lib/l10n/*.json).
 */

const T = {
  mod_warning_notice: {
    "pt-BR": "Aviso: sua mensagem quebrou as regras. Na próxima vez, você ficará 24 h sem enviar mensagens.",
    "pt-PT": "Aviso: a sua mensagem violou as regras. Da próxima vez, ficará 24 h sem enviar mensagens.",
    en: "Warning: your message broke the rules. Next time, you won't be able to send messages for 24 h.",
    es: "Aviso: tu mensaje infringió las reglas. La próxima vez, estarás 24 h sin enviar mensajes.",
    fr: "Avertissement : votre message enfreint les règles. La prochaine fois, vous ne pourrez plus envoyer de messages pendant 24 h.",
  },
  mod_muted_notice: {
    "pt-BR": "Você está suspenso até {until} por ofensas repetidas. Pode ler, mas não pode enviar mensagens nem falar nas salas.",
    "pt-PT": "Está suspenso até {until} por ofensas repetidas. Pode ler, mas não pode enviar mensagens nem falar nas salas.",
    en: "You're suspended until {until} for repeated insults. You can read, but you can't send messages or speak in rooms.",
    es: "Estás suspendido hasta {until} por ofensas repetidas. Puedes leer, pero no enviar mensajes ni hablar en las salas.",
    fr: "Vous êtes suspendu jusqu’au {until} pour insultes répétées. Vous pouvez lire, mais pas envoyer de messages ni parler dans les salons.",
  },
  mod_banned_notice: {
    "pt-BR": "Sua conta foi suspensa por violar as regras do Remdy. A equipe vai revisar o caso.",
    "pt-PT": "A sua conta foi suspensa por violar as regras do Remdy. A equipa vai rever o caso.",
    en: "Your account was suspended for breaking Remdy's rules. Our team will review it.",
    es: "Tu cuenta fue suspendida por infringir las reglas de Remdy. El equipo revisará el caso.",
    fr: "Votre compte a été suspendu pour non-respect des règles de Remdy. L’équipe va examiner le dossier.",
  },
  photo_blocked_notice: {
    "pt-BR": "Sua foto não foi aceita porque pode violar as regras do Remdy. Escolha outra foto. Se achar que foi engano, a equipe do Remdy vai revisar.",
    "pt-PT": "A sua foto não foi aceite porque pode violar as regras do Remdy. Escolha outra foto. Se achar que foi engano, a equipa do Remdy vai rever.",
    en: "Your photo wasn't accepted because it may break Remdy's rules. Please choose another photo. If you think this is a mistake, the Remdy team will review it.",
    es: "Tu foto no fue aceptada porque puede infringir las reglas de Remdy. Elige otra foto. Si crees que es un error, el equipo de Remdy lo revisará.",
    fr: "Votre photo n’a pas été acceptée car elle peut enfreindre les règles de Remdy. Choisissez une autre photo. Si vous pensez qu’il s’agit d’une erreur, l’équipe Remdy la vérifiera.",
  },
  notice_title: { "pt-BR": "Remdy", "pt-PT": "Remdy", en: "Remdy", es: "Remdy", fr: "Remdy" },
};

function langOf(userData) {
  return langFromUser(userData);
}

function text(key, lang, vars = {}) {
  const fromServer = serverT(key, lang, vars);
  if (fromServer) return fromServer;
  const row = T[key] || {};
  let s = row[lang] || row.en || "";
  for (const k of Object.keys(vars)) s = s.replaceAll(`{${k}}`, vars[k]);
  return s;
}

function formatUntil(ms, lang) {
  const d = new Date(ms);
  const two = (v) => String(v).padStart(2, "0");
  // UTC no servidor; o app mostra a hora local no composer (mod_muted_hint).
  return lang === "en"
    ? `${two(d.getUTCMonth() + 1)}/${two(d.getUTCDate())} ${two(d.getUTCHours())}:${two(d.getUTCMinutes())} UTC`
    : `${two(d.getUTCDate())}/${two(d.getUTCMonth() + 1)} ${two(d.getUTCHours())}:${two(d.getUTCMinutes())} UTC`;
}

async function pushNotice(admin, db, uid, key, vars = {}, extra = {}) {
  if (!uid) return;
  try {
    const u = await db.collection("users").doc(uid).get();
    const lang = langOf(u.exists ? u.data() : null);
    const v = { ...vars };
    if (typeof v.untilMs === "number") { v.until = formatUntil(v.untilMs, lang); delete v.untilMs; }
    await db.collection("users").doc(uid).collection("systemInbox").add({
      title: text("notice_title", lang),
      body: text(key, lang, v),
      type: "moderation",
      key,
      isRead: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      ...extra,
    });
  } catch (err) {
    console.warn("moderation notice failed", err && err.message);
  }
}

module.exports = { T, langOf, text, formatUntil, pushNotice };
