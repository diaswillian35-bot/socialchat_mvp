# Descoberta de grupos — documentos legados

## Política do app (sem mutação automática)

Grupos antigos **não são reescritos** pelo cliente. A UI aplica regras defensivas:

Para Região, o perfil usa `cityLat`/`cityLng` (com fallback legado
`lat`/`lng`), sempre obtidos do resultado público da cidade selecionada no
autocomplete. O app não consulta GPS atual nem endereço residencial para essa
decisão.

| Situação | Comportamento |
|---|---|
| `scope` ausente ou não mapeável (`unknown`) | **Fora** das abas Cidade / Região / País. Continua em **Meus grupos** se o usuário for membro/owner/admin/mod. |
| `scope` legado (`cidade`, `região`, `país`, `estado`, `national`) | Normalizado em memória para `city` / `region` / `country`. |
| `country` sem `countryCode` | Deriva ISO-2 quando possível (`brasil`→`br`, etc.). Sem código confiável → fora da descoberta geográfica. |
| Cidade sem `cityKey` | Deriva de `city` / `cityName` (case/acentos/espaços). |
| `scope: region` com `regionCenterCity`, centro público, país e raio 110 | Pode aparecer em Região após filtro geohash + Haversine. |
| Regional antigo apenas com `state` / `province` / `adminArea` | **Não** define alcance. Fica fora da descoberta até correção manual. |
| Regional antigo com cidade, `placeId` e lat/lng públicas válidas | O dry-run pode propor `regionCenter*`; nenhuma escrita automática. |
| `membersCount` ausente | Usa `members.length` na UI. |
| `updatedAt` ausente | Ordenação por `lastMessageAt` → `createdAt` → fim da lista. |
| `deleted` ausente | Tratado como não apagado; `deleted == true` ou `isActive == false` ocultam. |

**Nunca** colocar um grupo `region` na aba Cidade, nem `country` em Cidade/Região. Região significa raio Haversine de até 110 km, não estado/província. Sem centro público confiável, **não** inventar coordenadas.

## Segurança (pré-deploy)

- **Fonte canônica**: Place Details no servidor (`GOOGLE_PLACES_API_KEY` no Secret Manager).
- Cliente envia preferencialmente `placeId` + labels; `regionCenter*`/`geohash`/`radiusKm` do cliente **não** são autoritativos.
- Cache: coleção `placesCache` (TTL 30 dias, Rules `read/write: if false`).
- Custo Places Details: ~US$0,017/consulta em miss; hit de cache = 1 leitura Firestore.
- `groups` Rules: `create`/`update`/`delete: if false` — mutação só via Functions.

## Índices (locais, não publicados)

Prova estrutural:

```bash
node functions/scripts/prove_group_discovery_indexes.js
# com emulator:
firebase emulators:exec --only firestore \
  "node functions/scripts/prove_group_discovery_indexes.js"
```

## Backfill (opcional, futuro)

Script idempotente (dry-run por padrão):

```bash
node functions/scripts/backfill_group_discovery_fields.js --dry-run
# só com autorização explícita:
node functions/scripts/backfill_group_discovery_fields.js --execute
```

Não executar `--execute` sem revisão. O script **não inventa** `scope` para documentos sem valor mapeável.
