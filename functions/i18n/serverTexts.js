"use strict";
// Textos do servidor nos 5 idiomas do app (pt-BR, pt-PT, en, es, fr).
// Campo de idioma no users/{uid}: appLanguageCode (fallbacks: appLang,
// languageCode, appLanguage, language, locale). Sem valor: pt-BR;
// código não reconhecido: en.

const LANGS = Object.freeze(["pt-BR", "pt-PT", "en", "es", "fr"]);

const TEXTS = Object.freeze({
  "push_new_message": Object.freeze({
    "pt-BR": "Nova mensagem",
    "pt-PT": "Nova mensagem",
    "en": "New message",
    "es": "Mensaje nuevo",
    "fr": "Nouveau message",
  }),
  "push_audio": Object.freeze({
    "pt-BR": "🎤 Áudio",
    "pt-PT": "🎤 Áudio",
    "en": "🎤 Audio",
    "es": "🎤 Audio",
    "fr": "🎤 Audio",
  }),
  "push_photo": Object.freeze({
    "pt-BR": "📷 Foto",
    "pt-PT": "📷 Foto",
    "en": "📷 Photo",
    "es": "📷 Foto",
    "fr": "📷 Photo",
  }),
  "push_someone": Object.freeze({
    "pt-BR": "Alguém",
    "pt-PT": "Alguém",
    "en": "Someone",
    "es": "Alguien",
    "fr": "Quelqu’un",
  }),
  "push_group_fallback": Object.freeze({
    "pt-BR": "Grupo",
    "pt-PT": "Grupo",
    "en": "Group",
    "es": "Grupo",
    "fr": "Groupe",
  }),
  "push_place_fallback": Object.freeze({
    "pt-BR": "Local",
    "pt-PT": "Local",
    "en": "Place",
    "es": "Lugar",
    "fr": "Lieu",
  }),
  "push_event_your": Object.freeze({
    "pt-BR": "Seu evento",
    "pt-PT": "O seu evento",
    "en": "Your event",
    "es": "Tu evento",
    "fr": "Votre événement",
  }),
  "push_event_new_fallback": Object.freeze({
    "pt-BR": "Novo evento",
    "pt-PT": "Novo evento",
    "en": "New event",
    "es": "Nuevo evento",
    "fr": "Nouvel événement",
  }),
  "push_event_approved_title": Object.freeze({
    "pt-BR": "Evento aprovado",
    "pt-PT": "Evento aprovado",
    "en": "Event approved",
    "es": "Evento aprobado",
    "fr": "Événement approuvé",
  }),
  "push_event_approved_body": Object.freeze({
    "pt-BR": "\"{title}\" foi aprovado e já pode aparecer no app.",
    "pt-PT": "\"{title}\" foi aprovado e já pode aparecer na app.",
    "en": "\"{title}\" was approved and can now appear in the app.",
    "es": "\"{title}\" fue aprobado y ya puede aparecer en la app.",
    "fr": "« {title} » a été approuvé et peut maintenant apparaître dans l’app.",
  }),
  "push_event_rejected_title": Object.freeze({
    "pt-BR": "Evento rejeitado",
    "pt-PT": "Evento rejeitado",
    "en": "Event rejected",
    "es": "Evento rechazado",
    "fr": "Événement refusé",
  }),
  "push_event_rejected_body": Object.freeze({
    "pt-BR": "\"{title}\" foi rejeitado. Revise e envie novamente.",
    "pt-PT": "\"{title}\" foi rejeitado. Reveja e envie novamente.",
    "en": "\"{title}\" was rejected. Please review it and submit again.",
    "es": "\"{title}\" fue rechazado. Revísalo y envíalo de nuevo.",
    "fr": "« {title} » a été refusé. Vérifiez-le et renvoyez-le.",
  }),
  "push_event_changes_requested_title": Object.freeze({
    "pt-BR": "Alterações solicitadas",
    "pt-PT": "Alterações pedidas",
    "en": "Changes requested",
    "es": "Cambios solicitados",
    "fr": "Modifications demandées",
  }),
  "push_event_changes_requested_body": Object.freeze({
    "pt-BR": "\"{title}\" precisa de ajustes antes de republicar as mudanças.",
    "pt-PT": "\"{title}\" precisa de ajustes antes de republicar as alterações.",
    "en": "\"{title}\" needs adjustments before the changes can be published again.",
    "es": "\"{title}\" necesita ajustes antes de volver a publicar los cambios.",
    "fr": "« {title} » doit être ajusté avant de republier les modifications.",
  }),
  "push_event_changes_approved_title": Object.freeze({
    "pt-BR": "Alterações aprovadas",
    "pt-PT": "Alterações aprovadas",
    "en": "Changes approved",
    "es": "Cambios aprobados",
    "fr": "Modifications approuvées",
  }),
  "push_event_changes_approved_body": Object.freeze({
    "pt-BR": "As alterações de \"{title}\" foram aprovadas.",
    "pt-PT": "As alterações de \"{title}\" foram aprovadas.",
    "en": "The changes to \"{title}\" were approved.",
    "es": "Los cambios de \"{title}\" fueron aprobados.",
    "fr": "Les modifications de « {title} » ont été approuvées.",
  }),
  "push_event_changes_sent_title": Object.freeze({
    "pt-BR": "Alterações enviadas",
    "pt-PT": "Alterações enviadas",
    "en": "Changes submitted",
    "es": "Cambios enviados",
    "fr": "Modifications envoyées",
  }),
  "push_event_changes_sent_body": Object.freeze({
    "pt-BR": "As alterações de \"{title}\" foram enviadas para análise.",
    "pt-PT": "As alterações de \"{title}\" foram enviadas para análise.",
    "en": "The changes to \"{title}\" were submitted for review.",
    "es": "Los cambios de \"{title}\" se enviaron para revisión.",
    "fr": "Les modifications de « {title} » ont été envoyées pour examen.",
  }),
  "push_nearby_event_title": Object.freeze({
    "pt-BR": "📍 Novo evento perto de você",
    "pt-PT": "📍 Novo evento perto de si",
    "en": "📍 New event near you",
    "es": "📍 Nuevo evento cerca de ti",
    "fr": "📍 Nouvel événement près de vous",
  }),
  "push_nearby_event_body": Object.freeze({
    "pt-BR": "{title} • Toque para ver detalhes",
    "pt-PT": "{title} • Toque para ver detalhes",
    "en": "{title} • Tap to view details",
    "es": "{title} • Toca para ver detalles",
    "fr": "{title} • Touchez pour voir les détails",
  }),
  "push_join_approved_title": Object.freeze({
    "pt-BR": "Sua solicitação foi aprovada.",
    "pt-PT": "O seu pedido foi aprovado.",
    "en": "Your request was approved.",
    "es": "Tu solicitud fue aprobada.",
    "fr": "Votre demande a été approuvée.",
  }),
  "push_join_approved_body": Object.freeze({
    "pt-BR": "Agora você pode participar de {name}.",
    "pt-PT": "Agora pode participar de {name}.",
    "en": "You can now join {name}.",
    "es": "Ahora puedes participar en {name}.",
    "fr": "Vous pouvez maintenant participer à {name}.",
  }),
  "push_join_rejected_title": Object.freeze({
    "pt-BR": "Solicitação não aprovada",
    "pt-PT": "Pedido não aprovado",
    "en": "Request not approved",
    "es": "Solicitud no aprobada",
    "fr": "Demande non approuvée",
  }),
  "push_join_rejected_body": Object.freeze({
    "pt-BR": "Sua solicitação para entrar no grupo não foi aprovada.",
    "pt-PT": "O seu pedido para entrar no grupo não foi aprovado.",
    "en": "Your request to join the group was not approved.",
    "es": "Tu solicitud para entrar al grupo no fue aprobada.",
    "fr": "Votre demande pour rejoindre le groupe n’a pas été approuvée.",
  }),
  "push_join_request_title": Object.freeze({
    "pt-BR": "Nova solicitação",
    "pt-PT": "Novo pedido",
    "en": "New request",
    "es": "Nueva solicitud",
    "fr": "Nouvelle demande",
  }),
  "push_join_request_body": Object.freeze({
    "pt-BR": "{name} solicitou entrada no grupo {group}.",
    "pt-PT": "{name} pediu entrada no grupo {group}.",
    "en": "{name} requested to join the group {group}.",
    "es": "{name} solicitó entrar al grupo {group}.",
    "fr": "{name} a demandé à rejoindre le groupe {group}.",
  }),
  "push_event_comment_title": Object.freeze({
    "pt-BR": "Novo comentário no evento",
    "pt-PT": "Novo comentário no evento",
    "en": "New comment on the event",
    "es": "Nuevo comentario en el evento",
    "fr": "Nouveau commentaire sur l’événement",
  }),
  "push_event_reply_title": Object.freeze({
    "pt-BR": "Nova resposta",
    "pt-PT": "Nova resposta",
    "en": "New reply",
    "es": "Nueva respuesta",
    "fr": "Nouvelle réponse",
  }),
  "push_event_comment_body": Object.freeze({
    "pt-BR": "Novo comentário: {preview}",
    "pt-PT": "Novo comentário: {preview}",
    "en": "New comment: {preview}",
    "es": "Nuevo comentario: {preview}",
    "fr": "Nouveau commentaire : {preview}",
  }),
  "push_event_comment_body_empty": Object.freeze({
    "pt-BR": "Novo comentário no evento",
    "pt-PT": "Novo comentário no evento",
    "en": "New comment on the event",
    "es": "Nuevo comentario en el evento",
    "fr": "Nouveau commentaire sur l’événement",
  }),
  "push_report_title": Object.freeze({
    "pt-BR": "Nova denúncia",
    "pt-PT": "Nova denúncia",
    "en": "New report",
    "es": "Nueva denuncia",
    "fr": "Nouveau signalement",
  }),
  "push_report_body": Object.freeze({
    "pt-BR": "Nova denúncia · motivo: {reason} · total: {total}",
    "pt-PT": "Nova denúncia · motivo: {reason} · total: {total}",
    "en": "New report · reason: {reason} · total: {total}",
    "es": "Nueva denuncia · motivo: {reason} · total: {total}",
    "fr": "Nouveau signalement · motif : {reason} · total : {total}",
  }),
  "push_place_review_title": Object.freeze({
    "pt-BR": "Nova avaliação",
    "pt-PT": "Nova avaliação",
    "en": "New review",
    "es": "Nueva valoración",
    "fr": "Nouvel avis",
  }),
  "push_place_review_body": Object.freeze({
    "pt-BR": "Há uma nova avaliação em {name}.",
    "pt-PT": "Há uma nova avaliação em {name}.",
    "en": "There is a new review on {name}.",
    "es": "Hay una nueva valoración en {name}.",
    "fr": "Il y a un nouvel avis sur {name}.",
  }),
  "push_place_reply_title": Object.freeze({
    "pt-BR": "Resposta do estabelecimento",
    "pt-PT": "Resposta do estabelecimento",
    "en": "Reply from the business",
    "es": "Respuesta del establecimiento",
    "fr": "Réponse de l’établissement",
  }),
  "push_place_reply_body": Object.freeze({
    "pt-BR": "{name} respondeu sua avaliação.",
    "pt-PT": "{name} respondeu à sua avaliação.",
    "en": "{name} replied to your review.",
    "es": "{name} respondió a tu valoración.",
    "fr": "{name} a répondu à votre avis.",
  }),
  "push_place_approved_title": Object.freeze({
    "pt-BR": "Local aprovado",
    "pt-PT": "Local aprovado",
    "en": "Place approved",
    "es": "Lugar aprobado",
    "fr": "Lieu approuvé",
  }),
  "push_place_approved_body": Object.freeze({
    "pt-BR": "{name} foi aprovado e já aparece em Locais.",
    "pt-PT": "{name} foi aprovado e já aparece em Locais.",
    "en": "{name} was approved and now shows in Places.",
    "es": "{name} fue aprobado y ya aparece en Lugares.",
    "fr": "{name} a été approuvé et apparaît maintenant dans Lieux.",
  }),
  "push_place_rejected_title": Object.freeze({
    "pt-BR": "Local não aprovado",
    "pt-PT": "Local não aprovado",
    "en": "Place not approved",
    "es": "Lugar no aprobado",
    "fr": "Lieu non approuvé",
  }),
  "push_place_rejected_body": Object.freeze({
    "pt-BR": "{name} não foi aprovado.",
    "pt-PT": "{name} não foi aprovado.",
    "en": "{name} was not approved.",
    "es": "{name} no fue aprobado.",
    "fr": "{name} n'a pas été approuvé.",
  }),
  "push_place_rejected_reason": Object.freeze({
    "pt-BR": "Motivo: {reason}",
    "pt-PT": "Motivo: {reason}",
    "en": "Reason: {reason}",
    "es": "Motivo: {reason}",
    "fr": "Motif : {reason}",
  }),
  "push_place_admin_title": Object.freeze({
    "pt-BR": "Novo local em análise",
    "pt-PT": "Novo local em análise",
    "en": "New place to review",
    "es": "Nuevo lugar para revisar",
    "fr": "Nouveau lieu à vérifier",
  }),
  "push_place_admin_body": Object.freeze({
    "pt-BR": "{name} ({place}) aguarda aprovação.",
    "pt-PT": "{name} ({place}) aguarda aprovação.",
    "en": "{name} ({place}) is waiting for approval.",
    "es": "{name} ({place}) espera aprobación.",
    "fr": "{name} ({place}) attend une validation.",
  }),
  "push_audio_live_title": Object.freeze({
    "pt-BR": "{group} está ao vivo",
    "pt-PT": "{group} está em direto",
    "en": "{group} is live",
    "es": "{group} está en directo",
    "fr": "{group} est en direct",
  }),
  "push_audio_live_body": Object.freeze({
    "pt-BR": "{name} abriu uma sala de áudio. Toque para ouvir.",
    "pt-PT": "{name} abriu uma sala de áudio. Toque para ouvir.",
    "en": "{name} opened an audio room. Tap to listen.",
    "es": "{name} abrió una sala de audio. Toca para escuchar.",
    "fr": "{name} a ouvert un salon audio. Touchez pour écouter.",
  }),
  "push_interest_title": Object.freeze({
    "pt-BR": "Interesses em comum",
    "pt-PT": "Interesses em comum",
    "en": "Shared interests",
    "es": "Intereses en común",
    "fr": "Intérêts communs",
  }),
  "push_interest_one": Object.freeze({
    "pt-BR": "Conheça {name}: também curte {a}",
    "pt-PT": "Conheça {name}: também gosta de {a}",
    "en": "Meet {name}: also into {a}",
    "es": "Conoce a {name}: también le gusta {a}",
    "fr": "Découvrez {name} : aime aussi {a}",
  }),
  "push_interest_two": Object.freeze({
    "pt-BR": "Conheça {name}: também curte {a} e {b}",
    "pt-PT": "Conheça {name}: também gosta de {a} e {b}",
    "en": "Meet {name}: also into {a} and {b}",
    "es": "Conoce a {name}: también le gusta {a} y {b}",
    "fr": "Découvrez {name} : aime aussi {a} et {b}",
  }),
  "mod_warning_notice": Object.freeze({
    "pt-BR": "Aviso: sua mensagem quebrou as regras. Na próxima vez, você ficará 24 h sem enviar mensagens.",
    "pt-PT": "Aviso: a sua mensagem violou as regras. Da próxima vez, ficará 24 h sem enviar mensagens.",
    "en": "Warning: your message broke the rules. Next time, you won't be able to send messages for 24 h.",
    "es": "Aviso: tu mensaje infringió las reglas. La próxima vez, estarás 24 h sin enviar mensajes.",
    "fr": "Avertissement : votre message enfreint les règles. La prochaine fois, vous ne pourrez plus envoyer de messages pendant 24 h.",
  }),
  "mod_muted_notice": Object.freeze({
    "pt-BR": "Você está suspenso até {until} por ofensas repetidas. Pode ler, mas não pode enviar mensagens nem falar nas salas.",
    "pt-PT": "Está suspenso até {until} por ofensas repetidas. Pode ler, mas não pode enviar mensagens nem falar nas salas.",
    "en": "You're suspended until {until} for repeated insults. You can read, but you can't send messages or speak in rooms.",
    "es": "Estás suspendido hasta {until} por ofensas repetidas. Puedes leer, pero no enviar mensajes ni hablar en las salas.",
    "fr": "Vous êtes suspendu jusqu’au {until} pour insultes répétées. Vous pouvez lire, mais pas envoyer de messages ni parler dans les salons.",
  }),
  "mod_banned_notice": Object.freeze({
    "pt-BR": "Sua conta foi suspensa por violar as regras do Remdy. A equipe vai revisar o caso.",
    "pt-PT": "A sua conta foi suspensa por violar as regras do Remdy. A equipa vai rever o caso.",
    "en": "Your account was suspended for breaking Remdy's rules. Our team will review it.",
    "es": "Tu cuenta fue suspendida por infringir las reglas de Remdy. El equipo revisará el caso.",
    "fr": "Votre compte a été suspendu pour non-respect des règles de Remdy. L’équipe va examiner le dossier.",
  }),
  "photo_blocked_notice": Object.freeze({
    "pt-BR": "Sua foto não foi aceita porque pode violar as regras do Remdy. Escolha outra foto. Se achar que foi engano, a equipe do Remdy vai revisar.",
    "pt-PT": "A sua foto não foi aceite porque pode violar as regras do Remdy. Escolha outra foto. Se achar que foi engano, a equipa do Remdy vai rever.",
    "en": "Your photo wasn't accepted because it may break Remdy's rules. Please choose another photo. If you think this is a mistake, the Remdy team will review it.",
    "es": "Tu foto no fue aceptada porque puede infringir las reglas de Remdy. Elige otra foto. Si crees que es un error, el equipo de Remdy lo revisará.",
    "fr": "Votre photo n’a pas été acceptée car elle peut enfreindre les règles de Remdy. Choisissez une autre photo. Si vous pensez qu’il s’agit d’une erreur, l’équipe Remdy la vérifiera.",
  }),
  "notice_title": Object.freeze({
    "pt-BR": "Remdy",
    "pt-PT": "Remdy",
    "en": "Remdy",
    "es": "Remdy",
    "fr": "Remdy",
  }),
  "new_users_push_body": Object.freeze({
    "pt-BR": "Novas pessoas chegaram à Remdy. Venha dar um oi!",
    "pt-PT": "Novas pessoas chegaram à Remdy. Venha dar um oi!",
    "en": "New people just arrived on Remdy. Come say hi!",
    "es": "Llegaron personas nuevas a Remdy. ¡Ven a saludar!",
    "fr": "De nouvelles personnes viennent d’arriver sur Remdy. Venez dire bonjour !",
  }),
});

const KEYS = Object.freeze(Object.keys(TEXTS));

function normalizeLang(raw) {
  const t = String(raw == null ? "" : raw).trim().toLowerCase().replace(/_/g, "-");
  if (!t) return null;
  if (t === "pt-pt" || t.startsWith("pt-pt-")) return "pt-PT";
  if (t === "pt" || t === "pt-br" || t.startsWith("pt-br") || t.startsWith("pt-")) return "pt-BR";
  const two = t.split("-")[0];
  if (two === "en" || two === "es" || two === "fr") return two;
  return null;
}

/** Lê o idioma gravado em users/{uid}. */
function langFromUser(userData, opts = {}) {
  const d = userData && typeof userData === "object" ? userData : null;
  const raw = d && (
    d.appLanguageCode ||
    d.appLang ||
    d.languageCode ||
    d.appLanguage ||
    d.language ||
    d.locale
  );
  const n = normalizeLang(raw);
  if (n) return n;
  if (opts.countryFallback) {
    const country = String((d && (d.homeCountryCode || d.countryCode)) || "")
      .trim()
      .toLowerCase();
    if (country === "ca") return "en";
  }
  if (opts.unrecognizedToEn !== false && raw != null && String(raw).trim()) {
    return "en";
  }
  return opts.fallback || "pt-BR";
}

/** Alias compacto usado por módulos antigos (br / pt / en / es / fr). */
function compactLang(lang) {
  if (lang === "pt-PT") return "pt";
  if (lang === "pt-BR") return "br";
  if (lang === "en" || lang === "es" || lang === "fr") return lang;
  return "br";
}

function fill(s, vars) {
  let out = String(s == null ? "" : s);
  if (!vars) return out;
  for (const k of Object.keys(vars)) {
    out = out.replaceAll("{" + k + "}", String(vars[k] == null ? "" : vars[k]));
  }
  return out;
}

function t(key, lang, vars) {
  const row = TEXTS[key] || {};
  const code = normalizeLang(lang) || "pt-BR";
  const s = row[code] || row["pt-BR"] || row.en || "";
  return fill(s, vars);
}

function hasKey(key) {
  return Object.prototype.hasOwnProperty.call(TEXTS, key);
}

module.exports = {
  LANGS,
  TEXTS,
  KEYS,
  normalizeLang,
  langFromUser,
  compactLang,
  fill,
  t,
  hasKey,
};
