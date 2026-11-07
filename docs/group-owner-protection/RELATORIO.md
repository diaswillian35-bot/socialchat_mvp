# Proteção do dono e hierarquia de grupos — somente local

## Entrega e decisões que precisam de confirmação

Worktree: `/Volumes/REMDY_SSD/group_roles_work`; branch `fix/group-owner-protection`; base `c779572`. O SHA do commit local está na mensagem de entrega. Nenhum deploy, push, merge, instalação, login, build iOS ou gravação de dados de produção. Outros worktrees não foram modificados. Dependências já existentes foram reutilizadas; o `.gitignore` passou a ignorar também node_modules quando é symlink.

**Interpretação implementada, a confirmar antes de publicar:**

1. Só o dono pode promover para admin/moderador e rebaixar cargos. Só o dono pode remover ou banir outro admin. Isso é uma exceção explícita à expressão original “ninguém pode ... outros admins”; confirmar essa interpretação.
2. Admin pode remover/banir membros e moderadores, mas não outro admin nem o dono. Moderador pode remover/banir **somente membros comuns**; não altera cargos, não gerencia outro moderador, não edita configurações nem aprova pedidos. Não havia moderador operacional: apenas descoberta reconhecia os arrays legados `moderators`/`mods`. Esse papel e sua promoção foram implementados agora, reutilizando os componentes e o visual existentes.
3. Dono não pode sair nem transferir ownership, nem voluntariamente: o endpoint antigo falha fechado para impedir bypass por versões antigas do app. Mantida a exclusão voluntária do próprio grupo (soft-delete), exclusiva do dono.
4. A exclusão voluntária da conta continua possível, mas agora **encerra os grupos do dono**, preserva seu ownerId e suas entradas nos arrays, em vez de transferir a propriedade e expulsá-lo. Sem essa decisão, a exclusão de conta seria um caminho indireto de mudança do dono. Confirmar esse comportamento de produto antes do deploy.
5. Nenhum super-admin de plataforma ganha exceção nas funções de cargos. Não se promete bloquear operadores com credenciais IAM/Admin SDK ou console: eles estão fora das regras de cliente. A moderação global de contas/conteúdo continua intacta; dono não ganha imunidade contra medidas de segurança da plataforma.

O dono é o `ownerId` atual. Não houve migração de dados nem tentativa de descobrir/restaurar criadores de grupos cuja propriedade já foi transferida no passado.

## Diagnóstico de hoje, comprovado com a fonte live

**Um admin promovido não consegue remover, banir ou rebaixar diretamente o dono** nas funções atuais. Porém:

- **Pode banir outro admin** por `banGroupMember`; isso o remove simultaneamente de `members` e `admins`. O menu do app também oferece essa opção. `removeGroupMember` e `demoteGroupAdmin` já tinham a proteção entre admins: ban era o buraco.
- O criador pode perder a proteção por um caminho indireto: ele transfere a propriedade (inclusive no fluxo “sair” do app); o novo dono pode remover o criador, agora admin. A fonte live foi executada no emulador e essa sequência foi reproduzida.
- `deleteMyAccount.processGroups` remove o UID e transfere automaticamente para outro admin/membro. Não depende de um admin malicioso: é o fluxo de exclusão da própria conta.
- Um cliente não consegue contornar as funções alterando ownerId, membros/cargos, subcoleções inventadas ou bannedUsers diretamente: as regras live já bloqueiam essas gravações.

### Auditoria servidor: hoje versus depois

Referências abaixo são da worktree corrigida; os trechos anteriores usados na reprodução estão nesta pasta e a base original é `c779572`.

| Caminho / referência | Hoje / fonte live e base | Depois local |
|---|---|---|
| `createGroup`, `functions/index.js:3250` | UID autenticado cria; dono/admin/membro inicial é ele; campos de cargos do cliente recusados por allowlist | Sem mudança |
| `joinOpenGroup`, `index.js:1796`, `group_open_join_logic.js` | Adiciona somente quem chama; valida política/ban. Super-admin pode contornar política de entrada, não cargos | Sem mudança; proprietário e admins preservados |
| `joinGroupByInviteCode`, `index.js:1886` | Adiciona o próprio UID com convite válido; não altera cargos | Sem mudança; regressão executada |
| `approveGroupJoinRequest`, `index.js:3614` | Dono/admin adiciona solicitante a members; não troca ownerId/admins | Sem mudança; regressão executada |
| `rejectGroupJoinRequest`, `index.js:3816` | Dono/admin só muda estado da solicitação; não remove membro | Sem mudança |
| `banGroupMember`, `index.js:2040` | Dono/admin; dono protegido, **outro admin não protegido** | Política central em transação: dono intocável; admin só pelo dono; mod só gerencia membro comum; limpa ambos os arrays de moderadores |
| `unbanGroupMember`, `index.js:2186` | Dono/admin; só desativa ban; não readiciona membro nem muda cargo | Sem mudança; não é bypass para remoção/rebaixamento |
| `promoteGroupAdmin`, `index.js:2291` | Só dono promove membro a admin | Só dono; role admin (padrão compatível) ou moderator; sem escalada por token/mapa forjado |
| `demoteGroupAdmin`, `index.js:2412` | Só dono rebaixa admin; dono protegido | Política central; também rebaixa moderador; limpa moderators/mods |
| `removeGroupMember`, `index.js:2519` | Dono/admin; admin não remove outro admin; dono protegido | Mesma proteção, centralizada; admin remove mod e membro; mod remove apenas membro; cobre papel legado fora de members |
| `transferGroupOwnership`, `index.js:2633` | Só dono; transforma criador em admin removível | Sempre recusada com erro localizado; ownership imutável |
| `leaveGroup`, `index.js:2645` | Recusa dono, mas app antes transferia a propriedade | Mantém recusa; sem transferência no app; limpa papel próprio de mod, inclusive legado sem members |
| `deleteGroup`, `index.js:2751` | Só dono faz soft-delete; admin/super-admin não | Sem mudança; negações testadas |
| `updateGroupSettings`, `index.js:2877`, allowlists `2833–2857` | Dono/admin editam campos permitidos; ownerId/members/admins proibidos; roles/mods/moderators desconhecidos também recusados | Sem mudança; seis tentativas de forjar campos testadas |
| `deleteMyAccount`, `functions/delete_my_account.js:154,428` | Somente UID autenticado; remove o dono e transfere automaticamente | Fecha grupos próprios sem transferir/remover dono; relê em transação; consulta também admins/moderators/mods; erros de consulta não são ignorados |
| `onGroupJoinRequestCreated/Updated`, `index.js:1426,1447` | Push/badge, não alteram membros/cargos | Sem mudança |
| `onGroupMessageCreated`, `index.js:636`, `group_unread_logic.js` | Metadados/unread, não muda dono/cargos/membros | Sem mudança |
| `functions/on_report_created.js:73`, `moderation/apply_block.js`, `moderation/strikes.js`, `moderate_chat_image.js` | Tratam mensagens/evidências/strikes/conta; nenhum remove membro ou troca ownerId | Sem mudança; não foi criada exceção contra moderação global |
| Codebase `chat`, `chat/index.js:1–32` | Apenas template com helloWorld comentado; nenhuma função de grupo exportada | Sem mudança; nenhum deploy de chat necessário |

Foram pesquisadas todas as escritas/referências a grupos nas duas codebases, incluindo os módulos de encaminhamento, extensão de compartilhamento e preview de links: eles acessam mensagens/metadados, não ownership/cargos.

### Auditoria Flutter

| Ponto | Hoje | Depois |
|---|---|---|
| `lib/pages/group_info_page.dart`, antes `1524–1529`, agora `1449–1574` | Promover/rebaixar só dono; remover já protege admin; **ban não protege outro admin** | Todas as opções derivam de `GroupRolePolicy`; nenhum menu destrutivo no dono; nenhum no admin para não dono; promoção de moderador com o mesmo PopupMenuItem |
| `group_info_page.dart:219,1299,1341,1382` | Confirmações chamam serviços correspondentes | Guardas de ban/remove também repetem política; retorno do servidor é autoridade mesmo com tela desatualizada |
| `group_info_page.dart`, antes `771–870`, agora `776` | Seleciona novo dono, transfere e sai | Se dono, recusa e mostra tradução; botões de sair/sair e ocultar desativados para ele; seletor de transferência removido |
| `lib/pages/groups_list_page.dart:802,944,1012` | Dono só vê excluir; não dono pode sair; calls no servidor | Mesmo comportamento; erros de política agora traduzidos |
| `lib/services/group_roles_service.dart:10,23,34` | promote/demote/remove callables | Mesmo serviço; promoção aceita role opcional sem quebrar cliente antigo |
| `group_ban_service.dart:46,58`; `group_lifecycle_service.dart:10–27` | Ban/unban/sair/transferir/excluir por callables | Contratos mantidos; método legado de transferir permanece, mas não é chamado pela tela e o servidor o recusa |
| `group_creation_service.dart:18`; `group_settings_service.dart:14`; `group_join_request_service.dart:14,26`; `group_join_service.dart:247,441,453` | Criação/configuração/entrada via Functions; pedidos pendentes diretos próprios | Nenhum fallback que grave members/admins/ownerId no cliente; fluxos preservados |
| `lib/services/group_discovery_logic.dart:101–123` | Reconhece moderators/mods só para participação/descoberta | Mantido; não havia função operacional de mod |

Mensagens novas em `lib/l10n/{pt-BR,pt-PT,en,es,fr}.json`; `group_role_error.dart` converte `details.localizationKey` (ou message) usando AppTexts. Testes carregam os cinco catálogos e verificam o texto efetivamente retornado por AppTexts.t. Nenhuma cor, fonte ou estilo de componente foi alterado; só opções, disponibilidade e textos ligados à permissão.

### Regras live de Firestore (sem mudanças)

Release `projects/socialchatmvp/rulesets/8e055e6c-b6c2-4a69-9362-2a7cfe6cc2db`, atualizado em **03/11/2026 20:38:10 EST (Toronto)**. GET da release e do ruleset foi feito somente por leitura. Snapshot em `firestore.live.rules`.

SHA-256, live e repositório: `8417e8ac72fc7854a008e22b5bb2211cdbf0ee74233c5caca4baaa7ad68a94e5`. **Diff vazio.** Não foi necessário mudar regras.

| Match | Política relevante |
|---|---|
| `firestore.rules:797–808`, `/groups/{groupId}` | Leitura autenticada; create/update/delete do cliente sempre false, inclusive dono e admin de plataforma |
| `:960–1027`, `/pendingRequests/{requestUid}` | Só pedido/re-pedido/cancelamento do próprio solicitante; sem self-approve; decisão só Functions |
| `:1031–1035`, `/bannedUsers/{uid}` | Escrita do cliente sempre false |
| `:810–929`, `/messages/{mid}` | Escritas limitadas a mensagens, não campos do grupo |
| `:932–957`, `/reads/{uid}`; `:1038–1067`, `/presence/{uid}` | Campos próprios restritos; não alteram membros/cargos |
| `/groups/{id}/members/{uid}`, `/roles/{uid}` | Não existe match que permita escrita; deny implícito, testado |
| `:1214`, collection-group pendingRequests | Match adicional de leitura, não concede escrita de cargos/membros |

Functions usam Admin SDK e ignoram Rules. Por isso a nova política também é aplicada dentro das transações, não apenas nas regras/tela.

## Testes e limites

- **278 testes Node passaram**, zero falhas, incluindo **128 da política**: matriz 5×5×4 (dono/admin/mod/membro/externo; alvos distintos do mesmo cargo), self-actions, documentos legados/malformados, ausência de override de super-admin e exclusão de conta. Inclui as suítes existentes de bio, entrada aberta, convites/solicitações e demais funções.
- **86 testes de integração passaram**, zero falhas, em projeto **demo-group-owner-protection**, Firestore local `127.0.0.1:18080`. Criou grupo por callable real, entrou A/B, promoveu admins, reproduziu com código live o ban entre admins e a transferência seguida de remoção do criador; depois verificou que o código corrigido nega A contra dono/outro admin em remove/ban/demote, inclusive claims de plataforma. Dono pode demover e remover A ainda admin; pode banir B; admin pode remover moderador; moderador só remove membro. Bio, convite e aprovação continuam funcionando.
- A integração inclui **47 verificações no motor real de regras por REST**: 46 gravações recusadas e controle positivo de leitura autenticada. Testa root ownerId/admins/members/moderators/roles, delete, subcoleções members/roles/bannedUsers e self-approve; inclusive UID com documento de admin da plataforma e claims de super-admin.
- A limpeza de grupos de `deleteMyAccount.processGroups` foi executada de verdade contra o Firestore emulado; somente a remoção de mídia de Storage foi substituída por stub. Verificou fechamento sem mudança de ownerId/members/admins.
- **229 testes Flutter passaram**, zero falhas; inclui 105 de política/traduções e regressões de entrada, convites, bio/capa, criação, saída e descoberta.
- `flutter analyze --no-pub`: **zero erros**, dois infos pré-existentes de BuildContext após await (`group_info_page.dart:947`, `groups_list_page.dart:966`); nenhum novo aviso no helper.
- Java 21 já estava instalado no Homebrew; não foi baixado/instalado JDK. Node instalado é 26, enquanto o projeto declara 24. Não se instalou pacote algum; @firebase/rules-unit-testing não estava disponível, então as regras foram exercitadas por REST autenticado no emulador real, sem essa biblioteca.

**Não é correto chamar isto de E2E HTTP completo ou teste de interface em iPhone.** Os emuladores de Firestore/Auth iniciaram; Functions carregou a lista, mas cada worker HTTP caiu antes de executar o handler com `Cannot read properties of undefined (reading 'documentId')`. Segredos de teste foram substituídos por valores fictícios locais e foi tentado preservar symlinks, sem resolver a falha de runtime. Não foram alteradas dependências para contornar a proibição de instalar. O substituto forte foi executar os callables **reais exportados, incluindo socialOnCall/guard de idade e transações**, via `.run`, com Firestore e regras reais emulados. Transporte HTTP, App Check, fluxo completo de Auth/Storage na exclusão de conta e UI interativa/dispositivo não foram validados. Os logs de tentativas HTTP foram preservados localmente e não são apresentados como sucesso.

Evidência final: `integration-evidence.txt`, `test-results.json`, `deployment-provenance.md`, snapshots das funções live usados pela reprodução. Grupo demo da rodada final: `FrABMuSuqkPy6wWjmXBy`. Nenhum grupo real foi criado ou alterado.

## Reproduzir os testes localmente (sem instalação)

Usar o Java já existente e o TMPDIR no SSD. Iniciar em um terminal:

```sh
cd /Volumes/REMDY_SSD/group_roles_work
export TMPDIR=/Volumes/REMDY_SSD/remdy_b40_build/tmp
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
export PATH=/opt/homebrew/opt/openjdk@21/bin:$PATH
firebase emulators:start --project demo-group-owner-protection --config firebase.group-test.json --only firestore,auth
```

Em outro terminal, com as dependências locais existentes:

```sh
cd /Volumes/REMDY_SSD/group_roles_work/functions
npm test
FIRESTORE_EMULATOR_HOST=127.0.0.1:18080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:19099 GCLOUD_PROJECT=demo-group-owner-protection GOOGLE_PLACES_API_KEY=emulator-unused node --test group_owner_emulator.test.js
```

Esse segundo teste chama `.run`, não o servidor HTTP de Functions. Ele recusa ambiente que não seja o projeto demo e o host local especificados. Não usar os antigos scripts smoke de deploy, que atingem serviços reais.

## Publicação futura — comandos preparados, NÃO executados

**Aguardar confirmação das interpretações e OK específico de deploy.** Também revisar a diferença pré-existente do guard de idade: as funções live de julho usam onCall; a base c779572 usa socialOnCall e exige idade verificada. Os ZIPs e horários de implantação foram consultados, e essa diferença está documentada em deployment-provenance.md. Um deploy a partir desta base leva também esse guard.

```sh
cd /Volumes/REMDY_SSD/group_roles_work
firebase deploy --project socialchatmvp --only functions:default:banGroupMember,functions:default:promoteGroupAdmin,functions:default:demoteGroupAdmin,functions:default:removeGroupMember,functions:default:transferGroupOwnership,functions:default:leaveGroup,functions:default:deleteMyAccount
```

Nada de hosting, chat ou outras funções. Nenhum deploy de regras é necessário: o diff com live é vazio. Se futuramente houver mudança aprovada de regras, `--only firestore:rules` **substitui TODO o ruleset live**, não somente grupos; antes disso é obrigatório buscar novamente o live e revisar o diff completo para não sobrescrever mudanças concorrentes. Este trabalho não dá OK para essa publicação.

**Novo build do app é necessário** para menus de moderador, botões corretos e mensagens em cinco idiomas. A proteção do servidor não depende de atualizar o app antigo: após eventual deploy ele também passa a receber as recusas, inclusive da transferência antiga. Nenhum build foi gerado nesta tarefa.
