# Fontes live consultadas somente por leitura

Horários de Toronto. `updateTime` não prova igualdade de fonte. Foram também lidos os ZIPs de origem referenciados por `buildConfig.source.storageSource`, por GET autenticado; nenhum token foi salvo. Os quatro trechos usados na reprodução estão versionados nesta pasta.

| Função | Última atualização | Hash Firebase do pacote |
|---|---|---|
| onGroupJoinRequestCreated | 06/09/2026 19:35:07 EDT | 49491554e9d896657bdd9ccf8f66ee6fdc0f7e4f |
| banGroupMember | 22/07/2026 20:28:36 EDT | c0b5224448ca53fe409aab7dc5b5b9f488cb90ef |
| removeGroupMember | 22/07/2026 20:28:41 EDT | c0b5224448ca53fe409aab7dc5b5b9f488cb90ef |
| unbanGroupMember | 22/07/2026 20:28:35 EDT | c0b5224448ca53fe409aab7dc5b5b9f488cb90ef |
| leaveGroup | 22/07/2026 20:28:46 EDT | c0b5224448ca53fe409aab7dc5b5b9f488cb90ef |
| createGroup | 06/11/2026 18:47:57 EST | 57d0b8588a99df028daeaa4a16718fab3af0c70e |
| deleteGroup | 22/07/2026 20:28:46 EDT | c0b5224448ca53fe409aab7dc5b5b9f488cb90ef |
| promoteGroupAdmin | 22/07/2026 20:28:30 EDT | c0b5224448ca53fe409aab7dc5b5b9f488cb90ef |
| updateGroupSettings | 06/11/2026 18:47:48 EST | 57d0b8588a99df028daeaa4a16718fab3af0c70e |
| joinOpenGroup | 26/07/2026 14:23:26 EDT | 25b5e20d6ca6f44fdf6f79544796f9d8e797118c |
| onGroupMessageCreated | 11/10/2026 10:08:40 EDT | acb79f3829575c2ffd1c22125e6f6536e5051f27 |
| rejectGroupJoinRequest | 25/08/2026 21:39:11 EDT | 7ffb2200088f73ab5f528e93bd7e377c00952ea8 |
| demoteGroupAdmin | 22/07/2026 20:28:47 EDT | c0b5224448ca53fe409aab7dc5b5b9f488cb90ef |
| transferGroupOwnership | 22/07/2026 20:28:46 EDT | c0b5224448ca53fe409aab7dc5b5b9f488cb90ef |
| deleteMyAccount | 22/07/2026 20:28:47 EDT | c0b5224448ca53fe409aab7dc5b5b9f488cb90ef |
| approveGroupJoinRequest | 25/08/2026 21:39:11 EDT | 7ffb2200088f73ab5f528e93bd7e377c00952ea8 |
| joinGroupByInviteCode | 22/07/2026 20:28:40 EDT | c0b5224448ca53fe409aab7dc5b5b9f488cb90ef |
| markGroupAsRead | 10/10/2026 16:18:11 EDT | 2568e7103400709e58b77c095c743f87da9dd8e2 |

As funções de julho usam onCall sem o guard de idade; a base c779572 usa socialOnCall (idade verificada). Portanto, o eventual deploy das funções alteradas também levará essa diferença pré-existente da base, não apenas a nova política de cargos. createGroup/updateGroupSettings têm handlers idênticos à base; não foram alterados nesta correção e não precisam de deploy. Os handlers de aprovação/rejeição no pacote live são reexportados por index.js de index_full.js: foram inspecionados nesse arquivo; aprovação só adiciona membros, rejeição não altera membros.
