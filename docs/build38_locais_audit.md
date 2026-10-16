# Build 38 — auditoria de Locais

## Base e isolamento

- Worktree: `socialchat_mvp_build38`, branch `feat/remdy-build38`.
- Base preservada: commit `7cdcc019595ae357f404bb9e26902ec14357e0cc`, tag `ios-1.0.4-build37`.
- A versão continua `1.0.4+37`; `REMDY_LOCAIS_ENABLED` é `false` por padrão.
- O build 37 enviado à Apple não foi alterado.
- Nenhum deploy, instalação, IPA de distribuição, commit, push ou upload foi executado nesta etapa.

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

- Aba Locais com lista, mapa, cidade/região, busca, categorias e filtros.
- Estados de carregamento, vazio, erro e tentar novamente.
- Ficha com capa + até seis fotos, endereço, horário, contatos, rota, acessibilidade e próximos eventos.
- Avaliação de uma a cinco estrelas e comentário; uma avaliação por usuário/local, edição segura e nova moderação após editar.
- Resposta do proprietário/gestor e leitura pública sanitizada via callable, sem expor UID ou campos privados.
- Reivindicação autenticada, idempotente, para aprovação no Admin.
- Cardápio opcional para restaurante, bar e café: até seis fotos, PDF HTTPS, itens com nome, descrição, preço e disponibilidade. Não há pedido, checkout ou pagamento.
- Deep links web/app e push `place_review` e `place_reply` para a ficha.
- Campos obrigatórios pendentes em vermelho, alvos de toque e semântica.
- Textos em pt-BR, pt-PT, inglês, espanhol e francês.
- Layout testado em iPhone, Android e iPad em retrato e paisagem.

## Backend local, sem deploy

Callables novas em `functions/place_actions.js`:

- `submitPlaceReview`: autenticação, validação, uma avaliação por conta, limite de frequência, moderação pendente e média/contagem consistentes.
- `listPlaceReviews`: devolve somente campos públicos de avaliações aprovadas.
- `replyPlaceReview`: somente dono/gestor e apenas em avaliação pública.
- `claimPlaceForAccount`: pedido idempotente sem gravar proprietário direto.

O push ao proprietário por nova avaliação e ao autor por resposta inclui `type` e `placeId`; nenhum token é registrado em log.

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

## Deploy mínimo futuro (somente após autorização)

1. Functions do app: `submitPlaceReview`, `listPlaceReviews`, `replyPlaceReview` e `claimPlaceForAccount`.
2. Functions/Admin necessárias para listar e resolver reivindicações.
3. Firestore Rules e índice de `places` preparados no portal.
4. Storage Rules para `places/{placeId}/menu/*`.
5. Depois do backend, habilitar `REMDY_LOCAIS_ENABLED=true`, mudar a versão para `+38`, repetir testes físicos e só então gerar artefatos de loja.

## Pendências e riscos explícitos

- Nada desta integração está em produção enquanto Rules/Functions/índice não forem publicados em conjunto; habilitar antes disso causaria falhas de escrita e leitura.
- O cardápio do portal precisa de seletor/upload amigável, não apenas URLs.
- Push precisa de teste físico em APNs production e FCM Android depois do deploy, sem copiar tokens.
- Reivindicação e moderação precisam de teste ponta a ponta com contas de dono, gestor, usuário e administrador.
- Os builds de validação usam a flag ligada apenas no comando; a configuração padrão e a versão continuam sendo as do build 37.
