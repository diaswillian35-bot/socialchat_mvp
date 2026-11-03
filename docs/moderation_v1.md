# Moderação v1 (imagens, texto/links, denúncias)

Implementação no app `socialchatmvp` (este repositório). **Não foi feito deploy.** Não foi ativada a Cloud Vision API. Não foi criado alerta de orçamento no Billing. Build 37, Remdy Booth e o site remdy.app não foram alterados.

O painel admin vive em `Admin_Talksy_work` (codebase `admin-talksy`), que **não está neste workspace**. A especificação para implementar lá está na seção [Painel admin](#painel-admin).

## O que este PR faz

1. **Imagem** — function `moderateChatImage` (`onObjectFinalized`, região `northamerica-northeast1`, bucket `socialchatmvp.firebasestorage.app`). Paths `chat_images/**` e `groups/*/images/**`. Ignora o que não é `image/*` e ignora `quarantine/**` (o move não reentra). Uma chamada SafeSearch por `gs://`, sem baixar o arquivo.
   - `adult` ≥ LIKELY → bloqueia.
   - `racy` = VERY_LIKELY → bloqueia.
   - `racy` = LIKELY → `review` (o app mostra a imagem só para o remetente; os outros veem o balão "Imagem removida...").
   - Bloqueio: copia para `quarantine/{path}`, apaga o original, grava `moderation.status=blocked` e `imageUrl=''`, cria `reports` (`source: auto_vision`, `fromUid: system`) e soma `moderationStrikes/{uid}`.
   - Corrida upload/mensagem: `pendingModeration/{sha256 do path}` + `messageId` no metadata do Storage.
   - Falha da API: não bloqueia, marca `unchecked` e relança até 3 tentativas (`retry: true`).
2. **Texto** — `moderateMessageText` (DM) e `moderateGroupMessageText` (grupo), `onDocumentCreated`, mesma região. Porta o filtro para `functions/moderation/text_filter.js` (CSAM, violência sexual, ameaça dirigida, pornografia adulta e venda de conteúdo, URL inclusive "ponto com" e espaços). Domínios em `appConfig/moderation.blockedDomains` quando o campo existe; senão a lista embutida. Ao casar: `text=''`, `moderation.reason` = `text_adult` | `link_adult` | `csam`, strike e denúncia `source: auto_text`. O push e o `lastMessage` não levam o texto bloqueado.
3. **Cliente** — `lib/services/objectionable_content_filter.dart` devolve na hora a chave `content_filter_blocked`. Balões existentes (`_Bubble`, estilo de mensagem apagada) com `chat_image_blocked` e `chat_message_blocked`. Sem mudança de layout, cor ou fonte. Suspenso some das listas pelo mesmo filtro de conta inativa (`ModerationVisibility.isHiddenFromLists`).
4. **Denúncias** — `onReportCreated`. Enriquece `distinctReporterCount` e `priority` (`critical` se CSAM). O aviso ao admin sai de `functions/moderation/report_notice.js` (`sendOpsNoticeIfReady`), não de `ops_new_user_notify.js`. FCM para `appConfig/opsSettings.adminUids` ou, se vazio, `admins/{uid}` ativos. Corpo: `Nova denúncia · motivo: {reasonCode} · total: N`. Sem texto de mensagem e sem nome do denunciante. Denúncia de CSAM feita por usuário: prioridade crítica, cópia de preservação (sem apagar o original e sem apagar a mensagem), aviso ao admin, e o mesmo limite de 20 por dia. Sem suspensão automática. Suspensão imediata só quando a detecção é do sistema (`fromUid: system`). Strikes automáticos contam numa janela de 30 dias.
5. **Ação automática** — 3 denunciantes distintos em 30 dias (`appConfig/moderation.autoActionThreshold`), ou 1 denúncia CSAM, ou 3 strikes: `users/{uid}.moderation = {status:'suspended_pending_review', at}`. Não apaga a conta. Rules negam `create` de mensagem DM e de grupo. O campo `moderation` o cliente não altera.
6. **CSAM** — texto e path vão para `csamHolds/{reportId}` (cliente não lê). Imagem vai para `quarantine/` com `quarantineHolds.legalHold=true`. Não há exclusão automática. SafeSearch não detecta idade. Nenhum admin baixa o material por este PR (não há URL assinada aqui).

Fase 2 (perfil `users/**`, `events/*/photos/**`, `posts/**`) **não** foi implementada.

`appConfig/moderation.enabled=false` desliga as functions sem deploy. Documento ausente = ligado, com os defaults.

## Kill switch e config

Documento `appConfig/moderation` (só Admin SDK escreve; usuário logado pode ler):

```json
{
  "enabled": true,
  "adultBlockAt": "LIKELY",
  "racyBlockAt": "VERY_LIKELY",
  "racyReviewAt": "LIKELY",
  "autoActionThreshold": 3,
  "strikeThreshold": 3,
  "reportDailyLimit": 20,
  "blockedDomains": ["onlyfans.com", "pornhub.com"]
}
```

Se `blockedDomains` vier preenchido, **substitui** a lista embutida. Para acrescentar um domínio sem perder os outros, grave a lista completa.

`appConfig/opsSettings`: `{ "enabled": true, "adminUids": ["uidDoAdmin"] }`. Sem essa lista, cai nos docs `admins`.

## Comandos de deploy (não executar)

Codebase `default` em `firebase.json`. Região `northamerica-northeast1`. Sempre `--only`. Projeto `socialchatmvp`.

```bash
firebase deploy --only functions:default:moderateChatImage,functions:default:moderateMessageText,functions:default:moderateGroupMessageText,functions:default:onReportCreated,functions:default:onPrivateMessageCreated,functions:default:onGroupMessageCreated --project socialchatmvp
firebase deploy --only firestore:rules,storage --project socialchatmvp
```

Antes do deploy, confirme a região do bucket. O trigger `moderateChatImage` está em `northamerica-northeast1` e declara `socialchatmvp.firebasestorage.app`. Storage triggers só sobem se a região da function for a mesma do bucket. Não mude o bucket.

```bash
gcloud storage buckets describe gs://socialchatmvp.firebasestorage.app --format="value(location)"
```

Se o valor não for `northamerica-northeast1` (ou `NORTHAMERICA-NORTHEAST1`), pare. Não faça o deploy de `moderateChatImage` e não altere a localização do bucket sem o Willian. As functions de Firestore (`moderateMessageText`, `moderateGroupMessageText`, `onReportCreated`, `onPrivateMessageCreated`, `onGroupMessageCreated`) continuam em `northamerica-northeast1`, que já é a região do Firestore.

A Cloud Vision API e o alerta de orçamento no Billing continuam sendo ação do Willian no console. Este PR não ativa API e não cria alerta.

Backup sugerido antes do deploy: copiar `firestore.rules`, `storage.rules` e `functions/` para `~/Downloads/remdy_artifacts_backup/moderation_predeploy_<data>/`.

## Rollback (não executar)

```bash
# desligar sem deploy: appConfig/moderation.enabled = false

firebase functions:delete moderateChatImage moderateMessageText moderateGroupMessageText onReportCreated --region northamerica-northeast1 --project socialchatmvp

firebase deploy --only firestore:rules,storage --project socialchatmvp
# usando as rules do backup
```

Restaurar arquivos (dry-run por padrão; não roda daqui):

```bash
node functions/scripts/restore_quarantine.js
node functions/scripts/restore_quarantine.js --apply --messages messages.json
```

Objetos com `legalHold` (CSAM) são ignorados. O script não apaga a quarentena desses casos.

## Painel admin

Repositório `Admin_Talksy_work` (Flutter web, hosting target `admin`, functions codebase `admin-talksy`). Reutilizar a tela de denúncias de Locais (`listAdminPlaceReports` / `resolveAdminPlaceReport`). **Não implementado aqui.**

### Textos (5 idiomas)

| Chave | pt-BR | pt-PT | en | es | fr |
|---|---|---|---|---|---|
| título | Denúncias | Denúncias | Reports | Denuncias | Signalements |
| filtro abertas | Abertas | Abertas | Open | Abiertas | Ouvertes |
| críticas | Críticas | Críticas | Critical | Críticas | Critiques |
| resolvidas | Resolvidas | Resolvidas | Resolved | Resueltas | Résolus |
| descartar | Descartar | Descartar | Dismiss | Descartar | Ignorer |
| remover | Remover conteúdo | Remover conteúdo | Remove content | Eliminar contenido | Supprimer le contenu |
| suspender | Suspender | Suspender | Suspend | Suspender | Suspendre |
| banir | Banir | Banir | Ban | Banear | Bannir |
| reverter | Reverter suspensão | Reverter suspensão | Revert suspension | Revertir suspensión | Annuler la suspension |

### Lista

Filtros: abertas / críticas / resolvidas. Colunas: motivo (`reasonCode`), `distinctReporterCount`, data, `reportedUid`, contexto (`contextType`, `conversationId` ou `groupId`, `messageId`). Sem nome do denunciante e sem texto da mensagem na lista.

Imagem em quarentena: URL assinada de 5 minutos, gerada na callable, nunca pública. **CSAM (`priority=critical` ou `csamHolds`): não gerar URL, não mostrar miniatura, não oferecer download.** O Jurídico ainda precisa definir denúncia obrigatória (NCMEC / Cybertip.ca / SaferNet), prazo e quem acessa a evidência. Até lá a quarentena só preserva.

### Callables (codebase `admin-talksy`, região `northamerica-northeast1`)

As três exigem admin de verdade: documento `admins/{uid}` com `isActive != false`. Claim forjado no token ou `users.isAdmin` escrito pelo cliente não bastam (o cliente não escreve `admins`). Cada ação grava `moderationAudit/{autoId}`: `{actorUid, action, reportId, targetUid, at}` sem texto e sem URL.

- `adminListReports({ status, priority, limit })`  
  Lê `reports`. Para item não CSAM com `pathHash`, devolve `signedUrl` (5 min) do objeto `quarantine/...` se existir. Não admin: `permission-denied`.
- `adminResolveReport({ reportId, action })`  
  `action`: `dismiss` | `remove_content` | `suspend` | `ban` | `revert_suspension`.  
  - `dismiss`: `reports.status=dismissed`.  
  - `remove_content`: apaga texto/`imageUrl` da mensagem do contexto e, se houver arquivo, move para `quarantine/` (CSAM: move e marca `legalHold`, não apaga a cópia).  
  - `suspend`: `users/{reportedUid}.moderation.status=suspended_pending_review`.  
  - `ban`: `moderation.status=banned` (também bloqueia create de mensagem e some das listas). Não apaga a conta.  
  - `revert_suspension`: remove `moderation` se o status for `suspended_pending_review` ou `banned`.  
  Em todos, `reports.status=resolved` exceto `revert_suspension`, que pode deixar o report `resolved` com `resolution=reverted`.
- `adminSetUserModeration({ uid, status })`  
  `status`: `suspended_pending_review` | `banned` | `clear`. Mesma escrita de `users.moderation` e auditoria. Não admin: `permission-denied`.

## CSAM — ponto aberto (Jurídico)

Exploração sexual infantil pode exigir denúncia e preservação (EUA: NCMEC CyberTipline, 18 U.S.C. §2258A; Canadá: denúncia obrigatória via Cybertip.ca/RCMP; Brasil: ECA / SaferNet / PF). Antes do deploy o Jurídico define quem denuncia, o prazo, por quanto tempo preservar, quem acessa e se haverá hash-matching (PhotoDNA). Até lá: quarentena preservada, aviso crítico ao admin, sem download no painel. SafeSearch não detecta idade.

## Como testar

Unitário (sem deploy, sem API):

```bash
cd functions && npm test
cd .. && flutter test test/objectionable_content_filter_test.dart test/moderation_l10n_test.dart
```

Regras (emulador Firestore na porta 8080):

```bash
cd firestore-tests && npm run test:moderation
```

O emulador cobre: mensagem normal passa; `moderation.status=suspended_pending_review` nega create em DM e grupo; cliente não lê `moderationStrikes`, `moderationAudit`, `pendingModeration`, `csamHolds`; cliente lê `appConfig/moderation` e não escreve.

Critérios que dependem de staging (depois da aprovação do Willian, não neste PR):

1. Imagem adulta em `chat_images/` → em até 15 s vai para `quarantine/`; mensagem `moderation.status==blocked`; os dois lados veem "Imagem removida..." nos 5 idiomas.
2. Imagem normal não muda; 1 chamada Vision.
3. Vision com falha (mock) → `unchecked` e retry, sem bloqueio.
4. `onlyfans.com/x` ou termo adulto → texto vazio e balão "Mensagem removida..."; "vou matar a fome", "sexta-feira", "Essex", "documento.pdf" passam.
5. Denúncia → push ao admin em até 30 s, sem conteúdo sensível.
6. 3 denunciantes distintos ou 1 CSAM → `suspended_pending_review`, some das listas, create negado.
7. Painel (outro repo): lista, ações em `moderationAudit`, não admin recebe `permission-denied`.
8. Logs do emulador/functions: `grep` sem URL, sem texto, sem e-mail, sem token. O logger só aceita ids e a decisão (`functions/moderation/safe_log.js`).

Logs esperados (exemplo): `{"event":"moderation_block","decision":"blocked","reason":"link_adult","uid":"...","messageId":"...","conversationId":"..."}`.
