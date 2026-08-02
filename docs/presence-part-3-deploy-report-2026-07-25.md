# Parte 3 — relatório de ativação da presença

Data: 2026-07-25

## Preflight

- Projeto Firebase confirmado: `socialchatmvp` (`384686982032`, display name Remdy).
- Conta Firebase CLI: `diaswillian35@gmail.com`.
- Região das Functions existentes: `us-central1`.
- Região declarada pelas três novas Functions: `us-central1`.
- RTDB criado pela API oficial de gerenciamento:
  - instância: `socialchatmvp-default-rtdb`
  - tipo: `DEFAULT_DATABASE`
  - estado: `ACTIVE`
  - região: `us-central1`
  - URL: `https://socialchatmvp-default-rtdb.firebaseio.com`
- Rules iniciais do RTDB confirmadas como `.read: false` e `.write: false`.
- Leitura não autenticada antes do deploy: negada com HTTP 401.
- A URL real coincide com `lib/firebase_options.dart` e
  `PresenceRtdbConfig.databaseURL`.

## Firestore Rules revisadas

O `git diff -- firestore.rules` foi revisado. A publicação inclui somente as
alterações locais conhecidas desta sequência de segurança/presença:

- proteção dos campos administrativos, Premium, assinatura e convite em
  `users/{uid}`;
- proteção de `homeCountryCode` depois da primeira definição;
- leitura autenticada e escrita somente pelo servidor para `presenceState` e
  `presenceCounters`;
- bloqueio total do checkpoint de reconciliação para clientes;
- proteção do agregado `publicUsers.isOnline` e das sessões legadas;
- compatibilidade de `lastSeenAt` na presença interna de grupos.

Nenhum índice do Firestore será publicado.

## Escopo autorizado do deploy

- `firestore:rules`
- `database`
- `functions:onPresenceConnectionWritten`
- `functions:reconcilePresenceCounters`
- `functions:reconcilePresenceCountersNow`

Explicitamente fora do deploy: Hosting, Storage Rules, Firestore indexes,
demais Functions, lojas, AAB e IPA.

## Resultados

### Validação pré-deploy

- Dart (`presence_rtdb_test.dart` + `presence_revision_test.dart`): 26 testes
  aprovados.
- Node (agregado + contadores RTDB): 25 testes aprovados.
- Firestore Rules Emulator: 25 testes aprovados.
- RTDB Rules Emulator: 8 testes aprovados.
- `node --check`: `index.js`, `presence_rtdb_counters.js` e
  `presence_rtdb_counters_logic.js` válidos.
- `flutter analyze` focado nos 12 arquivos centrais da presença: nenhum
  problema.
- A análise ampliada de páginas consumidoras registrou 44 avisos antigos
  (imports/elementos não usados e APIs de UI depreciadas), sem erros de
  compilação e sem relação com o backend publicado.

### Deploy

Deploy concluído com sucesso, limitado a:

- Firestore Rules;
- RTDB Rules;
- `onPresenceConnectionWritten` (`us-central1`, Node.js 24, Gen 2);
- `reconcilePresenceCounters` (`us-central1`, Node.js 24, Gen 2);
- `reconcilePresenceCountersNow` (`us-central1`, Node.js 24, Gen 2).

O deploy da Function agendada habilitou a API Cloud Scheduler e criou o job
`firebase-schedule-reconcilePresenceCounters-us-central1`, habilitado, em UTC,
com frequência `every 24 hours`.

Não foram publicados Hosting, Storage Rules, Firestore indexes, outras
Functions, AAB ou IPA.

### Verificação pós-deploy

- As três Functions estão `ACTIVE` em `us-central1`.
- As RTDB Rules publicadas foram relidas e correspondem às regras locais.
- Leitura não autenticada de presença: negada.
- Escrita autenticada na presença de outro UID: negada.
- Escrita cliente nos contadores mundial e por país: negada.
- Usuário comum chamando a reconciliação: `permission-denied`.
- Conexão própria: criação, leitura e remoção aprovadas.
- `onDisconnect`: configuração, cancelamento e reconfiguração aprovados.
- Trigger marcou o usuário temporário online e removeu o marcador após a
  exclusão da conexão.
- Com país `br`, os contadores mundial e do país transitaram exatamente
  `0 → 1 → 0`, sem duplicação ou valor negativo.
- Estado final do smoke: `presence = null`, `presenceCounters/world = 0`.
- Usuários anônimos e documentos Firestore temporários usados no smoke foram
  excluídos; `presenceCounters/byCountry/br` permaneceu em `0`.
- `onPublicUserSessionWritten` não existe na lista de Functions do cloud;
  nenhuma Function antiga de heartbeat foi republicada.

### Smoke em aparelho

O smoke de backend autenticado foi concluído com SDK real contra produção.
O teste completo de ciclo de vida no app (background menor/maior que 60 s,
retorno, logout e botão voltar) ficou pendente porque o único aparelho perdeu
a conexão ADB antes da verificação pós-deploy.

O teste com dois aparelhos (texto `2 online`/`1 online` e bolinha verde em
chat, lista e grupo) também ficou pendente; nenhum resultado foi inferido.

### Custo esperado

Para o volume de MVP, a expectativa é custo nulo ou muito baixo dentro das
franquias do Blaze. O RTDB inclui 1 GB armazenado e aproximadamente 10 GB/mês
de download sem custo; excedentes custam cerca de US$ 5/GB-mês armazenado e
US$ 1/GB baixado. Cada entrada/saída aciona uma Function e transações no
Firestore; a reconciliação lê o estado uma vez por dia. O principal vetor de
custo é tráfego RTDB, seguido por invocações/tempo das Functions e
leituras/escritas Firestore. Recomenda-se alerta de orçamento.
