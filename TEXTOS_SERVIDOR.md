# Textos no servidor que ainda precisam de deploy

Inventário local (build 44, branch `feat/b44-erros-auth`). Nada disto foi alterado nem implantado.

Os pushes e erros abaixo saem das Cloud Functions (`functions/`). Enquanto não houver um deploy com i18n, o utilizador pode recebê-los só em português, só em inglês, ou num subconjunto dos 5 idiomas.

## Pushes e avisos no app

| Ficheiro | Linha | Texto (pt-BR / idioma original) |
|---|---|---|
| functions/index.js | 691 | Nova mensagem |
| functions/index.js | 1593 | Seu evento |
| functions/index.js | 1607 | Evento aprovado |
| functions/index.js | 1615 | Evento rejeitado |
| functions/index.js | 1633 | Alterações solicitadas |
| functions/index.js | 1641 | Alterações aprovadas |
| functions/index.js | 1652 | Alterações enviadas |
| functions/index.js | 1665 | Novo evento |
| functions/index.js | 1757 | 📍 Novo evento perto de você |
| functions/index.js | 1766 | 📍 Nuevo evento cerca de ti (já tem es; faltam os outros) |
| functions/index.js | 1771 | 📍 Nouvel événement près de vous (já tem fr) |
| functions/index.js | 3624 | Sua solicitação foi aprovada. |
| functions/index.js | 3625 | Solicitação não aprovada |
| functions/index.js | 3628 | Sua solicitação para entrar no grupo não foi aprovada. |
| functions/index.js | 4736 | Novo comentário no evento |
| functions/group_join_request_push_logic.js | 48 | Nova solicitação |
| functions/on_report_created.js | 248 | Nova denúncia |
| functions/place_actions.js | 111 | Nova avaliação |
| functions/place_admin_notice_logic.js | 9 | Novo local em análise |
| functions/place_moderation_push_logic.js | 9 | {name} foi aprovado e já aparece em Locais. |
| functions/place_moderation_push_logic.js | 10 | Local não aprovado |
| functions/place_moderation_push_logic.js | 11 | {name} não foi aprovado. |
| functions/place_moderation_push_logic.js | 36–38 | Já há pares em fr (Lieu approuvé / non approuvé); completar pt-PT, en, es |
| functions/audio_room_logic.js | 139–140 | Textos de sala ao vivo já existem em es e fr; completar os 5 idiomas |
| functions/moderation/notices.js | 8 | Aviso: sua mensagem quebrou as regras. Na próxima vez, você ficará 24 h sem enviar mensagens. |
| functions/moderation/notices.js | 9 | Aviso: a sua mensagem violou as regras. Da próxima vez, ficará 24 h sem enviar mensagens. (pt-PT) |
| functions/moderation/notices.js | 15–18 | Aviso de suspensão até {until} (já há pt-BR, pt-PT e es; faltam en e fr) |
| functions/event_social_ensure.js | 103 | Evento Remdy (texto da imagem social) |
| functions/event_social_image.js | 167 | Evento Remdy |
| lib/services/new_user_policy.dart | — | "Novas pessoas chegaram à Remdy. Venha dar um oi!" — o app já tem chave `new_users_push_body`, mas o lote de push no servidor está desligado (`pushBatchEnabled = false`). Quando for ligado, o envio tem de usar o idioma do destinatário. |

## Página pública de locais (HTML gerado na Function)

| Ficheiro | Linha | Texto |
|---|---|---|
| functions/public_place_logic.js | 10 | Buscar eventos, cidades... |
| functions/public_place_logic.js | 11 | Pesquisar eventos, cidades... (pt-PT) |
| functions/public_place_logic.js | 13 | Buscar eventos, ciudades... (es) |
| functions/public_place_logic.js | 24 | Novos locais e eventos públicos aparecerão aqui quando estiverem disponíveis. |
| functions/public_place_logic.js | 27 | Los nuevos lugares y eventos públicos aparecerán aquí cuando estén disponibles. |

Faltam en e fr (e revisar paridade dos 5 idiomas). Esta página só atualiza com deploy das Functions.

## Erros das callable Functions (HttpsError)

Muitos ainda estão só em inglês. Se algum ecrã mostrar `e.message` em vez de uma chave do AppTexts, o utilizador vê o inglês. Exemplos:

| Ficheiro | Linha | Texto |
|---|---|---|
| functions/age_verification.js | 15 | Policy version is outdated. |
| functions/age_verification.js | 18 | Invalid date of birth. |
| functions/age_verification.js | 32 | Date of birth can only be corrected through support. |
| functions/age_verification.js | 35 | Remdy is only for adults. |
| functions/delete_my_account.js | 531 | Account data cleaned but auth delete failed. Please retry. |
| functions/delete_my_account.js | 572 | Could not delete account. Please retry. |
| functions/dm_reply_quota.js | 216 | Premium required for this international conversation. |
| functions/dm_reply_quota.js | 226 | Only text is allowed under the free reply allowance. |
| functions/dm_reply_quota.js | 232 | Message text is required. |
| functions/dm_reply_quota.js | 260 | Free reply allowance exhausted for this conversation. |
| functions/event_editorial.js | 165 | Too many photos. |
| functions/forward_message.js | 57 | Rate limit exceeded. |
| functions/forward_message.js | 140 | Message not found. |
| functions/group_bio_logic.js | 9 | Bio too long. |
| functions/index.js | 467 | Premium required for international groups. |
| functions/index.js | 1907 | Could not join group. |
| functions/index.js | 1928 | Invalid invite code. |
| functions/index.js | 1940 | Account is banned. |
| functions/index.js | 1964 | Group not found. |
| functions/index.js | 1994 | Cannot join this group. |
| functions/index.js | 2111 | Cannot ban the owner. |
| functions/index.js | 3464 | Group owner limit reached. |
| functions/index.js | 3586 | Could not create group. |
| functions/index.js | 3074 | Account is disabled. |
| functions/index.js | 3120 | Name is required. |

Há dezenas de mensagens no mesmo estilo em `functions/index.js` (ban, unban, promote, demote, leave, delete, update, create). Não foram alteradas.

## E-mails

Não foi encontrada função de envio de e-mail transacional neste repositório (sem nodemailer / sendMail). E-mails de verificação e de redefinição de senha continuam a cargo do Firebase Auth.

## Fora deste inventário (de propósito)

- `console.log` / `functions.logger` e comentários internos
- Listas de frases do bot / filtro (`falo português`, `trabalho na construção`, etc.)
- Identificadores, códigos de erro e chaves de analytics
- Assets de imagem em `functions/assets/`
