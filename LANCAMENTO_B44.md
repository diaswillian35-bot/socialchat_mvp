# Lançamento da build 44 — checklist

**Nada neste documento foi executado.** Merge, push, deploy, backfill, build de loja, envio às lojas e instalação no iPhone ficam todos à espera de OK explícito do Willian.

Fonte da app: branch `feat/b44-selo-desconto` @ `7e3fa48`  
Worktree: `/Volumes/REMDY_SSD/b44_selo_desconto`  
Painel admin: `/Volumes/REMDY_SSD/admin_qr_work`, branch `feat/b44-excluir-local` @ `96e1d23`  
Projeto Firebase: `socialchatmvp` (região das Functions: `us-central1`)  
Versão de loja proposta: **1.0.10**, build number sugerido **52** (maior do que a build de teste 51; a 51 ficou como IPA de teste do botão Gerenciar meus locais)

A lista de Functions e os comandos soltos também estão em `DEPLOY_B44.md` (atualizado nesta revisão). Este ficheiro é o procedimento único de lançamento.

---

## 1) Ordem de merge das branches b44 e push — SEM OK

A história já é linear (fast-forward):

1. `feat/b44-traducao-locais` @ `1f1b181`
2. `feat/b44-erros-auth` @ `3ebd8c7` (contém a anterior; não há commits só em `traducao-locais`)
3. `feat/b44-selo-desconto` @ `7e3fa48` (um commit em cima de `erros-auth`)

`master` local e `origin/master` estão em `b585253` e são ancestrais desta tip (113 commits à frente, 0 no sentido contrário). Um `git merge --ff-only feat/b44-selo-desconto` em `master` inclui as três branches. Mesmo assim, a ordem pedida é esta:

```
# NÃO EXECUTAR sem OK. Não fazer checkout de uma branch que já está
# noutro worktree. Usar um worktree livre ou criar um temporário no SSD.
cd /Volumes/REMDY_SSD/b44_selo_desconto   # ou worktree de master, se existir

# 1. Garantir que as três branches apontam para os commits acima
git rev-parse --short feat/b44-traducao-locais   # 1f1b181
git rev-parse --short feat/b44-erros-auth        # 3ebd8c7
git rev-parse --short feat/b44-selo-desconto     # 7e3fa48

# 2. Atualizar master por fast-forward (inclui as três)
git checkout master
git merge --ff-only feat/b44-traducao-locais
git merge --ff-only feat/b44-erros-auth
git merge --ff-only feat/b44-selo-desconto
git rev-parse --short HEAD   # deve ficar 7e3fa48

# 3. Push — SEM OK. Só depois de o Willian autorizar, e só o que ele autorizar:
# git push origin feat/b44-traducao-locais feat/b44-erros-auth feat/b44-selo-desconto
# git push origin master
```

Painel admin (repositório separado, também SEM OK):

```
cd /Volumes/REMDY_SSD/admin_qr_work
git rev-parse --short HEAD   # 96e1d23
# git push origin feat/b44-excluir-local
```

Não há merge do painel no repositório da app. Não apagar worktrees nem ficheiros do disco interno.

---

## 2) Deploy único completo — SEM OK

**Ordem (Functions e backend antes do app chegar às lojas):**

1. Confirmar tip `7e3fa48` na pasta da app e `96e1d23` no painel. Confirmar o kill switch e as credenciais da tradução (ver secção 2.4).
2. `firestore:indexes` (geo). Esperar até os 4 índices novos estarem **Enabled** na consola (pode demorar vários minutos). Não avançar o backfill geo antes disso.
3. `firestore:rules` (segurança b44) — só com OK próprio; altera o comportamento das versões já nas lojas.
4. **Todas** as Cloud Functions da app (codebase `default`) a partir desta tip, num único comando (secção 2.2).
5. Functions + hosting do painel (codebase `admin-talksy`, secção 2.3).
6. Backfills só com OK à parte, dry-run primeiro (secção 2.4).
7. Hosting da app (portal-login / convite) só com OK à parte (secção 2.5).
8. Testes manuais no iPhone contra a produção já atualizada (secção 5).
9. Só então gerar e enviar as builds de loja (secção 3).

Não implantar `landing/` nem o site de marketing. Não gravar no Firestore de produção fora dos backfills aprovados. Não fazer `firebase functions:delete` sem OK.

### 2.1 Índices e rules

A correr em `/Volumes/REMDY_SSD/b44_selo_desconto`, projeto `socialchatmvp`:

```
cd /Volumes/REMDY_SSD/b44_selo_desconto
firebase deploy --only firestore:indexes --project socialchatmvp
# Esperar Enabled na consola: groups
#   deleted+countryCode+scope+cityKey+updatedAt
#   deleted+countryCode+scope+regionCenterGeohash+updatedAt
#   deleted+countryCode+geohash3+updatedAt
#   deleted+countryCode+stateKey+updatedAt

# Rules da segurança b44 (SEM OK próprio — vê LANCAMENTO secção 6):
firebase deploy --only firestore:rules --project socialchatmvp
```

As Rules de `places` continuam `create`/`update`/`delete: if false`. O diff das rules é só a frente de segurança (bloquear PV, muted, `verification`/`verified` só no servidor, `verificationPhones`).

### 2.2 Functions da app — comando único

Um único `firebase deploy` com tudo o que as secções 1–7 do `DEPLOY_B44.md` pediam, mais o que a revisão encontrou em falta (segurança e filtros). A correr na pasta da app, tip `7e3fa48`:

```
cd /Volumes/REMDY_SSD/b44_selo_desconto

firebase deploy --only \
functions:onGroupMessageCreated,functions:onPrivateMessageCreated,functions:onEventUpdated,functions:onGroupJoinRequestCreated,functions:onGroupJoinRequestUpdated,functions:approveGroupJoinRequest,functions:rejectGroupJoinRequest,functions:createEventComment,functions:onAudioRoomOpened,functions:onReportCreated,functions:submitPlaceReview,functions:replyPlaceReview,functions:onPlaceModerated,functions:onPlacePendingNotifyAdmins,functions:onPublicUserInterestsWritten,\
functions:confirmAdultAge,functions:deleteMyAccount,functions:createGroup,functions:updateGroupSettings,functions:joinGroupByInviteCode,functions:joinOpenGroup,functions:leaveGroup,functions:deleteGroup,functions:banGroupMember,functions:unbanGroupMember,functions:promoteGroupAdmin,functions:demoteGroupAdmin,functions:removeGroupMember,functions:createEvent,functions:updateEvent,functions:cancelEvent,functions:joinEvent,functions:leaveEvent,functions:sendDmMessage,functions:forwardMessage,functions:searchUsers,functions:submitPlace,functions:updateMyPlace,functions:moderatePlace,functions:askRemi,functions:audioRoomAction,functions:setGroupAudioRoom,\
functions:applyInviteCode,functions:claimInvitePremiumReward,functions:fetchLinkPreview,functions:issueShareExtensionSession,functions:revokeShareExtensionSessions,functions:translatePlaceDescription,functions:claimPlaceForAccount,functions:listPlaceReviews,functions:transferGroupOwnership,functions:markGroupAsRead,functions:exportEventParticipants,functions:toggleEventLike,functions:toggleEventCommentLike,functions:deleteEventComment,functions:registerEventView,functions:archiveEvent,functions:restoreEvent,functions:duplicateEvent,functions:deleteEventPermanently,functions:abortIncompleteEvent,functions:approveEventPendingChanges,functions:rejectEventPendingChanges,functions:syncRevenueCatEntitlement,\
functions:listShareDestinations,functions:sendShareMessage,\
functions:onPlaceDescriptionApproved,\
functions:deletePlace,\
functions:setPlaceDiscount,functions:setPlacePartnershipDiscount,functions:issuePlaceDiscountCode,functions:redeemPlaceDiscount,\
functions:markPhoneVerified,functions:unlinkVerifiedPhone,functions:revokeVerification,functions:onUserVerificationGuard,functions:adjustModeration,functions:updateGroupModBot,functions:onGroupMembersWelcomeBot,functions:moderateChatImage,functions:moderateMessageText,functions:moderateGroupMessageText \
--project socialchatmvp
```

Opcional (mesmo `details.i18nKey` em erros de listagem do dono): acrescentar `functions:getMyPlace,functions:listMyPlaces,functions:listPendingPlaces`.

`renderPublicPlacePage` / `renderPlacesSitemap` não mudaram no passo da tradução (o gatilho grava o cache que a `/l/` já lê). Só reimplantar se a verificação da `/l/` falhar.

### 2.3 Painel admin (`moderateAdminPlace` + hosting)

Mesmo projeto, codebase **`admin-talksy`**. Tem de ser lançado **a partir do repositório do painel**, nunca da pasta da app.

```
cd /Volumes/REMDY_SSD/admin_qr_work
git rev-parse --short HEAD   # 96e1d23, branch feat/b44-excluir-local

export TMPDIR=/Volumes/REMDY_SSD/remdy_b40_build/tmp44
export PATH=/Users/macbookairm1/Downloads/flutter/bin:$PATH

flutter build web --release
firebase deploy --only functions:moderateAdminPlace,hosting:admin --project socialchatmvp
```

Hosting target `admin` → site `remdy-admin`, pasta `build/web`. Isto publica o “Excluir local” do painel. A UI de selo de parceria **não** está neste commit.

### 2.4 Backfills e tradução — OK à parte

Dry-run (não escreve):

```
cd /Volumes/REMDY_SSD/b44_selo_desconto/functions
node scripts/backfill_group_geo_state.js --out /Volumes/REMDY_SSD/remdy_b40_build/backfill_b44_geo
node scripts/backfill_place_description_i18n.js --out /Volumes/REMDY_SSD/remdy_b40_build/backfill_b44_i18n
```

Execução real, só com OK (e, no i18n, com o kill switch ligado — tem custo de API):

```
node scripts/backfill_group_geo_state.js --execute --out /Volumes/REMDY_SSD/remdy_b40_build/backfill_b44_geo
PLACE_DESCRIPTION_TRANSLATION_ENABLED=true node scripts/backfill_place_description_i18n.js --execute --out /Volumes/REMDY_SSD/remdy_b40_build/backfill_b44_i18n
```

Antes de implantar `onPlaceDescriptionApproved` ou de correr o backfill i18n: confirmar `PLACE_DESCRIPTION_TRANSLATION_ENABLED=true` no ambiente das Functions. O ficheiro `.env.socialchatmvp` citado no `DEPLOY_B44.md` **não está** no worktree `b44_selo_desconto`. Sem o kill switch, o gatilho não traduz.

### 2.5 Hosting da app (portal-login e convite) — OK à parte

```
cd /Volumes/REMDY_SSD/b44_selo_desconto
firebase deploy --only hosting:app --project socialchatmvp
```

Publica **todo** o `public/` no site `socialchatmvp` (incluindo portal-login e convite nos 5 idiomas). Rever o conteúdo de `public/` antes de aprovar. Marketing (`landing/`, `public/index.html`) ficou de fora de propósito no trabalho de l10n.

### 2.6 Verificações pós-deploy

- Consola Firebase: as Functions do comando único aparecem em `us-central1` com horário de atualização recente; as 4 do selo, `deletePlace` e as 7 de segurança/filtros existem.
- Índices geo: estado **Enabled** (não “Building”).
- Rules: o texto publicado inclui `userDmBlocked`, `verificationPhones` e `mutedUntil`.
- Callable de fumo (conta de teste, não de produção real sem OK): `deletePlace` (idempotente num local de teste); `setPlaceDiscount` / `issuePlaceDiscountCode` / `redeemPlaceDiscount`; `listShareDestinations`; um push (mensagem de grupo) no idioma gravado em `users/{uid}.appLanguageCode`.
- Aprovar um local de teste e confirmar `descriptionI18n` no documento e a página `/l/{id}` nos 5 idiomas (`?lang=` / `Accept-Language`).
- Painel (`remdy-admin`): login de admin, “Excluir local” (`moderateAdminPlace` ação `delete`); o local some do catálogo público e permanece com exclusão lógica.
- App (depois do deploy, com a IPA de teste 50 ou uma build de loja ainda não enviada): ver secção 5.
- Confirmar que as Rules de `places` continuam a recusar create/update/delete do cliente.

### 2.7 Rollback

Nada disto foi ensaiado. Princípio: reimplantar a revisão anterior conhecida de produção (a loja 1.0.9 saiu do commit `135d943` da app; confirmar no histórico da consola o código que está mesmo em produção **antes** do deploy, e guardar esse ponto).

- **Functions já existentes** (ex.: `sendDmMessage`, pushes): na pasta da app, checkout do commit de produção anterior e `firebase deploy --only functions:<lista afetada> --project socialchatmvp`.
- **Functions novas** (`deletePlace`, `setPlaceDiscount`, `setPlacePartnershipDiscount`, `issuePlaceDiscountCode`, `redeemPlaceDiscount`, e as novas de segurança se não existirem em produção): deixá-las no ar é inofensivo enquanto a app das lojas não as chama; para as remover, `firebase functions:delete <nome> --project socialchatmvp` **só com OK** (irreversível sem o código).
- **Índices**: não reverter por defeito (adicionar é seguro; apagar pode partir queries).
- **Rules**: guardar o ficheiro publicado hoje; rollback = `firebase deploy --only firestore:rules` a partir do commit anterior (`135d943` ou o que estiver em produção). Fazer isto com cuidado: um rollback das rules pode voltar a permitir o cliente escrever `verified` / não honrar PV bloqueado.
- **Backfill geo**: `node scripts/backfill_group_geo_state.js --rollback DIR/antes_<ts>.json` (apaga só `stateCode`, `stateKey`, `geohash3`).
- **Backfill i18n**: `node scripts/backfill_place_description_i18n.js --rollback DIR/antes_<ts>.json` (os contadores de uso da API não voltam; o custo já foi cobrado).
- **Hosting do painel**: `flutter build web` no commit anterior do admin e `firebase deploy --only hosting:admin --project socialchatmvp`. A Function `moderateAdminPlace` no commit anterior (sem ação `delete`) pela mesma pasta.
- **Hosting da app**: só se o passo 2.5 tiver sido feito; reimplantar o `public/` anterior.
- **Lojas**: uma vez em revisão ou publicada, não há rollback técnico da IPA/AAB; pausar lançamento faseado ou submeter correção (build > 52). As IPAs de teste 50 e 51 não vão para a loja.

### 2.8 Lacunas encontradas no `DEPLOY_B44.md` (documento corrigido)

O ficheiro na worktree do selo foi atualizado (só o documento; sem commit, sem deploy). Faltava:

1. **Segurança b44** (`089e9a7`): `firestore:rules` e as Functions `markPhoneVerified`, `unlinkVerifiedPhone`, `revokeVerification`, `onUserVerificationGuard`, `adjustModeration`, `updateGroupModBot`, `onGroupMembersWelcomeBot`, `moderateChatImage`, `moderateMessageText`, `moderateGroupMessageText`. Sem as rules, o interruptor “bloquear PV” da app nova não consegue gravar `dmBlocked`. Sem as Functions novas, selo SMS, bot do grupo e “sem falar” não fecham o ciclo. `word_lists.json` continua RASCUNHO até revisão do Willian.
2. **Comando de deploy dos “outros callables”** (a lista da secção 2 terminava em “etc.”). Ficou completo, com `revokeVerification`.
3. **Backfill da tradução de lugares** (`functions/scripts/backfill_place_description_i18n.js`) e o aviso de que `.env.socialchatmvp` não está neste worktree; o kill switch é `PLACE_DESCRIPTION_TRANSLATION_ENABLED`.
4. **Hosting do painel** (`flutter build web` + `firebase deploy --only functions:moderateAdminPlace,hosting:admin` a partir de `admin_qr_work`, codebase `admin-talksy`). A secção 6 só tinha a Function, sem diretório nem hosting.
5. **Comando de `hosting:app`** para portal-login e convite (já estava nas Notas, sem comando).
6. Cabeçalho desatualizado (ainda falava só de `feat/b44-erros-auth`).

Não se juntou ao comando único, de propósito: `renderPublicPlacePage` (não mudou), site de marketing, backfills (`--execute`), e `getMyPlace` / `listMyPlaces` / `listPendingPlaces` (i18n opcional).

---

## 3) Builds de loja — SEM OK (não gerar agora)

As builds de teste 50 e 51 (Development) **não** servem para App Store / TestFlight / Play. As builds de loja só depois do deploy (secção 2) e dos testes (secção 5). Versão **1.0.10** via flags, **sem alterar o `pubspec.yaml` do git** (continua `1.0.9+43`), salvo se o Willian quiser o bump commitado. Build number sugerido: **52** (tem de ser > 51 e maior do que qualquer build já enviada às lojas; a 51 é a IPA de teste «Gerenciar meus locais». A Play 1.0.9+45 já usou 45, a App Store 1.0.9 usou 43).

DerivedData, TMPDIR e caches no SSD. Não apagar nada no disco interno. Não instalar no iPhone, não fazer upload, sem `-allowProvisioningUpdates` se isso abrir login/2FA — no arquivo de loja com assinatura automática, parar e reportar se a Apple pedir credenciais.

### 3.1 Decisão do Willian: `REMDY_LOCAIS_ENABLED` na loja

No código (`lib/features/locais/locais_feature_flag.dart`) o valor compilado **padrão é `false`**. O comentário ainda diz que Locais fica fora dos builds de produção e só liga com `--dart-define=REMDY_LOCAIS_ENABLED=true` em desenvolvimento.

Na prática, a loja **já saiu com a flag ligada**:

- iOS 1.0.9 (43), pipeline `store43/pipeline109.sh`: `--dart-define=REMDY_LOCAIS_ENABLED=true`
- Android 1.0.9+45, `store43/aab.sh`: o mesmo

A build 44 é sobretudo Locais (tradução das descrições, partilhar com grupos/pessoas, excluir local, selo de desconto). **Sem a flag, nada disso aparece na loja.**

**Recomendação:** enviar a 1.0.10 da b44 **com** `--dart-define=REMDY_LOCAIS_ENABLED=true`, igual à 1.0.9(43).  
**Isto precisa de OK do Willian.** Se a decisão for não ligar, a 1.0.10 chega às lojas sem o módulo Locais (e os textos de “Novidades” abaixo deixam de fazer sentido). O comentário no `locais_feature_flag.dart` fica desatualizado em relação à 1.0.9; atualizá-lo é um passo de código à parte.

### 3.2 iOS (App Store)

Mesmo método da 1.0.9(43): `flutter build ios --config-only --release` + `xcodebuild archive` + `xcodebuild -exportArchive`.

- Assinatura: **Apple Distribution: Willian Dias (CZN2YMTU7B)**, Team ID `CZN2YMTU7B` (não é a identidade de teste Development `7K2Y5QVQ7C`).
- `ExportOptions.plist`: `/Volumes/REMDY_SSD/remdy_b40_build/store/ExportOptions.plist` (`method` = `app-store-connect`, `signingStyle` = `automatic`, `manageAppVersionAndBuildNumber` = `false`).
- Inclui a Share Extension, como na 1.0.9.
- Saída sugerida no SSD, por exemplo `/Volumes/REMDY_SSD/remdy_b40_build/store44/`.
- Esboço (não executar):

```
B=/Volumes/REMDY_SSD/remdy_b40_build
S=$B/store44
export TMPDIR=$B/tmp44 PATH=/Users/macbookairm1/Downloads/flutter/bin:$PATH
export CP_HOME_DIR=$B/CocoaPods
export CLANG_MODULE_CACHE_PATH=$B/ModuleCache SWIFT_MODULECACHE_PATH=$B/ModuleCache
cd /Volumes/REMDY_SSD/b44_selo_desconto

flutter build ios --config-only --release --build-name 1.0.10 --build-number 52 --dart-define=REMDY_LOCAIS_ENABLED=true

xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
  -sdk iphoneos -destination generic/platform=iOS \
  -derivedDataPath $B/DerivedData44store \
  -clonedSourcePackagesDirPath $B/SwiftPackages \
  -packageCachePath $B/PackageCache \
  -archivePath $S/Remdy-1.0.10-52.xcarchive \
  archive

xcodebuild -exportArchive -archivePath $S/Remdy-1.0.10-52.xcarchive \
  -exportOptionsPlist $B/store/ExportOptions.plist \
  -exportPath $S/ipa
```

Upload à App Store Connect / TestFlight: passo posterior, com OK (a pipeline 1.0.9 usava `xcrun altool` com chave de API; não repetir aqui).

### 3.3 Android (AAB)

Assinatura de release: `android/key.properties` (gitignored) com `storePassword`, `keyPassword`, `keyAlias`, `storeFile`, lido por `android/app/build.gradle.kts`. **Esse ficheiro não está** no worktree `b44_selo_desconto`; existe no worktree `b43_firebase`. Copiar localmente (sem commitar) antes da AAB.

Esboço (não executar), com a flag à espera da decisão da secção 3.1:

```
B=/Volumes/REMDY_SSD/remdy_b40_build
export TMPDIR=$B/tmp44 PATH=/Users/macbookairm1/Downloads/flutter/bin:$PATH
export GRADLE_USER_HOME=$B/gradle_home JAVA_TOOL_OPTIONS=-Djava.io.tmpdir=$B/tmp44
cd /Volumes/REMDY_SSD/b44_selo_desconto

# garantir android/key.properties (local, gitignored)

flutter build appbundle --release --build-name=1.0.10 --build-number=52 --dart-define=REMDY_LOCAIS_ENABLED=true
# saída: build/app/outputs/bundle/release/app-release.aab
# copiar para $B/store44/Remdy-1.0.10-52.aab
```

Envio à Play Console: passo posterior, com OK.

---

## 4) Textos das lojas (What’s New / Novidades) — rascunho para aprovação

Cinco idiomas, a resumir a b44. Assumem Locais **ligado** na loja (secção 3.1). Se a flag for `false`, estes textos não devem ser usados.

### pt-BR

Nesta versão o Remdy está traduzido por completo (português do Brasil e de Portugal, inglês, espanhol e francês), inclusive os erros de login e cadastro.

Em Locais, você pode compartilhar um lugar com grupos e com pessoas, excluir um local que cadastrou, e os estabelecimentos podem oferecer um selo de desconto: toque no selo, mostre o app no caixa e use o código ou o QR, que se renovam a cada 60 segundos.

### pt-PT

Nesta versão, a aplicação Remdy está traduzida na totalidade (português do Brasil e de Portugal, inglês, espanhol e francês), incluindo os erros de início de sessão e de registo.

Em Locais, pode partilhar um lugar com grupos e com pessoas, eliminar um local que tenha registado, e os estabelecimentos podem oferecer um selo de desconto: toque no selo, mostre a aplicação no caixa e use o código ou o QR, que se renovam a cada 60 segundos.

### en

This version fully translates Remdy (Brazilian and European Portuguese, English, Spanish, and French), including sign-in and sign-up error messages.

In Places, you can share a place with groups and people, delete a place you added, and businesses can offer a discount badge: tap the badge, show the app at the counter, and use the code or QR, which refresh every 60 seconds.

### es

En esta versión, Remdy está traducido por completo (portugués de Brasil y de Portugal, inglés, español y francés), incluidos los errores de inicio de sesión y de registro.

En Locales, puedes compartir un lugar con grupos y con personas, eliminar un local que hayas dado de alta, y los establecimientos pueden ofrecer un sello de descuento: toca el sello, muestra la app en caja y usa el código o el QR, que se renuevan cada 60 segundos.

### fr

Cette version traduit entièrement Remdy (portugais du Brésil et du Portugal, anglais, espagnol et français), y compris les erreurs de connexion et d’inscription.

Dans Lieux, vous pouvez partager un lieu avec des groupes et des personnes, supprimer un lieu que vous avez ajouté, et les établissements peuvent proposer un badge de réduction : touchez le badge, montrez l’application en caisse et utilisez le code ou le QR, qui se renouvellent toutes les 60 secondes.

---

## 5) Testes manuais no iPhone antes do envio

Usar a IPA de teste 1.0.10 (51) (Development, `Apple Development: Willian Dias (7K2Y5QVQ7C)`, com `REMDY_LOCAIS_ENABLED=true`, botão Gerenciar meus locais) ou a IPA de loja 52 ainda não enviada. **Só depois do deploy da secção 2**: sem as Functions, guardar/validar selo, excluir local e a lista nova de destinos de partilha falham no servidor.

Não instalar nesta tarefa; esta é a lista a cumprir quando o Willian autorizar a instalação.

- Idioma da app nos 5 idiomas (incluindo pt-PT); reinício e `appLanguageCode` gravado.
- Erros de login/cadastro (password errada, e-mail inválido, rede) no idioma escolhido, sem texto cru do Firebase.
- Locais visível (flag ligada): lista, detalhe, descrições já traduzidas quando existirem.
- Selo na lista (canto superior esquerdo) e no detalhe (canto inferior esquerdo do herói); toque abre a promoção; selo expirado ou desligado não aparece.
- Ecrã de promoção: condição “mostrando o app Remdy”; código no formato `REM-XX-….`; QR; renovação a cada 60 s; pílula “Parceria Remdy” só quando for parceria; pede login se estiver desligado.
- Dono: Meus locais → Selo de desconto (5/7/10/15/20 %, validade obrigatória, máximo 90 dias, ligar/desligar, um selo por local, guardar). Ligar/desligar mantém a promoção; mudar percentagem ou data gera código novo.
- Caixa: Validar código (aceita código normalizado; recusa repetido, expirado, de outro local ou de promoção antiga).
- Admin do app: Selo de parceria (`coveredBy` lugar / Remdy / partilhado), catálogo.
- Excluir local (dono e admin); o local some do catálogo; repetir é idempotente; o cliente não escreve direto no documento do lugar.
- Partilha: destinos com grupos e pessoas (membros, busca); regra de país BR/CA/PT + Premium.
- Painel web (se o hosting do admin tiver sido implantado): Excluir local.
- Regressão: login, grupos, eventos, DM, salas de áudio, Share Extension antiga, compras/Premium.
- Segurança (se rules + Functions da secção 8 tiverem sido implantadas): bloquear PV, selo SMS, “sem falar”.
- Confirmar que a 1.0.10(50/51/52) não foi instalada por engano em cima da build 37 / Remdy Booth, e que o bundle é `com.remdy.app`.

---

## 6) Itens que precisam de OK do Willian

1. Merge local na ordem `feat/b44-traducao-locais` → `feat/b44-erros-auth` → `feat/b44-selo-desconto` (ff para `master`).
2. Push das três branches e de `master` (e, à parte, `feat/b44-excluir-local` do painel).
3. Deploy dos índices Firestore (geo) e espera até Enabled.
4. Deploy das **rules** de segurança b44 (afeta as versões já nas lojas).
5. Deploy único das Cloud Functions da app (comando da secção 2.2), incluindo as 4 do selo, `deletePlace`, i18n, geo, tradução, partilha e as Functions de segurança/filtros que faltavam no `DEPLOY_B44.md`.
6. Revisão de `functions/moderation/word_lists.json` (RASCUNHO) antes de o filtro de insultos ir para produção.
7. `PLACE_DESCRIPTION_TRANSLATION_ENABLED` e credenciais da API de tradução (o `.env.socialchatmvp` não está no worktree do selo).
8. Backfill geo `--execute`.
9. Backfill i18n `--execute` (custo de API).
10. Deploy do painel: `moderateAdminPlace` + hosting `admin` (`96e1d23`).
11. Deploy de `hosting:app` (portal-login e convite) — rever `public/` antes.
12. **Flag de loja `REMDY_LOCAIS_ENABLED`** (recomendação: `true`, igual à 1.0.9(43)).
13. Versão 1.0.10 e build number **52** (ou outro número > 51 à escolha).
14. Textos de What’s New / Novidades nos 5 idiomas (rascunho da secção 4).
15. Gerar IPA de loja (Distribution) e AAB (depois do deploy e dos testes).
16. Instalar a IPA de teste 51 (ou a 52 de loja ainda não enviada) no iPhone e cumprir a lista da secção 5.
17. Envio à App Store Connect / TestFlight e à Play Console.
18. (Futuro, não bloqueia este lançamento.) Selo de parceria no painel admin — não está no `96e1d23`.

Não precisa de OK para o que já foi feito nesta tarefa: IPA de teste 1.0.10 (50) local no SSD e estes dois documentos.
