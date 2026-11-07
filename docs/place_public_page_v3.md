# Locais públicos V3 — CTA de delivery exclusivamente no app

LOCAL ONLY na worktree `/Volumes/REMDY_SSD/place_page_work`. Nenhum deploy, push, merge, instalação, login, escrita em Firestore ou limpeza. Remdy_page intocado. As funções que estão no ar NÃO foram alteradas.

## Campos suportados e preenchimento real de John Burger

Fontes: `PlaceContact`/`PlaceMenu` em `lib/features/locais/models/place_listing.dart`, adaptador `firestore_place_mapper.dart` e `functions/place_submission_logic.js`. Documento `places/hPGFEU4iQbDJXItOwQhV`, leitura apenas.

| Campo persistido | Modelo do app / entrada aceita pela função | John Burger (mascarado) |
| --- | --- | --- |
| `phone` | `PlaceContact.phone`; entrada `phone` (texto, máx. 40) | vazio |
| `whatsapp` | `PlaceContact.whatsapp`; entrada `whatsapp` (texto, máx. 40) | preenchido, ••••9436 |
| `websiteUrl` | `PlaceContact.website`; entrada `websiteUrl` (HTTPS) | preenchido, instagram.com/… |
| `instagramUrl` | `PlaceContact.instagram`; mapper lê legado, `parsePlaceInput` não grava | ausente |
| `menu.pdfUrl` | `PlaceMenu.pdfUrl`; entrada `menuUrl` (HTTPS) | preenchido, *.square.site/… |
| `menu.photoUrls` | `PlaceMenu.photoUrls`; entrada `menuPhotoUrls` (URLs do Storage do local) | 1 imagem |
| `menu.enabled` | `PlaceMenu.enabled`; derivado da URL/fotos | true |
| `menu.items` | `PlaceMenu.items`: nome, descrição, preço, disponibilidade; leitura legado, sem escrita por `parsePlaceInput` | ausente |
| `menu.notice` | `PlaceMenu.notice`; leitura legado, sem escrita por `parsePlaceInput` | ausente |
| `orderUrl`, `orderingUrl`, `deliveryUrl`, `orderLink`, `deliveryLink`, `paymentUrl`, `paymentLink` | NÃO existem no modelo/API analisados | sem valores preenchidos |

O contrato local antigo serializa `contact.website`/`contact.instagram`; o documento de produção usa os campos planos mapeados acima. `menuUrl` é entrada da função, armazenada como `menu.pdfUrl`, não um campo plano persistido. Apesar do nome `pdfUrl`, no John Burger o valor é um link Square de pedidos, NÃO necessariamente PDF. A decisão mais recente cancela qualquer exposição/uso desses destinos na página web: cardápio e pedido somente dentro do app.

## Comportamento implementado

- Delivery: o chip informativo continua, mas o texto solto na área de localização foi substituído pelo CTA **“Ver cardápio e pedir”**. Cinco idiomas: pt-BR, pt-PT (“Ver ementa e pedir”), en, es, fr. A classe é exatamente a do botão de abrir app do evento: `btn btn-primary btn-wide`, com o ícone Remdy e `data-open-app`.
- Local físico: “Como chegar” nos cinco idiomas; coordenadas primeiro, ou endereço codificado como fallback. Mesmo formato do evento: `https://www.google.com/maps/search/?api=1&query=LAT,LNG`.
- IMPORTANTE: o evento ao vivo `/e/cbTY3immRDcmhhamltMd` NÃO tem um botão estilizado chamado “Como chegar”. Ele tem o link **“Abrir no Google Maps”**, sem `class` nem estilo inline: `<a href="…" target="_blank" rel="noopener noreferrer">…</a>`. Copiei esse markup exato, mudando somente o texto para “Como chegar”/traduções e o destino para o local. Não inventei fonte/cor/classe nova.
- Locais delivery ou com endereço oculto continuam sem maps/coordenadas no JSON-LD. Não publiquei contatos nem cardápio de nenhum tipo.

## Abrir app e lojas — verificações reais e proposta mais confiável

A página de evento ao vivo usa HTTPS no próprio domínio em iframe + `location.href`, com temporizador e fallback antigo genérico `https://apps.apple.com/`; não tem custom scheme/Android intent. Copiar isso não resolveria o problema de toques same-domain no Safari.

O app registra `remdy` em `ios/Runner/Info.plist`. O manifesto Android aceita HTTPS `/l/`; não registra `remdy://`. Portanto implementei:

1. iOS/iPadOS: tenta `remdy://l/<id>`. Temporizador de 1400ms cai no App Store correto. `visibilitychange`/`pagehide` cancelam o temporizador quando o app abre, evitando ir à loja ao voltar ao Safari.
2. Android: `intent://remdy.app/l/<id>#Intent;scheme=https;package=com.remdy.app;S.browser_fallback_url=…;end`, correspondente ao filtro HTTPS existente no manifesto.
3. Sem JS/desktop e como fallback Android: o link aponta para a função pública **já existente e funcionando** `https://us-central1-socialchatmvp.cloudfunctions.net/appDownloadRedirect?l=<id>`.
4. Destinos conferidos com `curl -I`, sem autenticação: iOS responde 302 para `https://apps.apple.com/br/app/id6780296747`; Android responde 302 para `https://play.google.com/store/apps/details?id=com.remdy.app`. Mesmo destino do código `appDownloadRedirect` no commit local `f8922ad`.

**Pendência externa descoberta:** `https://remdy.app/app` e `?l=<id>` responderam **404** nas três verificações (UA padrão, iPhone e Android). Por isso o botão NÃO depende desse caminho quebrado: usa a URL pública da função, que retornou 302 correto. Não alterei o site/Hosting para corrigir `/app` e não modifiquei `appDownloadRedirect`.

O `l` chega na URL de fallback, mas a função existente ignora esse parâmetro ao montar a loja. Não foi implementado deferred deep link pós-instalação. Se o app já está instalado, o scheme/intent transporta o ID e abre a ficha. A abertura real no aparelho depende do binário com o parser `/l/`; nesta tarefa não houve instalação/clique em aparelho ou login, somente testes do JS e inspeção dos registros.

## Segurança e E2E

- **181 testes npm passaram**, incluindo strings sensíveis sentinela, links/JSON-LD, idiomas, direções e JS de abertura iOS/Android, iPadOS, cancelamento dos timers e fallback desktop.
- Documento real lido sem escrita. Executei `grep -F` dos valores REAIS via stdin (sem imprimir os números/links), além da busca no HTML escapado e JSON-LD parseado: `whatsapp`, `websiteUrl`, `menu.pdfUrl`, `menu.photoUrls[0]`, em pt-BR e en: **8 verificações passaram**. Nenhum desses valores aparece no HTML/JSON-LD. `url` do JSON-LD permanece `https://remdy.app/l/<id>`; sem `menu`, `hasMenu` ou `telephone`.
- Não fiz GET/HEAD do link Square, Instagram ou WhatsApp; a verificação de destino foi redirecionada às lojas conforme a decisão mais recente. Nenhuma mensagem/pedido foi enviado.
- As 5 fotos públicas continuam 200, JSON-LD array preservado. John Burger continua somente delivery: não aparece “Como chegar” na ficha real.
- Capturas desktop 1280px e mobile 390px: botão “Ver cardápio e pedir”, sem overflow e imagens carregadas. Uma fixture física claramente marcada mostra “Como chegar”; nenhum documento foi criado.

## Artefatos

Mac: `~/remdy_e2e/place_page/`.

- `john-v3-desktop-pt-BR.png` (recorte da área do CTA real)
- `john-v3-mobile-pt-BR.png` (recorte da área do CTA real)
- `john-v3-physical-fixture.png` (fixture claramente identificada)
- `john-v3-full-desktop-pt-BR.png`, `john-v3-full-mobile-pt-BR.png`, `john-v3-full-physical-fixture.png` (páginas inteiras)
- `browser-v3-proof.json`, `readonly-v3-e2e.json`, `john-v3-fields-masked.json`, logs e este relatório.

## Deploy futuro — exige novo OK, NÃO executado

Rodar da worktree `/Volumes/REMDY_SSD/place_page_work`:

```sh
firebase deploy --project socialchatmvp --only functions:default:renderPublicPlacePage
```

Não é necessário deploy de `appDownloadRedirect`, sitemap, índices ou Hosting para esta V3. Nenhum desses arquivos/configurações foi alterado. O problema do caminho curto `/app` é separado e deve ser tratado no estágio completo do site, com autorização própria; nunca publicar Hosting desta worktree incompleta.
