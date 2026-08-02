# Events Discover v1 — campos Firestore e fallbacks

Sem migração/backfill nesta etapa. Eventos antigos continuam legíveis.

## Documento `events/{id}` — usados na UI nova

| Campo | Uso | Fallback se ausente |
|-------|-----|---------------------|
| `title` | Card, detalhes, share | `eventTitle` → `name` → chave l10n `events_default_category` |
| `coverUrl` | Capa card/hero/share | primeira de `photoUrls`; senão placeholder Remdy |
| `photoUrls` | Galeria | `[]` — esconde aba Galeria |
| `logoUrl` | Share (centro) se portal | omitir logo do evento |
| `category` / `type` | Badge categoria | omitir badge |
| `startAt` | Data/hora, seções Hoje/Próximos | “sem data” l10n |
| `endAt` | Intervalo de datas se existir | só `startAt` |
| `city` | Localização | omitir cidade |
| `stateName` | Região/estado | omitir |
| `countryCode` | País via `IsoCountryNames` | omitir país |
| `placeName` / `placeDisplay` / `address` | Local / mapa | “TBD” l10n |
| `lat` / `lng` | Perto de você | excluir do filtro de distância |
| `cityKey` / `regionKey` / `countryCode` | Queries | — |
| `description` / `desc` / `about` / `sobre` | Aba Sobre | esconder aba se vazio **e** sem comentários/join? (Sobre sempre se houver join) |
| `attendeesCount` / `attendeesUids` | Pessoas | `0` |
| `likesCount` | Curtidas | `0` |
| `status` | Confirmado / cancelado | tratado como não confirmado se ≠ approved |
| `isActive` | Listagens | só `true` nas queries |
| `deleted` | Soft-delete | filtrar client-side |
| `sponsored` / `featured` / `featuredUntil` | Em destaque / Em alta | featured→sponsored→likes |
| `price` / `ticketInfo` / `isFree` | Preço | **não inventar**; mostrar só se campo existir |
| `schedule` / `programacao` / `attractions` / `attractions` | Abas | se ausente/vazio → **esconder aba** |

## Subcoleções (inalteradas)

- `likes/{uid}`, `comments`, `attendees/{uid}`, `views/{uid}`

## Compatibilidade

- Eventos só do app mobile: sem `logoUrl`/`endAt`/preço/programação → UI degrada com abas ocultas.
- Eventos do portal podem trazer `logoUrl` e `endAt`.
- País **nunca** hardcoded; sempre `IsoCountryNames.displayName(countryCode, lang)`.

## Share

- Link público: `https://remdy.app/e/{eventId}`
- Imagem: geração **local** (RepaintBoundary / dart:ui), cache temp no device; **sem** upload Firebase por share.
