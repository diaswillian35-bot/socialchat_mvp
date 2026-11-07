# Página pública de Locais — preparação local

Nenhum deploy, push, merge, instalação, login ou escrita em Firestore foi feito.
Worktree: `/Volumes/REMDY_SSD/place_page_work`, branch `feat/place-public-page`, base `a848f40`. A atualização V2 abaixo parte do commit local `a77ebf7`.

## Implementação

- `functions/public_place_logic.js`: SSR puro, HTML escapado, URLs HTTPS, JSON-LD seguro; 404 para local não publicado; cinco idiomas via Accept-Language ou `?lang=`; canonical/hreflang/x-default, OG/Twitter, title e description com cidade.
- `functions/public_place.css` e `public_place_brand.json`: mesmos estilos, fontes, cores e marca da página de eventos ao vivo. Fonte original localizada em `/Users/macbookairm1/Downloads/tmp_portal_qr_fix/functions/src/public_events.ts` e `public_event_landing.ts`; CSS/marca conferidos com `https://remdy.app/e/x`.
- `functions/public_places.js`: `renderPublicPlacePage` e `renderPlacesSitemap`, us-central1, invoker público, só leitura, Cache-Control de 300/600 segundos, Vary Accept-Language.
- Galeria V2: `coverUrl` primeiro, depois `photoUrls` na ordem original, HTTPS e sem duplicatas, limite de 7 exatamente como `_photos` em `firestore_place_mapper.dart`. Logo permanece separado. Grid responsivo reaproveita CSS da galeria de eventos, lazy loading, alt `nome — foto N` nos cinco idiomas e links para a imagem completa. JSON-LD image é array; og:image continua a capa.
- Relacionados V2: mesma cidade (limite 7); se houver menos de 3, pool de até 24 locais publicados mais recentes de outras cidades, ordenados por proximidade quando há coordenadas, ou atualização mais recente. Mostra até 6 sem duplicatas/excluindo o próprio local. A proximidade é entre os 24 candidatos, não uma varredura global.
- Se não houver outro local: lê o switch `config/publicEvents.enabled`, consulta eventos da cidade (limite 16) e completa com eventos nacionais do país do local (limite 40). Revalida isActive/isPublic, status aprovado/publicado ou legado ativo, exclusão/arquivo, visibilidade pública, moderação, SEO e início estritamente futuro. Título muda para eventos; links `/e/<id>`.
- Se o banco não tiver NENHUM candidato público elegível, a seção nunca some: mostra “Explore no Remdy”, explicação e botão real para `/eventos`, sem inventar cartões nem mostrar eventos vencidos.
- Sitemap lê todos os documentos publicados em páginas de 500; cinco URLs por local e lastmod. Acima de 10.000 locais, retorna sitemapindex e shards `?page=N`, respeitando 50.000 URLs por XML.
- `firebase.json`: `/l/**` e `/sitemap-locais.xml` no mesmo target `app` dos eventos.
- App: compartilhar com share_plus/ícone existente do header de eventos, textos nos cinco catálogos; `/l/<ID>` preserva maiúsculas e lê diretamente por ID. Rota antiga por slug preservada. Android recebe `/l/`. Repositório injetável para testar sem Firebase nem conta.
- `functions/social_function_policy.js`: registra os dois endpoints como públicos somente leitura; nenhuma ação social foi liberada.
- Testes em `functions/public_place_logic.test.js`, `functions/public_places.test.js`, `test/place_public_link_test.dart`; expectativas antigas de segurança atualizadas para build 40 e rota agora implementada. Golden alterado somente para o ícone novo em `iphone_detalhe.png`.

## Validação

- V2: 172 testes npm passaram, incluindo galeria, JSON-LD array, idiomas, ordenação/dedupe, rejeição de eventos privados/vencidos, switch global e fallbacks do handler.
- Na V1, 114 testes Flutter passaram (`test/locais`, parser e links), incluindo compartilhar nativo mockado e leitura direta sem consultar catálogo. V2 não altera Dart, Android ou binários.
- Analyzer dos quatro arquivos Dart novos/alterados: sem problemas. Analyzer incluindo main.dart: somente 13 avisos `avoid_print` preexistentes, fora do trecho alterado.
- Integração local de handlers reais com Firestore REST somente leitura: `scripts/place_page_readonly_e2e.cjs` (GET de documento + runQuery somente leitura; sem Java).
- John Burger `hPGFEU4iQbDJXItOwQhV`: 200 pt-BR e en; as CINCO fotos reais (capa + photoUrls, sem duplicatas) retornaram 200 image/jpeg por HEAD sem Authorization. JSON-LD inclui as cinco URLs, OG continua a primeira. 404 para ausência.
- John Burger é só delivery: não foram publicados rua/coordenadas/maps, embora o documento tenha coordenadas. Cidade Toronto continua pública. OwnerId, contatos privados e campos internos não são serializados.
- A descrição do dono continua no idioma original: a tradução automática de conteúdo não faz parte desta tarefa. Interface, categorias, dias da semana, SEO e botões têm os cinco idiomas.
- E2E V2 real: apenas UM local publicado (John Burger), zero outros locais e zero eventos futuros elegíveis no Canadá. Os dois eventos ativos encontrados em leitura limitada eram antigos, no Brasil, e não foram mostrados. Portanto o fallback real é “Explore no Remdy”, zero cartões, botão real “Explorar eventos”. NÃO usamos fixtures nas capturas V2. Arquivos antigos da V1 foram preservados, conforme a regra de não apagar.
- `whatsapp-preview.png` é uma SIMULAÇÃO visual dos metadados OG, não uma captura do WhatsApp nem um link já publicado.
- Capturas V2 reais: `john-v2-desktop-pt-BR.png`, `john-v2-mobile-pt-BR.png`, `john-v2-desktop-en.png`, `john-v2-gallery-related-pt-BR.png`. Headless isolado no SSD, galeria e seção final visíveis, imagens carregadas e sem overflow em 1280px/390px. Prova em `e2e/browser-v2-proof.json`; script reproduzível `scripts/place_page_capture.cjs`.

## Índices

As queries EXATAS V2 (cidade, recentes por updatedAt DESC, eventos futuros por isActive/countryCode/city/startAt, nacional e sitemap) funcionaram no banco real sem criar índice. Não é necessário deploy de índice novo para esta versão. `firestore.indexes.json` permaneceu inalterado. Existem três índices de places READY no projeto; definições remotas completas foram salvas apenas em `e2e/live-indexes.json`. Não publicar o arquivo geral de índices às cegas: ele não contém todos esses índices remotos e uma sincronização pode propor remoções.

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

## Arquivos adicionados/alterados na V2

`functions/public_place_logic.js`, `public_place_logic.test.js`, `public_places.js`, `public_places.test.js`, novos `public_place_recommendations.js`/`.test.js`, `functions/package.json`, `scripts/place_page_readonly_e2e.cjs`, novo `scripts/place_page_capture.cjs` e este relatório. CSS original, app, firebase.json, índices e Remdy_page não foram alterados na V2.
