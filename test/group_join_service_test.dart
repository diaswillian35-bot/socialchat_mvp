import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/group_join_service.dart';

void main() {
  group('GroupJoinService.normalizeInviteCode', () {
    test('trims and uppercases', () {
      expect(GroupJoinService.normalizeInviteCode('  ab12  '), 'AB12');
      expect(GroupJoinService.normalizeInviteCode(null), '');
      expect(GroupJoinService.normalizeInviteCode(''), '');
    });
  });

  group('GroupJoinService.normalizeJoinPolicy', () {
    test('maps aliases', () {
      expect(GroupJoinService.normalizeJoinPolicy(null), 'open');
      expect(GroupJoinService.normalizeJoinPolicy('open'), 'open');
      expect(GroupJoinService.normalizeJoinPolicy('approval'), 'approval');
      expect(GroupJoinService.normalizeJoinPolicy('adminApproval'), 'approval');
      expect(GroupJoinService.normalizeJoinPolicy('inviteOnly'), 'inviteOnly');
      expect(GroupJoinService.normalizeJoinPolicy('invite_only'), 'inviteOnly');
      expect(GroupJoinService.normalizeJoinPolicy('invite-only'), 'inviteOnly');
      expect(GroupJoinService.normalizeJoinPolicy('unknown'), 'open');
    });
  });

  group('GroupJoinResult', () {
    test('didEnterChat only for joined outcomes', () {
      expect(
        const GroupJoinResult(outcome: GroupJoinOutcome.joined).didEnterChat,
        true,
      );
      expect(
        const GroupJoinResult(outcome: GroupJoinOutcome.alreadyMember)
            .didEnterChat,
        true,
      );
      expect(
        const GroupJoinResult(outcome: GroupJoinOutcome.pendingCreated)
            .didEnterChat,
        false,
      );
      expect(
        const GroupJoinResult(outcome: GroupJoinOutcome.banned).didEnterChat,
        false,
      );
    });
  });

  group('GroupJoinService.unreadAfterJoin', () {
    test('preserves existing unread counters and initializes new member', () {
      final result = GroupJoinService.unreadAfterJoin(
        <String, dynamic>{
          'unread': <String, dynamic>{'owner': 4, 'member': 2},
        },
        'new-member',
      );

      expect(result, <String, dynamic>{
        'owner': 4,
        'member': 2,
        'new-member': 0,
      });
    });

    test('membersAfterOpenJoin preserva itens e só acrescenta uid', () {
      final next = GroupJoinService.membersAfterOpenJoin(
        <String, dynamic>{
          'members': <dynamic>['owner', '', 'member'],
        },
        'new-uid',
      );
      expect(next, <dynamic>['owner', '', 'member', 'new-uid']);
    });

    test('membersAfterOpenJoin é idempotente se já membro', () {
      final next = GroupJoinService.membersAfterOpenJoin(
        <String, dynamic>{
          'members': <dynamic>['owner', 'new-uid'],
        },
        'new-uid',
      );
      expect(next, <dynamic>['owner', 'new-uid']);
    });

    test('membersAfterOpenJoin cria lista para documento legado', () {
      expect(
        GroupJoinService.membersAfterOpenJoin(
          <String, dynamic>{'members': null},
          'new-uid',
        ),
        <dynamic>['new-uid'],
      );
    });
  });
}
