/** Suspensão de moderação impede envio. Não apaga a conta. */

function moderationSendBlock(userData) {
  const status = userData && userData.moderation && userData.moderation.status;
  if (status === "suspended_pending_review" || status === "banned") {
    return "suspended";
  }
  return null;
}

/** b44: "sem falar" temporário (degraus 2 e 3). Só bloqueia quem envia. */
function moderationMuted(userData, nowMs = Date.now()) {
  return require("./ladder").isMutedNow(userData, nowMs);
}

module.exports = { moderationSendBlock, moderationMuted };
