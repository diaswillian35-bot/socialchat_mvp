# Deep links Remdy — AASA / App Links (fonte de verdade local)

## Problema corrigido (2026-09-06)
AASA em produção usava `paths: ["/*"]` e o Android claimava o host inteiro.
Resultado: `https://remdy.app` abria o app e o `pending_group_code` antigo
podia reabrir / auto-processar o último grupo.

## Paths permitidos (app)
- `/g/*` — convite de grupo (prévia; join só no toque)
- `/e/*`, `/events/*`, `/event/*` — evento no app
- `/invite`, `/invite/*` — convite Premium
- `/group`, `/group/*` — legado
- `/portal-login`, `/portal-login/*` — QR portal

## Paths que DEVEM ficar no browser
- `/` — landing
- `/eventos`, `/eventos/**` — listagem pública
- páginas legais (`/privacidade`, `/termos`, …)

## Arquivos
- `public/.well-known/apple-app-site-association`
- `public/apple-app-site-association` (fallback Apple)
- `public/.well-known/assetlinks.json`
- `android/.../AndroidManifest.xml` — pathPrefix por rota
- `lib/services/remdy_deep_link_parser.dart`

## Publicação
Hosting (AASA + assetlinks + `/g` OG) + novo build iOS/Android.
iOS pode levar até ~24h para refrescar AASA (ou reinstalar o app).
