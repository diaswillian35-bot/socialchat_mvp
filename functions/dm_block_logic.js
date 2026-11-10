/**
 * b44: "Bloquear mensagens privadas" (users/{uid}.dmBlocked + dmAllowExisting).
 * Vale nos dois sentidos e sem exceção para admin, como o Só explorar.
 * Com dmAllowExisting, conversas que já têm mensagem continuam.
 * Mesma lógica de firestore.rules (dmBlockedBy).
 */

function sideBlocksDm(userData, hasHistory) {
  if (!userData || userData.dmBlocked !== true) return false;
  return !(userData.dmAllowExisting === true && hasHistory === true);
}

function conversationHasHistory(convData) {
  return Boolean(convData && String(convData.lastMessage || "").trim());
}

/** true se o PV entre os dois está bloqueado por qualquer um dos lados. */
function dmBlockedBetween(senderData, recipientData, opts = {}) {
  const h = opts.hasHistory === true;
  return sideBlocksDm(recipientData, h) || sideBlocksDm(senderData, h);
}

module.exports = { sideBlocksDm, conversationHasHistory, dmBlockedBetween };
