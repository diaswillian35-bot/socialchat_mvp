# Deploy B44 — lista única (nada foi implantado)

Trabalho local na tip `feat/b44-selo-desconto` @ `7e3fa48` (worktree `/Volumes/REMDY_SSD/b44_selo_desconto`), que já inclui `feat/b44-traducao-locais` (`1f1b181`) e `feat/b44-erros-auth` (`3ebd8c7`).
**Não implantar, fazer push nem gravar em produção sem aprovação explícita do Willian.**

Esta lista consolida o que ficou pendente de deploy nesta linha da build 44 (i18n do servidor, geo, tradução de lugares, Share Extension, Excluir local, selo de desconto) e, na secção 8, o que **faltava**: a segurança b44 (rules + Functions novas) e o hosting do painel admin.

A ordem completa, o comando único, as verificações, o rollback e os itens que precisam de OK estão em `LANCAMENTO_B44.md`. Nada disto foi executado.

## 1) 15 pushes e avisos (i18n)

```
firebase deploy --only functions:onGroupMessageCreated,functions:onPrivateMessageCreated,functions:onEventUpdated,functions:onGroupJoinRequestCreated,functions:onGroupJoinRequestUpdated,functions:approveGroupJoinRequest,functions:rejectGroupJoinRequest,functions:createEventComment,functions:onAudioRoomOpened,functions:onReportCreated,functions:submitPlaceReview,functions:replyPlaceReview,functions:onPlaceModerated,functions:onPlacePendingNotifyAdmins,functions:onPublicUserInterestsWritten
```

## 2) 27 callables (i18n: `details.i18nKey`, a `message` não muda)

```
firebase deploy --only functions:confirmAdultAge,functions:deleteMyAccount,functions:createGroup,functions:updateGroupSettings,functions:joinGroupByInviteCode,functions:joinOpenGroup,functions:leaveGroup,functions:deleteGroup,functions:banGroupMember,functions:unbanGroupMember,functions:promoteGroupAdmin,functions:demoteGroupAdmin,functions:removeGroupMember,functions:createEvent,functions:updateEvent,functions:cancelEvent,functions:joinEvent,functions:leaveEvent,functions:sendDmMessage,functions:forwardMessage,functions:searchUsers,functions:submitPlace,functions:updateMyPlace,functions:moderatePlace,functions:askRemi,functions:audioRoomAction,functions:setGroupAudioRoom
```

Outros callables no mesmo estilo (helper i18n). A lista abaixo substitui o “etc.” anterior; inclui `revokeVerification`, que estava só implícito:

```
firebase deploy --only functions:applyInviteCode,functions:claimInvitePremiumReward,functions:fetchLinkPreview,functions:issueShareExtensionSession,functions:revokeShareExtensionSessions,functions:translatePlaceDescription,functions:claimPlaceForAccount,functions:listPlaceReviews,functions:transferGroupOwnership,functions:markGroupAsRead,functions:exportEventParticipants,functions:toggleEventLike,functions:toggleEventCommentLike,functions:deleteEventComment,functions:registerEventView,functions:archiveEvent,functions:restoreEvent,functions:duplicateEvent,functions:deleteEventPermanently,functions:abortIncompleteEvent,functions:approveEventPendingChanges,functions:rejectEventPendingChanges,functions:syncRevenueCatEntitlement,functions:markPhoneVerified,functions:unlinkVerifiedPhone,functions:revokeVerification
```

`listShareDestinations` e `sendShareMessage` também tocada no helper; o deploy delas é o da secção 5 (levam também a regra nova de destinos). Callables de lugares `getMyPlace`, `listMyPlaces` e `listPendingPlaces` não estavam nesta lista: só entram se se quiser o mesmo `details.i18nKey` nesses erros (opcional).

## 3) Geo de grupos

Já incluídos na lista dos 27: `createGroup`, `updateGroupSettings`.

Índices Firestore (4, coleção `groups`) — implantar com `firebase deploy --only firestore:indexes` quando for aprovado (os 4 já estão em `firestore.indexes.json`):

- `deleted`, `countryCode`, `scope`, `cityKey`, `updatedAt`
- `deleted`, `countryCode`, `scope`, `regionCenterGeohash`, `updatedAt`
- `deleted`, `countryCode`, `geohash3`, `updatedAt`
- `deleted`, `countryCode`, `stateKey`, `updatedAt`

Backfill (script, não é Function): `functions/scripts/backfill_group_geo_state.js` (dry-run é o padrão; `--execute` só com aprovação). Rollback: `node scripts/backfill_group_geo_state.js --rollback DIR/antes_<ts>.json`.

## 4) Tradução de lugares

- Function: `onPlaceDescriptionApproved` (grava `descriptionI18n` e o espelho no cache que a página `/l/` já lê). `renderPublicPlacePage` **não mudou** neste passo; só reimplantar se a verificação pós-deploy mostrar a `/l/` sem a tradução.
- Variáveis: `PLACE_DESCRIPTION_TRANSLATION_ENABLED=true` (kill switch; sem isto a Function não traduz). O ficheiro `.env.socialchatmvp` é referido nesta lista, mas **não está** no worktree `b44_selo_desconto` — confirmar no projeto Firebase antes do deploy (não commitar segredos).
- Backfill (faltava nesta lista): `functions/scripts/backfill_place_description_i18n.js` (dry-run padrão, não chama a API). Execução real, só com OK: `PLACE_DESCRIPTION_TRANSLATION_ENABLED=true node scripts/backfill_place_description_i18n.js --execute --out DIR`. Tem custo de API. Rollback: `node scripts/backfill_place_description_i18n.js --rollback DIR/antes_<ts>.json` (os contadores de uso não voltam).

```
firebase deploy --only functions:onPlaceDescriptionApproved
```

## 5) Share Extension (lista + envio)

Estas duas mudaram de comportamento (membros de grupos em comum, busca por nome, criação de DM, regra de país BR/CA/PT + Premium):

```
firebase deploy --only functions:listShareDestinations,functions:sendShareMessage
```

Estão em `functions/share_extension.js` (junto de `issueShareExtensionSession` e `revokeShareExtensionSessions`, que não mudaram de regra).

## 6) Excluir local

Nova callable de exclusão lógica (`deleted: true`, `active: false`, `deletedAt`, `deletedBy`). Dono ou admin total. Idempotente. As Rules de `places` **não mudam** (`create`/`update`/`delete: if false`; a exclusão passa só pela Function).

A correr no repositório da app (`/Volumes/REMDY_SSD/b44_selo_desconto`, projeto `socialchatmvp`, codebase `default`):

```
firebase deploy --only functions:deletePlace
```

O painel web admin (repositório `/Volumes/REMDY_SSD/admin_qr_work`, branch `feat/b44-excluir-local` @ `96e1d23`) altera `moderateAdminPlace` (ação `delete`). Esse deploy é do **mesmo projeto** `socialchatmvp`, mas da codebase **`admin-talksy`**, e tem de ser lançado **a partir da pasta do painel** (não da pasta da app). O hosting do painel (target `admin` → site `remdy-admin`, `public: build/web`) também estava em falta nesta lista:

```
cd /Volumes/REMDY_SSD/admin_qr_work
# confirmar branch e commit:
# git rev-parse --short HEAD   # deve ser 96e1d23
# TMPDIR no SSD; Flutter em /Users/macbookairm1/Downloads/flutter/bin
flutter build web --release
firebase deploy --only functions:moderateAdminPlace,hosting:admin --project socialchatmvp
```

A parceria do selo de desconto **não** foi adicionada ao painel (passo futuro, com OK novo).

## 7) Selo de desconto — SEM OK

Quatro callables novas (escrita de códigos só no Admin SDK; o cliente só lê `places/{id}.discount`, já público). As Rules de `places` **não mudam** (`create`/`update`/`delete: if false`). Subcoleções `discountCodes`, `discountOpen` e `discountRedemptions` não têm regra nova: o cliente não acessa (deny por omissão); só as Functions (Admin SDK). Sem índice composto novo (gets por id de documento). Sem migração. Grátis no lançamento (sem gate Premium).

```
firebase deploy --only functions:setPlaceDiscount,functions:setPlacePartnershipDiscount,functions:issuePlaceDiscountCode,functions:redeemPlaceDiscount
```

O painel web admin (`/Volumes/REMDY_SSD/admin_qr_work`) **não foi alterado** para o selo. Se no futuro a parceria também for configurada lá, isso é um passo separado, com OK novo.

## 8) Segurança b44 — estava em falta nesta lista (SEM OK)

A linha da build 44 inclui, desde `089e9a7`, trabalho de segurança que **não estava** nas secções 1–7: bloquear PV, “sem falar”, selo verificado por SMS, bot do grupo, filtro de fotos/texto alargado, punição em degraus.

**Rules** (`firestore.rules`, +40/−3 relativamente à loja 1.0.9 @ `135d943`): `userDmBlocked` / `dmAllowExisting`; o cliente não escreve `verification`/`verified`; `senderModerationBlocksSend` passa a honrar `moderation.status == muted` até `mutedUntil`; coleção `verificationPhones` só Admin SDK. As Rules de `places` não entram neste diff. Implantar só com OK explícito — as regras passam a valer também para as versões antigas da app que ainda estão nas lojas.

```
firebase deploy --only firestore:rules
```

**Functions novas / gatilhos desta frente** (não apareciam nas secções 1–7):

```
firebase deploy --only functions:markPhoneVerified,functions:unlinkVerifiedPhone,functions:revokeVerification,functions:onUserVerificationGuard,functions:adjustModeration,functions:updateGroupModBot,functions:onGroupMembersWelcomeBot,functions:moderateChatImage,functions:moderateMessageText,functions:moderateGroupMessageText
```

(`markPhoneVerified`, `unlinkVerifiedPhone` e `revokeVerification` também estão no comando da secção 2; repetir no comando único não faz mal.)

Muitas Functions das secções 1–2 e 5 (`sendDmMessage`, `forwardMessage`, `sendShareMessage`, `deleteMyAccount`, `onReportCreated`, etc.), se implantadas a partir desta tip, já levam o código de segurança. `functions/moderation/word_lists.json` está marcado no commit como **RASCUNHO até revisão** — precisa de OK do Willian antes de o filtro de insultos ir para produção.

## Notas

- O app local já grava `users/{uid}.appLanguageCode`. Os pushes só passam a honrar o idioma depois do deploy da secção 1.
- Hosting da app (`/l/` já estava nos 5 idiomas e não mudou neste passo). Portal-login e convite (`public/portal-login/index.html`, `public/invite/index.html`) só entram com um deploy de hosting da app, se for aprovado, a correr na pasta da app:

```
firebase deploy --only hosting:app --project socialchatmvp
```

  Isto publica tudo o que está em `public/` no site `socialchatmvp`. O site de marketing (`landing/`, `public/index.html`) ficou de fora de propósito neste trabalho — rever o conteúdo de `public/` antes de aprovar este passo.
- Inventário de textos do servidor: `TEXTOS_SERVIDOR.md`.
- Checklist de lançamento (merge, ordem, lojas, textos, testes, OKs): `LANCAMENTO_B44.md`.
