# Parte 4 — Voltar Android + links + prévia

Data: 2026-07-26

## Causa do botão Android fechar o app

1. `MainShell` não tinha `PopScope`/`WillPopScope`: com a shell na raiz,
   o gesto/botão `<` do Android fazia pop da única rota e encerrava o app.
2. Deep links de grupo usavam `pushAndRemoveUntil(..., false)` deixando
   `JoinGroupPage` / `GroupChatPage` como única rota; Voltar saía do app.
3. `JoinGroupPage._popOrExit` chamava `SystemNavigator.pop()` quando
   `canPop == false`.

A seta interna do AppBar não foi alterada.

## Comportamento final de navegação

1. Teclado aberto → fecha primeiro.
2. Diálogos/modais (rotas) → Flutter dá pop neles primeiro.
3. Aba ≠ Home → volta para Home (sem afetar presença).
4. Home → “Toque novamente para sair”; 2º toque ≤ 2s → sai.
5. Push/deep link → sempre `MainShell` sob o destino.

## Presença RTDB

`AndroidBackNavigation.shouldAffectPresenceOnInternalBack() == false`.
Voltar entre páginas/abas não chama `PresenceService.stop()` nem remove
conexões RTDB. Presença só sai nas condições da Parte 3.

## Prévia e cache

- Callable `fetchLinkPreview` (us-central1) — **não publicada nesta etapa**.
- Cache: `linkPreviewCache/{sha256}` TTL 7 dias; overwrite no miss/expiração.
- Rate limit: 20/min/UID (todas as chamadas) + 10 fetches/min por
  `(uid, url)` **somente em cache miss**. Sem limite global por URL
  (links populares / Amazon não são bloqueados injustamente).
- Cliente envia só texto; CF grava **somente** `linkPreview` +
  `linkPreviewStatus` (update transacional).
- Autorização: autor da mensagem + participante (DM) ou membro não banido
  (grupo); URL deve existir no texto; mensagem deleted/hidden rejeitada.
- Falha da prévia nunca impede o envio. Update não dispara push/unread
  (`onDocumentCreated` only).

## Proteções SSRF

Auth, https only, DNS + IPs privados/metadata, redirects ≤ 5 (Amazon short
links), timeout 5s,
max 512KB, HTML only, sanitização, sem cookies, imagem https opcional.

## Formato nos docs de mensagem

```
linkPreview: { url, title, description, domain, imageUrl, fetchedAt }
linkPreviewStatus: 'ready' | 'failed'
```

Somente Admin SDK. Cliente não pode criar/alterar esses campos (Rules).

## Deploy futuro (NÃO executar agora)

```bash
firebase deploy --only \
  firestore:rules,\
  functions:fetchLinkPreview \
  --project socialchatmvp
```

Não publicar Hosting, lojas, AAB/IPA.
