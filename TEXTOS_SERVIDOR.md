# Textos no servidor — i18n local (aguardando deploy)

Trabalho local na branch `feat/b44-erros-auth` (worktree `/Volumes/REMDY_SSD/b44_erros_auth`).
Nada disto foi implantado.

Módulo único: `functions/i18n/serverTexts.js` (5 idiomas: pt-BR, pt-PT, en, es, fr).
Campo de idioma em `users/{uid}`: **`appLanguageCode`**, com fallbacks `appLang`, `languageCode`, `appLanguage`, `language`, `locale`.
Sem valor: **pt-BR**. Código não reconhecido: **en**.
Nas salas de áudio, se não houver idioma gravado e o país do utilizador for CA: **en** (padrão já existente).

O app hoje grava o idioma só em SharedPreferences (`app_lang`). **Não escreve `appLanguageCode` no Firestore** (não foi adicionado aqui: exigiria escrita no perfil, não aprovada). Enquanto o campo não for gravado, os pushes usam o fallback.

## Como o idioma é escolhido

- **Pushes e avisos:** idioma do destinatário (`users/{uid}.appLanguageCode` + fallbacks). O `lastMessage` gravado no grupo/conversa permanece em pt-BR (`Nova mensagem`, `🎤 Áudio`, `📷 Foto`); só o texto do push é traduzido.
- **HttpsError:** a `message` original (en/pt) **não muda**, para apps antigos que ainda comparam `e.message`. O servidor anexa `details.i18nKey` (e reutiliza `localizationKey` quando já existia). O app novo traduz pela chave em `AppTexts` (`lib/services/functions_error_text.dart`).
- **Página /l/{id}:** já usava `Accept-Language` e `?lang` (5 idiomas). Não foi alterada neste passo. O site de marketing (`landing/`, `public/index.html`) ficou de fora, como pedido.

## O que precisa de deploy (nada foi implantado)

Pushes e avisos:

```
firebase deploy --only functions:onGroupMessageCreated,functions:onPrivateMessageCreated,functions:onEventUpdated,functions:onGroupJoinRequestCreated,functions:onGroupJoinRequestUpdated,functions:approveGroupJoinRequest,functions:rejectGroupJoinRequest,functions:createEventComment,functions:onAudioRoomOpened,functions:onReportCreated,functions:submitPlaceReview,functions:replyPlaceReview,functions:onPlaceModerated,functions:onPlacePendingNotifyAdmins,functions:onPublicUserInterestsWritten
```

Callables que passaram a anexar `details.i18nKey` (mesmo `message` de antes). Exemplos principais:

```
firebase deploy --only functions:confirmAdultAge,functions:deleteMyAccount,functions:createGroup,functions:updateGroupSettings,functions:joinGroupByInviteCode,functions:joinOpenGroup,functions:leaveGroup,functions:deleteGroup,functions:banGroupMember,functions:unbanGroupMember,functions:promoteGroupAdmin,functions:demoteGroupAdmin,functions:removeGroupMember,functions:createEvent,functions:updateEvent,functions:cancelEvent,functions:joinEvent,functions:leaveEvent,functions:sendDmMessage,functions:forwardMessage,functions:searchUsers,functions:submitPlace,functions:updateMyPlace,functions:moderatePlace,functions:askRemi,functions:audioRoomAction,functions:setGroupAudioRoom
```

Mais callables no mesmo estilo (também tocaram no helper): `applyInviteCode`, `claimInvitePremiumReward`, `fetchLinkPreview`, `issueShareExtensionSession`, `sendShareMessage`, `listShareDestinations`, `revokeShareExtensionSessions`, `translatePlaceDescription`, `claimPlaceForAccount`, `listPlaceReviews`, `transferGroupOwnership`, `markGroupAsRead`, `exportEventParticipants`, `toggleEventLike`, `toggleEventCommentLike`, `deleteEventComment`, `registerEventView`, `archiveEvent`, `restoreEvent`, `duplicateEvent`, `deleteEventPermanently`, `abortIncompleteEvent`, `approveEventPendingChanges`, `rejectEventPendingChanges`, `syncRevenueCatEntitlement`, e as de presença/verificação (`markPhoneVerified`, `unlinkVerifiedPhone`, etc.).

**Hosting:** a página pública `/l/` já estava nos 5 idiomas e não mudou neste passo. Não há deploy de hosting pendente por causa deste trabalho. Portal-login e convite (commits anteriores nesta branch) só entram no ar com um deploy de hosting futuro, se for aprovado.

## De fora (de propósito)

- Site de marketing (`landing/`, `public/index.html`)
- Texto do sistema no chat da sala de áudio (`🎧 … abriu uma sala de áudio`) — continua desligado e, se ligar, é uma mensagem gravada (um idioma só)
- Fallback `Evento Remdy` na imagem social (um asset para todos os idiomas)
- `lastMessage` gravado no Firestore (prévia da lista) — só o push é traduzido
- E-mails do Firebase Auth (não há envio transacional neste repositório)
- Lista de frases do filtro/bot, logs e identificadores
