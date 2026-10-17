# Locais – avaliações (build 38): o que falta publicar

Nada disto foi publicado. Código pronto localmente na branch feat/remdy-build38.

## Regras de autoria (implementadas)
- 1 avaliação por usuário por local: doc `places/{placeId}/reviews/{uid}`.
- Só o autor cria/edita a própria (estrelas + texto); edição volta para `pending` (re-moderação) e retira a contribuição antiga do agregado.
- Dono/gestor: não pode avaliar o próprio local, não altera estrelas/texto/status; só escreve `ownerReply` (função `replyPlaceReview` grava apenas esse campo; não pode responder a si mesmo).
- Admin Remdy (portal `moderateReview`): só muda `status` (approved/rejected/hidden), nunca estrelas ou texto.
- Anônimo: `anonymous: true` grava "Anônimo" e sem foto; a listagem mascara de novo na leitura e nunca devolve uid.

## Firestore rules (portal repo `remdy-events-web/firestore.rules`, deploy de lá)
Regras ao vivo já negam toda escrita de cliente:
```
match /places/{placeId}/reviews/{reviewId} {
  allow get: if signedIn() && reviewId == uid();
  allow list: if false;
  allow create, update, delete: if false;   // só Admin SDK (funções)
}
```
Nenhuma mudança de regra é necessária. Índices: nenhum composto novo (consultas de igualdade/`in` em um campo).
