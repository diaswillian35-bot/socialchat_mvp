# Deploy B44 — lista única (nada foi implantado)

Trabalho local na branch `feat/b44-erros-auth` (worktree `/Volumes/REMDY_SSD/b44_erros_auth`).
**Não implantar, fazer push nem gravar em produção sem aprovação explícita do Willian.**

Esta lista consolida tudo o que ficou pendente de deploy nesta branch (i18n do servidor, geo, tradução de lugares e Share Extension).

## 1) 15 pushes e avisos (i18n)

```
firebase deploy --only functions:onGroupMessageCreated,functions:onPrivateMessageCreated,functions:onEventUpdated,functions:onGroupJoinRequestCreated,functions:onGroupJoinRequestUpdated,functions:approveGroupJoinRequest,functions:rejectGroupJoinRequest,functions:createEventComment,functions:onAudioRoomOpened,functions:onReportCreated,functions:submitPlaceReview,functions:replyPlaceReview,functions:onPlaceModerated,functions:onPlacePendingNotifyAdmins,functions:onPublicUserInterestsWritten
```

## 2) 27 callables (i18n: `details.i18nKey`, a `message` não muda)

```
firebase deploy --only functions:confirmAdultAge,functions:deleteMyAccount,functions:createGroup,functions:updateGroupSettings,functions:joinGroupByInviteCode,functions:joinOpenGroup,functions:leaveGroup,functions:deleteGroup,functions:banGroupMember,functions:unbanGroupMember,functions:promoteGroupAdmin,functions:demoteGroupAdmin,functions:removeGroupMember,functions:createEvent,functions:updateEvent,functions:cancelEvent,functions:joinEvent,functions:leaveEvent,functions:sendDmMessage,functions:forwardMessage,functions:searchUsers,functions:submitPlace,functions:updateMyPlace,functions:moderatePlace,functions:askRemi,functions:audioRoomAction,functions:setGroupAudioRoom
```

Outros callables no mesmo estilo (helper i18n): `applyInviteCode`, `claimInvitePremiumReward`, `fetchLinkPreview`, `issueShareExtensionSession`, `revokeShareExtensionSessions`, `translatePlaceDescription`, `claimPlaceForAccount`, `listPlaceReviews`, `transferGroupOwnership`, `markGroupAsRead`, `exportEventParticipants`, `toggleEventLike`, `toggleEventCommentLike`, `deleteEventComment`, `registerEventView`, `archiveEvent`, `restoreEvent`, `duplicateEvent`, `deleteEventPermanently`, `abortIncompleteEvent`, `approveEventPendingChanges`, `rejectEventPendingChanges`, `syncRevenueCatEntitlement`, e as de presença/verificação (`markPhoneVerified`, `unlinkVerifiedPhone`, etc.).

## 3) Geo de grupos

Já incluídos na lista dos 27: `createGroup`, `updateGroupSettings`.

Índices Firestore (4, coleção `groups`) — implantar com `firebase deploy --only firestore:indexes` quando for aprovado:

- `deleted`, `countryCode`, `scope`, `cityKey`, `updatedAt`
- `deleted`, `countryCode`, `scope`, `regionCenterGeohash`, `updatedAt`
- `deleted`, `countryCode`, `geohash3`, `updatedAt`
- `deleted`, `countryCode`, `stateKey`, `updatedAt`

Backfill (script, não é Function): `functions/scripts/backfill_group_geo_state.js` (só com aprovação).

## 4) Tradução de lugares

- Function: `onPlaceDescriptionApproved`
- Variáveis: `.env.socialchatmvp` (não commitar segredos)

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

```
firebase deploy --only functions:deletePlace
```

O painel web admin (repositório `/Volumes/REMDY_SSD/admin_qr_work`, branch `feat/b44-excluir-local`) altera `moderateAdminPlace` (ação `delete`). Esse deploy é do projeto/Functions do painel, e o hosting do painel, quando for aprovado:

```
firebase deploy --only functions:moderateAdminPlace
```


## 7) Selo de desconto — SEM OK

Quatro callables novas (exclusão lógica de códigos só no Admin SDK; o cliente só lê `places/{id}.discount`, já público). As Rules de `places` **não mudam** (`create`/`update`/`delete: if false`). Subcoleções `discountCodes`, `discountOpen` e `discountRedemptions` não têm regra nova: o cliente não acessa (deny por omissão); só as Functions (Admin SDK). Sem índice composto novo (gets por id de documento). Sem migração. Grátis no lançamento (sem gate Premium).

```
firebase deploy --only functions:setPlaceDiscount,functions:setPlacePartnershipDiscount,functions:issuePlaceDiscountCode,functions:redeemPlaceDiscount
```

O painel web admin (`/Volumes/REMDY_SSD/admin_qr_work`) **não foi alterado**. Se no futuro a parceria também for configurada lá, isso é um passo separado, com OK novo.

## Notas

- O app local já grava `users/{uid}.appLanguageCode`. Os pushes só passam a honrar o idioma depois do deploy da secção 1.
- Hosting (`/l/`, portal-login, convite) só entra com um deploy de hosting futuro, se for aprovado.
- Inventário de textos do servidor: `TEXTOS_SERVIDOR.md`.
