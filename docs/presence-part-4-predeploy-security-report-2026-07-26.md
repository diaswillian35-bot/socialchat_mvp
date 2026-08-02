# Parte 4 — Relatório final pré-deploy (segurança + testes)

Data: 2026-07-26  
Projeto: `socialchatmvp`  
**Deploy: NÃO executado**

## Checklist (1–12)

| # | Requisito | Status | Evidência |
|---|-----------|--------|-----------|
| 1 | Prévia só em mensagem do próprio usuário | OK | `isMessageAuthoredBy` + `permission-denied` se `senderId`/`fromUid` ≠ caller |
| 2 | Chat privado: pertence à conversa | OK | `participants`/`members` includes uid |
| 3 | Grupo: membro e não banido | OK | membership + `bannedUsers/{uid}.isActive !== true` |
| 4 | URL existe exatamente no texto | OK | `urlAppearsInMessageText` após normalização https |
| 5 | Só altera `linkPreview` + `linkPreviewStatus` | OK | `tx.update` com patch de 1–2 campos |
| 6 | Não altera texto/remetente/horário/reply/unread | OK | teste unitário “outros campos intactos” |
| 7 | Update não gera push/unread/nova msg | OK | push em `onDocumentCreated` only; update não cria doc |
| 8 | Apagada/ocultada sem prévia | OK | `deleted` / `hiddenFor` / `deletedFor` → `failed-precondition` |
| 9 | Cache/rateLimit/metadados não pelo cliente | OK | Rules deny `linkPreviewCache`, `_rateLimits`, create/update preview fields |
| 10 | Links encurtados / redirects Amazon | OK | testes `amzn.to` e `a.co`; `MAX_REDIRECTS = 5` |
| 11 | URLs populares sem bloqueio global | OK | removido limite global por URL; 40 uids no mesmo Amazon URL via cache |
| 12 | Reexecução de testes | OK | ver resultados abaixo |

## Correções feitas nesta revisão

1. **`messagePath` obrigatório** — sem path, a Function não busca/anexa.
2. **Autoria** — só o remetente da mensagem pode anexar prévia.
3. **Ban em grupo** — checagem de `groups/{gid}/bannedUsers/{uid}.isActive`.
4. **URL no texto** — rejeita URL que não aparece na mensagem.
5. **Deleted/hidden** — rejeita antes do fetch; write revalida em transaction.
6. **Write mínimo** — `update` só dos dois campos de prévia (não `set` merge amplo).
7. **Rate limit** — removido `linkPreviewUrl_{hash}` global; cache hit não conta fetch; limite de fetch por `(uid,url)` no miss.
8. **Redirects** — `MAX_REDIRECTS` 3 → 5 para cadeias Amazon.

Arquivos: `functions/link_preview.js`, `functions/link_preview_logic.js`,
`firestore-tests/link_preview_unit.test.js`,
`firestore-tests/link_preview_rules.test.js` (novo),
`firestore-tests/package.json`, docs Part 4.

## Resultados dos testes

| Suite | Resultado |
|-------|-----------|
| Dart `test/part4_android_back_and_links_test.dart` | **20/20** pass |
| Node `npm run test:unit` (presence + link preview) | **71/71** pass |
| Firestore Rules emulator (`npm test` em firestore-tests) | **32/32** pass (incl. 7 link-preview) |
| `flutter analyze` (9 arquivos Part 4) | **No issues found** |

## Deploy (quando autorizado)

```bash
firebase deploy --only firestore:rules,functions:fetchLinkPreview --project socialchatmvp
```

Não executar até confirmação explícita.
