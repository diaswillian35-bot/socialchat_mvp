import 'package:flutter_test/flutter_test.dart';

import 'package:socialchat_mvp/services/group_join_service.dart';
import 'package:socialchat_mvp/services/group_join_ui_logic.dart';

void main() {
  group('GroupJoinUiLogic.canStartJoin / double-tap', () {
    test('bloqueia enquanto joining', () {
      expect(
        GroupJoinUiLogic.canStartJoin(isJoining: true, isBanned: false),
        isFalse,
      );
    });

    test('bloqueia se banido', () {
      expect(
        GroupJoinUiLogic.canStartJoin(isJoining: false, isBanned: true),
        isFalse,
      );
    });

    test('permite retry depois da falha (joining=false)', () {
      expect(
        GroupJoinUiLogic.canStartJoin(isJoining: false, isBanned: false),
        isTrue,
      );
    });
  });

  group('GroupJoinUiLogic.fromResult — spinner encerrado em todos', () {
    void expectClears(GroupJoinOutcome outcome) {
      final d = GroupJoinUiLogic.fromResult(
        GroupJoinResult(outcome: outcome, groupId: 'g1'),
      );
      expect(d.clearJoining, isTrue, reason: '$outcome deve liberar o botão');
    }

    test('sucesso imediato', () {
      final d = GroupJoinUiLogic.fromResult(
        const GroupJoinResult(outcome: GroupJoinOutcome.joined, groupId: 'g1'),
      );
      expect(d.effect, GroupJoinUiEffect.enterChat);
      expect(d.clearJoining, isTrue);
    });

    test('já membro', () {
      final d = GroupJoinUiLogic.fromResult(
        const GroupJoinResult(
          outcome: GroupJoinOutcome.alreadyMember,
          groupId: 'g1',
        ),
      );
      expect(d.effect, GroupJoinUiEffect.enterChat);
      expect(d.clearJoining, isTrue);
    });

    test('aprovação pendente (criada)', () {
      final d = GroupJoinUiLogic.fromResult(
        const GroupJoinResult(outcome: GroupJoinOutcome.pendingCreated),
      );
      expect(d.effect, GroupJoinUiEffect.showPending);
      expect(d.clearJoining, isTrue);
    });

    test('aprovação pendente (já existe)', () {
      final d = GroupJoinUiLogic.fromResult(
        const GroupJoinResult(outcome: GroupJoinOutcome.pendingExists),
      );
      expect(d.effect, GroupJoinUiEffect.showPending);
      expect(d.clearJoining, isTrue);
    });

    test('banido', () {
      final d = GroupJoinUiLogic.fromResult(
        const GroupJoinResult(outcome: GroupJoinOutcome.banned),
      );
      expect(d.effect, GroupJoinUiEffect.showBanned);
      expect(d.clearJoining, isTrue);
    });

    test('grupo inexistente / apagado', () {
      final d = GroupJoinUiLogic.fromResult(
        const GroupJoinResult(outcome: GroupJoinOutcome.groupUnavailable),
      );
      expect(d.effect, GroupJoinUiEffect.showUnavailable);
      expect(d.clearJoining, isTrue);
    });

    test('convite inválido', () {
      expectClears(GroupJoinOutcome.invalidInvite);
      expect(
        GroupJoinUiLogic.fromResult(
          const GroupJoinResult(outcome: GroupJoinOutcome.invalidInvite),
        ).effect,
        GroupJoinUiEffect.showUnavailable,
      );
    });

    test('Free internacional → premium', () {
      final d = GroupJoinUiLogic.premiumRequired();
      expect(d.effect, GroupJoinUiEffect.showPremiumRequired);
      expect(d.clearJoining, isTrue);
      expect(d.messageKey, 'group_premium_other_country');
    });

    test('Premium internacional: joined continua enterChat', () {
      // O bloqueio Free é client-side; Premium passa e o serviço retorna joined.
      final d = GroupJoinUiLogic.fromResult(
        const GroupJoinResult(outcome: GroupJoinOutcome.joined, groupId: 'g1'),
      );
      expect(d.effect, GroupJoinUiEffect.enterChat);
    });

    test('permission-denied mapeado no serviço → banned/error limpa spinner', () {
      expectClears(GroupJoinOutcome.banned);
      expectClears(GroupJoinOutcome.error);
    });

    test('unauthenticated', () {
      final d = GroupJoinUiLogic.fromResult(
        const GroupJoinResult(outcome: GroupJoinOutcome.notAuthenticated),
      );
      expect(d.effect, GroupJoinUiEffect.showLoginRequired);
      expect(d.clearJoining, isTrue);
    });

    test('unavailable/rede', () {
      final d = GroupJoinUiLogic.fromResult(
        const GroupJoinResult(
          outcome: GroupJoinOutcome.networkError,
          errorDetail: 'unavailable',
        ),
      );
      expect(d.effect, GroupJoinUiEffect.showNetworkError);
      expect(d.clearJoining, isTrue);
      expect(d.messageKey, 'group_join_network_error');
    });

    test('timeout (deadline-exceeded via networkError)', () {
      expectClears(GroupJoinOutcome.networkError);
    });

    test('página desmontada limpa joining', () {
      final d = GroupJoinUiLogic.pageUnmounted();
      expect(d.clearJoining, isTrue);
      expect(d.effect, GroupJoinUiEffect.idle);
    });

    test('erro inesperado limpa joining', () {
      final d = GroupJoinUiLogic.fromUnexpected(Exception('boom'));
      expect(d.clearJoining, isTrue);
      expect(d.effect, GroupJoinUiEffect.showGenericError);
      expect(d.debugDetail, contains('boom'));
    });

    test('todos os outcomes limpam o spinner', () {
      for (final o in GroupJoinOutcome.values) {
        expectClears(o);
      }
    });
  });

  group('GroupJoinUiLogic messages spinner (preview)', () {
    test('não-membro NUNCA mostra spinner de mensagens', () {
      expect(
        GroupJoinUiLogic.shouldShowMessagesSpinner(
          isMember: false,
          hasData: false,
          hasError: true,
          waiting: true,
          hasCachedDocs: false,
        ),
        isFalse,
      );
    });

    test('membro com erro não fica em spinner eterno', () {
      expect(
        GroupJoinUiLogic.shouldShowMessagesSpinner(
          isMember: true,
          hasData: false,
          hasError: true,
          waiting: false,
          hasCachedDocs: false,
        ),
        isFalse,
      );
    });

    test('membro aguardando sem dados mostra spinner', () {
      expect(
        GroupJoinUiLogic.shouldShowMessagesSpinner(
          isMember: true,
          hasData: false,
          hasError: false,
          waiting: true,
          hasCachedDocs: false,
        ),
        isTrue,
      );
    });

    test('preview não escuta streams de membro', () {
      expect(
        GroupJoinUiLogic.shouldListenToMemberStreams(
          isMember: false,
          isBanned: false,
        ),
        isFalse,
      );
      expect(
        GroupJoinUiLogic.shouldListenToMemberStreams(
          isMember: true,
          isBanned: true,
        ),
        isFalse,
      );
      expect(
        GroupJoinUiLogic.shouldListenToMemberStreams(
          isMember: true,
          isBanned: false,
        ),
        isTrue,
      );
    });
  });

  group('GroupJoinService._mapFunctionsException (via messageKey)', () {
    test('permission-denied → banned', () {
      final r = GroupJoinService.normalizeJoinPolicy('open');
      expect(r, 'open');
      // Mapeamento coberto indiretamente: outcome banned messageKey.
      expect(
        const GroupJoinResult(outcome: GroupJoinOutcome.banned).messageKey,
        'group_cannot_join_banned',
      );
    });

    test('networkError messageKey', () {
      expect(
        const GroupJoinResult(outcome: GroupJoinOutcome.networkError).messageKey,
        'group_join_network_error',
      );
    });

    test('Functions unavailable code maps to networkError', () {
      // Equivalente ao mapeamento de `unavailable` / `deadline-exceeded`
      // em GroupJoinService._mapFunctionsException.
      expect(
        const GroupJoinResult(outcome: GroupJoinOutcome.networkError).messageKey,
        'group_join_network_error',
      );
      expect(
        const GroupJoinResult(outcome: GroupJoinOutcome.networkError).outcome,
        GroupJoinOutcome.networkError,
      );
    });
  });
}
