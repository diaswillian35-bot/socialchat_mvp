# Parte 4 — Relatório de deploy (socialchatmvp)

Data: 2026-07-26  
Projeto: `socialchatmvp`  
Operador CLI: `diaswillian35@gmail.com`

## Comando executado

```bash
firebase deploy --only firestore:rules,functions:fetchLinkPreview --project socialchatmvp
```

**Resultado:** `Deploy complete!` (exit 0), ~84 s.

## O que foi publicado

| Artefato | Ação | Detalhe |
|----------|------|---------|
| `firestore.rules` | released | Regras com bloqueio de `linkPreview`/`linkPreviewStatus` no cliente + deny em `linkPreviewCache` e `_rateLimits` |
| `fetchLinkPreview` | **created** | Gen 2, Node.js 24, callable, **us-central1**, 256 MiB |

## Escopo — o que NÃO foi alterado

Confirmado pelo log do deploy e pela lista de Functions:

- Nenhuma outra Function criada/atualizada (apenas `Successful create` de `fetchLinkPreview`)
- Sem Hosting
- Sem RTDB Rules / Database
- Sem Storage Rules
- Sem publicação de índices Firestore (o CLI só leu `firestore.indexes.json`; não houve release de indexes)
- Sem AAB / IPA / publicação em lojas

## Verificação da Function

| Check | Resultado |
|-------|-----------|
| Listada em `firebase functions:list` | `fetchLinkPreview` \| v2 \| callable \| **us-central1** \| nodejs24 |
| Estado no audit log pós-create | `state: ACTIVE`, `environment: GEN_2` |
| URL callable | `https://us-central1-socialchatmvp.cloudfunctions.net/fetchLinkPreview` |
| Cloud Run URI | `https://fetchlinkpreview-6o5ndgsibq-uc.a.run.app` |

## Smoke tests (produção)

### 1. Não autenticado

- `POST` callable sem token → **HTTP 401**  
  `{"error":{"message":"Login required.","status":"UNAUTHENTICATED"}}`
- SDK `httpsCallable` sem login → `functions/unauthenticated`

### 2. Autenticado + mensagem real com Amazon

- Dois usuários anônimos temporários, conversa DM, mensagem com  
  `https://www.amazon.com/dp/B09V3KXJPB`
- Callable retornou `status: "ready"`, `cached: false`, `domain: "www.amazon.com"`
- Log da Function: `link_preview_fetch_ok` host `www.amazon.com` status 200
- Documento da mensagem: `linkPreviewStatus: "ready"`, `linkPreview` presente
- Texto e `senderId` **inalterados** após a prévia
- Título OG vazio (comum quando Amazon não devolve metadados ao bot) — prévia/status gravados mesmo assim

### 3. Cliente comum não escreve campos server-only

| Tentativa | Resultado |
|-----------|-----------|
| `update` de `linkPreview` / `linkPreviewStatus` na mensagem | `permission-denied` |
| `set` em `linkPreviewCache/smoke_forged` | `permission-denied` |
| `set` em `_rateLimits/linkPreview_{uid}` | `permission-denied` |

### 4. Lojas / builds

- Nenhum `flutter build appbundle` / `ipa` executado nesta sessão.

### Limpeza

Docs temporários de smoke (`conversations/smoke_lp_*`, `smoke_diag_*` e
perfis anônimos associados) podem ter ficado se a exclusão cliente falhou
(rules). São inofensivos; podem ser apagados manualmente no Console se
desejado.

## Avisos do deploy (pré-existentes)

- Warnings de Rules unused (variáveis/funções) — compilação OK
- Aviso de `firebase-functions` desatualizado no `package.json`
- Aviso cross-region em Functions **já existentes** de mensagem/evento (não republicadas)

## Conclusão

Parte 4 publicada com sucesso no escopo autorizado. `fetchLinkPreview` está **ACTIVE** em **us-central1**. Smoke auth/unauth, Rules client-side e mensagem Amazon passaram. Pronto para uso pelo app; **sem nova versão de loja**.
