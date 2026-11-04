/** Suspensão de moderação impede envio. Não apaga a conta. */

function moderationSendBlock(userData) {
  const status = userData && userData.moderation && userData.moderation.status;
  if (status === "suspended_pending_review" || status === "banned") {
    return "suspended";
  }
  return null;
}

module.exports = { moderationSendBlock };
