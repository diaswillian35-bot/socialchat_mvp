# Build 38 — auditoria de Locais

## Base e isolamento

- Worktree: `socialchat_mvp_build38`, branch `feat/remdy-build38`.
- Base preservada: commit `7cdcc019595ae357f404bb9e26902ec14357e0cc`, tag `ios-1.0.4-build37`.
- A worktree agora está em `1.0.4+38` no commit local `3fe7612`; `REMDY_LOCAIS_ENABLED` continua `false` por padrão. Esse commit apareceu durante a validação e não foi criado por esta execução.
- O build 37 enviado à Apple não foi alterado.
- Nenhum deploy, instalação, IPA de distribuição, push ou upload foi executado nesta etapa.

## Contrato compartilhado

O app, o portal e o Admin usam a coleção real `places`. Não existe coleção paralela `locais`.

- Público: `places/{placeId}`, contrato `remdy.places.v1`.
- Avaliação única: `places/{placeId}/reviews/{uid}`, contrato `remdy.places.reviews.v1`.
- Acesso privado: `places/{placeId}/private/access`.
- Vínculo por conta: `placeManagers/{uid}/places/{placeId}`.
- Reivindicação: `placeClaims/{placeId_uid}`.
- Cardápio: `places/{placeId}.menu` e arquivos em `places/{placeId}/menu/{fileName}`.
- O público recebe apenas locais `published`, ativos e não apagados.

## Aplicativo implementado

- Aba Locais com lista, descoberta paginada por cidade/geohash regional,
  busca, categorias e filtros. Não há mapa interno: “Como chegar” abre o
  aplicativo de mapas externo; o antigo desenho esquemático foi removido.
- Estados de carregamento, vazio, erro e tentar novamente.
- Ficha com capa + até seis fotos, endereço, horário, contatos, rota, acessibilidade e próximos eventos.
- Avaliação de uma a cinco estrelas e comentário; uma avaliação por usuário/local, edição segura e nova moderação após editar.
- Resposta do proprietário/gestor habilitada somente quando a ACL privada
  confirma dono/gestor; leitura pública sanitizada sem expor UID.
- Reivindicação autenticada e idempotente habilitada para aprovação no Admin.
- Denúncia do cadastro (não do comentário) com motivos comerciais, fila
  privada, idempotência e limite de frequência.
- Cardápio opcional para restaurante, bar e café: até seis fotos, PDF HTTPS, itens com nome, descrição, preço e disponibilidade. Não há pedido, checkout ou pagamento.
- Deep links web/app e push `place_review` e `place_reply` para a ficha.
- Campos obrigatórios pendentes em vermelho, alvos de toque e semântica.
- Textos em pt-BR, pt-PT, inglês, espanhol e francês.
- Layout testado em iPhone, Android e iPad em retrato e paisagem.

## Backend publicado em 2026-10-17

Callables novas em `functions/place_actions.js`:

- `submitPlaceReview`: autenticação, validação, uma avaliação por conta, limite de frequência, moderação pendente e média/contagem consistentes.
- `listPlaceReviews`: devolve somente campos públicos de avaliações aprovadas.
- `replyPlaceReview`: somente dono/gestor e apenas em avaliação pública.
- `claimPlaceForAccount`: pedido idempotente sem gravar proprietário direto.

O push ao proprietário por nova avaliação e ao autor por resposta inclui `type` e `placeId`; nenhum token é registrado em log.

Pacote mínimo publicado no projeto confirmado `socialchatmvp`:

- `replyPlaceReview`, `claimPlaceForAccount` e `reportPlace`, região
  `us-central1`, estado `ACTIVE`, hash
  `9932f021e26702850135e7f18b60d859012af23d`.
- `submitPlaceReview` e `listPlaceReviews` foram preservadas no hash já ativo
  `e542f38086696467ff7505ff19bde7ca170c1c36`.
- Firestore Rules, índices de catálogo/cidade/geohash e Storage Rules do menu.
- Nenhum Hosting, outra Function, app ou artefato de loja foi publicado.

## Portal e Admin locais

- Portal: contrato do cardápio, edição no painel e renderização pública.
- Portal: Rules, índice composto e Storage Rules para imagens/PDF preparados.
- Admin: lista de reivindicações; aprovar cria o acesso privado e o vínculo da conta; rejeitar mantém o local sem vínculo.
- O formulário atual do cardápio aceita URLs HTTPS e itens estruturados. O upload amigável de fotos/PDF pelo navegador ainda deve ser concluído antes da liberação comercial; as Storage Rules já estão preparadas.

## Validação automatizada concluída

- Flutter Locais/push: 39 testes passando.
- Node do app: 5 testes de regras puras passando e auditoria social passando.
- Portal: TypeScript compilado e testes de contrato, banco ao vivo simulado, avaliação/moderação e política de visita passando.
- Admin: TypeScript compilado; 2 testes de permissão passando; análise focada sem erro na página de Locais (há avisos preexistentes em `admin_home_page`).
- `git diff --check` sem erro nos três repositórios.

## Artefatos locais de validação

- Android AAB concluído com a flag ligada apenas no comando: `build/app/outputs/bundle/release/app-release.aab`, 74,5 MB, SHA-256 `0a8086c6b5b8b843547f972097331d68249095a2ce7e425d33bf537a6a856d48`.
- O AAB está declarado como `1.0.4+38`; é somente artefato local de validação e não foi enviado ao Google Play.
- O iOS Profile não foi concluído neste executor. O Xcode instalado exige CoreSimulator mais novo (`1174.9.2`, instalado `1171.7.0`) e os caches/DerivedData redirecionados para o SSD não têm escrita autorizada no sandbox. A tentativa sem assinatura também parou na sandbox interna do Swift Package Manager. Não há `Runner.app` novo para declarar válido.
- Em etapa posterior desta mesma conversa, fora deste executor, um Profile
  `1.0.4+38` foi informado como gerado e instalado no iPhone 16. Esta auditoria
  não recebeu nem verificou hash, UUID ou assinatura desse artefato e não os
  inventa. Nenhuma instalação foi realizada nesta etapa.

## Deploy realizado e próximos passos

1. Publicar, quando pronto, o fluxo Admin que lista e resolve reivindicações e
   denúncias; não entrou neste deploy mínimo do app.
2. Garantir que portal/Admin gravem `cityKey` e `placeGeohash` em todo local.
3. Repetir testes físicos autenticados e só então liberar a flag em artefatos
   de loja.

## Pendências e riscos explícitos

- O backend mínimo do aplicativo está publicado. A flag continua desligada por
  padrão até concluir Admin, dados geográficos e testes físicos.
- O cardápio do portal precisa de seletor/upload amigável, não apenas URLs.
- Push precisa de teste físico em APNs production e FCM Android depois do deploy, sem copiar tokens.
- Reivindicação e moderação precisam de teste ponta a ponta com contas de dono, gestor, usuário e administrador.
- Os builds de validação usam a flag ligada apenas no comando; a configuração padrão continua desligada. O build 37 preservado continua no commit/tag/branch próprios e não foi alterado.
- iPhone/iPad permanecem bloqueados para um Profile real até atualizar o componente CoreSimulator/Xcode e permitir a escrita nos caches Xcode/Swift; não contornar isso com um IPA.
- Os três locais de demonstração ainda não foram criados. IDs reservados e
  confirmados ausentes: `demo-build38-cm-restaurante`,
  `demo-build38-cm-cafe` e `demo-build38-cm-bar`. A criação continua bloqueada
  até o pacote atômico de Rules/índices/Storage/Functions ser autorizado e as
  fotos próprias/licenciadas estarem definidas; nenhuma escrita foi feita.
