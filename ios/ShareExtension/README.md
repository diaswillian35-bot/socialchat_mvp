# Share Extension (iOS)

**Status:** target `ShareExtension` embutido em `Runner.app/PlugIns` (Debug, Profile e Release).
`ShareExtensionSessionService.enabledForLaunch = true`.

Visual: tela sempre clara (branco + navy/azul/verde Remdy), logo oficial, envio ao tocar no destino.

Sessão:
- Keychain Access Group `CZN2YMTU7B.com.remdy.app.share`
- App Group `group.com.remdy.app` (espelho da sessão + inbox de imagens)

Fluxo:
- Texto / link HTTPS: envio imediato via Callables (`listShareDestinations` / `sendShareMessage`).
- Imagens: JPEGs no App Group; o Runner envia ao voltar ao foreground (sem abrir o host por API privada).

Não abrir o aplicativo principal a partir da extensão.
