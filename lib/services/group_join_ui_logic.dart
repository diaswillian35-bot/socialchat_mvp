/// Lógica pura do fluxo "Entrar no grupo" (testável sem Firebase/UI).
///
/// Responsável por:
/// - guardar double-tap (`canStartJoin`);
/// - decidir o efeito de UI a partir do [GroupJoinOutcome];
/// - mapear erros de rede/timeout para chaves de tradução;
/// - garantir que o spinner do botão sempre encerra (`joining` → false).
import 'package:socialchat_mvp/services/group_join_service.dart';

enum GroupJoinUiEffect {
  /// Liberar botão; nada mais.
  idle,

  /// Mostrar spinner no botão e bloquear novos toques.
  showJoining,

  /// Entrou (ou já era membro): abrir chat / sair do preview.
  enterChat,

  /// Pedido de aprovação criado ou já existente.
  showPending,

  /// Banido.
  showBanned,

  /// Free bloqueado em grupo internacional → popup Premium.
  showPremiumRequired,

  /// Convite inválido / grupo indisponível / apagado.
  showUnavailable,

  /// Somente por convite (sem código).
  showInviteOnly,

  /// Rede / timeout → mensagem + retry.
  showNetworkError,

  /// Não autenticado.
  showLoginRequired,

  /// Erro genérico (detalhe só em debug).
  showGenericError,
}

class GroupJoinUiDecision {
  const GroupJoinUiDecision({
    required this.effect,
    required this.clearJoining,
    this.messageKey,
    this.debugDetail,
  });

  final GroupJoinUiEffect effect;

  /// Sempre true ao concluir uma tentativa — o botão NUNCA fica preso.
  final bool clearJoining;

  final String? messageKey;
  final String? debugDetail;
}

class GroupJoinUiLogic {
  GroupJoinUiLogic._();

  /// Proteção de double-tap: se já está entrando, ignore o novo toque.
  static bool canStartJoin({required bool isJoining, required bool isBanned}) {
    if (isJoining) return false;
    if (isBanned) return false;
    return true;
  }

  /// Após o usuário tocar em entrar (antes da chamada async).
  static GroupJoinUiDecision beginJoin() {
    return const GroupJoinUiDecision(
      effect: GroupJoinUiEffect.showJoining,
      clearJoining: false,
    );
  }

  /// Mapeia o resultado do serviço para a UI. Sempre `clearJoining: true`.
  static GroupJoinUiDecision fromResult(GroupJoinResult result) {
    switch (result.outcome) {
      case GroupJoinOutcome.joined:
      case GroupJoinOutcome.alreadyMember:
        return GroupJoinUiDecision(
          effect: GroupJoinUiEffect.enterChat,
          clearJoining: true,
          messageKey: result.messageKey,
        );
      case GroupJoinOutcome.pendingCreated:
      case GroupJoinOutcome.pendingExists:
        return GroupJoinUiDecision(
          effect: GroupJoinUiEffect.showPending,
          clearJoining: true,
          messageKey: result.messageKey,
        );
      case GroupJoinOutcome.banned:
        return GroupJoinUiDecision(
          effect: GroupJoinUiEffect.showBanned,
          clearJoining: true,
          messageKey: result.messageKey,
        );
      case GroupJoinOutcome.premiumRequired:
        return GroupJoinUiDecision(
          effect: GroupJoinUiEffect.showPremiumRequired,
          clearJoining: true,
          messageKey: result.messageKey,
        );
      case GroupJoinOutcome.groupFull:
        return GroupJoinUiDecision(
          effect: GroupJoinUiEffect.showUnavailable,
          clearJoining: true,
          messageKey: result.messageKey,
        );
      case GroupJoinOutcome.inviteOnlyDenied:
        return GroupJoinUiDecision(
          effect: GroupJoinUiEffect.showInviteOnly,
          clearJoining: true,
          messageKey: result.messageKey,
        );
      case GroupJoinOutcome.invalidInvite:
      case GroupJoinOutcome.groupUnavailable:
      case GroupJoinOutcome.wrongJoinPolicy:
        return GroupJoinUiDecision(
          effect: GroupJoinUiEffect.showUnavailable,
          clearJoining: true,
          messageKey: result.messageKey,
        );
      case GroupJoinOutcome.notAuthenticated:
        return GroupJoinUiDecision(
          effect: GroupJoinUiEffect.showLoginRequired,
          clearJoining: true,
          messageKey: result.messageKey,
        );
      case GroupJoinOutcome.networkError:
        return GroupJoinUiDecision(
          effect: GroupJoinUiEffect.showNetworkError,
          clearJoining: true,
          messageKey: result.messageKey,
          debugDetail: result.errorDetail,
        );
      case GroupJoinOutcome.error:
        return GroupJoinUiDecision(
          effect: GroupJoinUiEffect.showGenericError,
          clearJoining: true,
          messageKey: result.messageKey,
          debugDetail: result.errorDetail,
        );
    }
  }

  /// Free + grupo internacional (antes de chamar o serviço).
  static GroupJoinUiDecision premiumRequired() {
    return const GroupJoinUiDecision(
      effect: GroupJoinUiEffect.showPremiumRequired,
      clearJoining: true,
      messageKey: 'group_premium_other_country',
    );
  }

  /// Exceção inesperada fora do serviço.
  static GroupJoinUiDecision fromUnexpected(Object error) {
    return GroupJoinUiDecision(
      effect: GroupJoinUiEffect.showGenericError,
      clearJoining: true,
      messageKey: 'group_error_join_prefix',
      debugDetail: error.toString(),
    );
  }

  /// Página desmontada no meio do join: ainda assim o flag deve limpar se
  /// o State voltar a montar; o efeito é idle (sem toast/nav).
  static GroupJoinUiDecision pageUnmounted() {
    return const GroupJoinUiDecision(
      effect: GroupJoinUiEffect.idle,
      clearJoining: true,
    );
  }

  /// Placeholder de mensagens no preview: NUNCA spinner eterno.
  static bool shouldShowMessagesSpinner({
    required bool isMember,
    required bool hasData,
    required bool hasError,
    required bool waiting,
    required bool hasCachedDocs,
  }) {
    if (!isMember) return false;
    if (hasError) return false;
    if (hasData || hasCachedDocs) return false;
    return waiting;
  }

  /// Em preview (não-membro), não assinar messages/presence (Rules negam).
  static bool shouldListenToMemberStreams({
    required bool isMember,
    required bool isBanned,
  }) {
    return isMember && !isBanned;
  }
}
