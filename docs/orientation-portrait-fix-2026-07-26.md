# Correção — tela vermelha ao girar (orientação)

Data: 2026-07-26  
Dispositivo: Android `R38M30CCS1T`  
Deploy / lojas: **não**

## 1. Causa exata

Ao girar para landscape, a Home remonta widgets do `ListView` e um
`StreamBuilder` escuta de novo um stream **single-subscription** de
`PresenceWatch.watchCountryOnlineCount`.

```
StateError: Bad state: Stream has already been listened to.
```

Tipo: **reconstrução de estado / stream** (não RenderFlex overflow,
não MediaQuery infinito, não SafeArea/teclado).

## 2–3. Tela / widget / arquivo

| Item | Valor |
|------|--------|
| Tela | Home (`HomePage`) |
| Widget | `Container` (card “ao vivo”) → `StreamBuilder` do contador do país |
| Arquivo:linha | `lib/pages/home_page.dart:648` (Container); stream em `:684–685` |
| Cascata | `Each child must be laid out exactly once` + `Duplicate GlobalKey` |

## 4. Orientação final

Somente `DeviceOrientation.portraitUp` (sem `portraitDown`, para câmera/fotos).

## 5. Arquivos alterados

| Arquivo | Mudança |
|---------|---------|
| `lib/services/app_orientation.dart` | **novo** — lista + `lockToPortraitUp()` |
| `lib/main.dart` | lock após Firebase, antes de `runApp` |
| `android/.../AndroidManifest.xml` | `android:screenOrientation="portrait"` |
| `ios/Runner/Info.plist` | iPhone já portrait; comentário iPad inalterado |
| `lib/services/presence_watch.dart` | `watchCountryOnlineCount` → broadcast (defesa) |
| `test/app_orientation_test.dart` | **novo** |

## 6. Testes

- `flutter analyze` (arquivos alterados): **sem issues**
- `app_orientation` + `firebase_bootstrap` + Part4 back/links: **26/26**

## 7. Aparelho

- Cold start: Home + `PresenceService` OK; sem `duplicate-app`
- Hot restart: OK; presença reinicia
- Fechar/reabrir: OK
- Forçar rotação do sistema: app permanece vertical; **sem** `EXCEPTION CAUGHT` / stream error

## 8. Firebase / presença

Bootstrap idempotente preservado (`ensureFirebaseInitialized` → orientação →
`runApp`). Presença RTDB continua criando conexão após start/restart.

## 9. Pendências

- iPad ainda permite landscape no `Info.plist` (documentado; sem mudança nesta versão)
- Validação manual residual: câmera/áudio/chat/grupo após o lock (não exercitada ponta a ponta aqui)
- Overflow de layouts em landscape (se um dia liberar landscape) permanece fora de escopo
