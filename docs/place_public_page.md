# Página pública de Locais — preparação local

Nenhum deploy, push, merge, instalação, login ou escrita em Firestore foi feito.
Worktree: `/Volumes/REMDY_SSD/place_page_work`, branch `feat/place-public-page`, base `a848f40`.

## Implementação

- `functions/public_place_logic.js`: SSR puro, HTML escapado, URLs HTTPS, JSON-LD seguro; 404 para local não publicado; cinco idiomas via Accept-Language ou `?lang=`; canonical/hreflang/x-default, OG/Twitter, title e description com cidade.
- `functions/public_place.css` e `public_place_brand.json`: mesmos estilos, fontes, cores e marca da página de eventos ao vivo. Fonte original localizada em `/Users/macbookairm1/Downloads/tmp_portal_qr_fix/functions/src/public_events.ts` e `public_event_landing.ts`; CSS/marca conferidos com `https://remdy.app/e/x`.
- `functions/public_places.js`: `renderPublicPlacePage` e `renderPlacesSitemap`, us-central1, invoker público, só leitura, Cache-Control de 300/600 segundos, Vary Accept-Language.
- Relacionados: query por `cityName` e quatro filtros de publicação, limite 7; exclui o próprio local, deduplica e mostra até 6. Também evita homônimos em outro país quando o país está informado. Sem resultados, esconde a seção, igual ao carrossel de eventos.
- Sitemap lê todos os documentos publicados em páginas de 500; cinco URLs por local e lastmod. Acima de 10.000 locais, retorna sitemapindex e shards `?page=N`, respeitando 50.000 URLs por XML.
- `firebase.json`: `/l/**` e `/sitemap-locais.xml` no mesmo target `app` dos eventos.
- App: compartilhar com share_plus/ícone existente do header de eventos, textos nos cinco catálogos; `/l/<ID>` preserva maiúsculas e lê diretamente por ID. Rota antiga por slug preservada. Android recebe `/l/`. Repositório injetável para testar sem Firebase nem conta.
- `functions/social_function_policy.js`: registra os dois endpoints como públicos somente leitura; nenhuma ação social foi liberada.
- Testes em `functions/public_place_logic.test.js`, `functions/public_places.test.js`, `test/place_public_link_test.dart`; expectativas antigas de segurança atualizadas para build 40 e rota agora implementada. Golden alterado somente para o ícone novo em `iphone_detalhe.png`.

## Validação

- 161 testes npm passaram (15 novos testes SSR/handler incluídos).
- 114 testes Flutter passaram (`test/locais`, parser e links), incluindo compartilhar nativo mockado e leitura direta sem consultar catálogo.
- Analyzer dos quatro arquivos Dart novos/alterados: sem problemas. Analyzer incluindo main.dart: somente 13 avisos `avoid_print` preexistentes, fora do trecho alterado.
- Integração local de handlers reais com Firestore REST somente leitura: `scripts/place_page_readonly_e2e.cjs` (GET de documento + runQuery somente leitura; sem Java).
- John Burger `hPGFEU4iQbDJXItOwQhV`: 200 pt-BR e en; imagem OG pública Firebase Storage com download token retornou 200 image/jpeg sem autenticação; 404 para ausência.
- John Burger é só delivery: não foram publicados rua/coordenadas/maps, embora o documento tenha coordenadas. Cidade Toronto continua pública. OwnerId, contatos privados e campos internos não são serializados.
- A descrição do dono continua no idioma original: a tradução automática de conteúdo não faz parte desta tarefa. Interface, categorias, dias da semana, SEO e botões têm os cinco idiomas.
- A consulta de sitemap retornou apenas UM local publicado (John Burger), portanto não há outros reais para o carrossel. `related-fixture-pt-BR.png` é uma prévia claramente marcada com dois cartões fictícios em memória; NÃO criamos documentos.
- `whatsapp-preview.png` é uma SIMULAÇÃO visual dos metadados OG, não uma captura do WhatsApp nem um link já publicado.
- Screenshots Chrome headless, perfil novo no SSD: desktop pt-BR/en, mobile e prévia de relacionados. `e2e/browser-proof.json` registra dimensões e carregamento das imagens.

## Índices

As queries EXATAS de relacionados e sitemap funcionaram no banco real sem criar índice. Não é necessário deploy de índice novo para esta versão. `firestore.indexes.json` permaneceu inalterado. Existem três índices de places READY no projeto; definições remotas completas foram salvas apenas em `e2e/live-indexes.json`. Não publicar o arquivo geral de índices às cegas: ele não contém todos esses índices remotos e uma sincronização pode propor remoções.

## Deploy futuro — NÃO executado

Depois de aprovação e integração dos commits:

```sh
firebase deploy --project socialchatmvp --only functions:default:renderPublicPlacePage
firebase deploy --project socialchatmvp --only functions:default:renderPlacesSitemap
```

Ou as duas funções no mesmo comando:

```sh
firebase deploy --project socialchatmvp --only functions:default:renderPublicPlacePage,functions:default:renderPlacesSitemap
```

Hosting:

```sh
firebase deploy --project socialchatmvp --only hosting:app
```

**RISCO ALTO: NÃO executar esse comando de Hosting nesta worktree.** Target `app` aponta para o site `socialchatmvp`, o MESMO de remdy.app. As páginas `/e/x` em remdy.app e socialchatmvp.web.app retornaram HTML com SHA-256 idêntico. Deploy de Hosting substitui a versão inteira de arquivos/configuração, não apenas rewrites. O `public/` deste app contém index.html exportado que referencia `_next/`/brand/imagens ausentes daqui, e não é o estágio completo e atual do Remdy_page. Transfira somente os dois rewrites para o estágio atual e completo do site, preserve os outros rewrites/headers/assets e publique DE LÁ após aprovação. Remdy_page NÃO foi modificado.

## Pendências no site (somente proposta)

1. AASA: nos arquivos que servem `/.well-known/apple-app-site-association` e `/apple-app-site-association` (exportação pública do Remdy_page, tipicamente `public/.well-known/apple-app-site-association` e `public/apple-app-site-association`), adicionar `"/l/*"` em `applinks.details[].paths` para `CZN2YMTU7B.com.remdy.app`. Preservar todas as rotas atuais e webcredentials. O AASA ao vivo ainda não tem `/l/*`.
2. `public/robots.txt` do site: adicionar `Sitemap: https://remdy.app/sitemap-locais.xml`; pode adicionar `Allow: /l/`, embora `Allow: /` já libere. Preservar os sitemaps atuais.
3. `/sitemap.xml` atual é um **urlset**, não sitemapindex: NÃO inserir uma tag `<sitemap>` dentro dele. O novo sitemap pode ser descoberto diretamente pelo robots (mesmo padrão atual de sitemap-events.xml). Se quiser um índice principal, converter corretamente para sitemapindex e mover as URLs estáticas para outro sitemap, preservando-as.
4. Novo binário do app (iOS e Android) necessário para botão e parser; usar `REMDY_LOCAIS_ENABLED=true` na entrega aprovada. Não foi gerado build iOS nem instalado nada. Universal links reais no aparelho dependem desse build + AASA/site publicado + cache de associação da Apple; não foram alegados como testados.

Artefatos ficam em `e2e/` na worktree e `~/remdy_e2e/place_page/` no Mac. Dependências existentes foram reutilizadas (node_modules por symlink, package_config na worktree); nenhum arquivo do Mac foi apagado.
