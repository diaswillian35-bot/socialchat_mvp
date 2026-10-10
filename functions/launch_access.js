/**
 * Interruptor único do lançamento gratuito (BR/CA, sem compras).
 *
 * freeLaunchActive === true:
 *   claimInvitePremiumReward e applyInviteCode não concedem
 *   premiumUntil nem recompensa, inclusive em chamada direta.
 *
 * O webhook e o sync do RevenueCat ficam de fora deste interruptor.
 * No Android as compras continuam ativas; esses handlers só espelham
 * um entitlement já pago e não criam recompensa de convite.
 *
 * Para reativar as recompensas, mude somente esta constante para false.
 * A lógica de marcos permanece no código.
 */
const freeLaunchActive = true;

function premiumGrantsEnabled() {
  return freeLaunchActive !== true;
}

/**
 * Resposta genérica. Não inclui contagem de convites, datas,
 * estado da conta nem entitlement.
 */
function premiumGrantDeniedBody() {
  return {
    success: false,
    available: false,
    granted: false,
    applied: false,
    rewardGranted: false,
  };
}

module.exports = {
  freeLaunchActive,
  premiumGrantsEnabled,
  premiumGrantDeniedBody,
};
