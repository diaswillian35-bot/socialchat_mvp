import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/group_pending_join_badge_logic.dart';

void main() {
  group('GroupPendingJoinBadgeLogic permission', () {
    test('owner and admin only', () {
      expect(
        GroupPendingJoinBadgeLogic.isOwnerOrAdmin(
          data: {'ownerId': 'o1', 'admins': []},
          uid: 'o1',
        ),
        isTrue,
      );
      expect(
        GroupPendingJoinBadgeLogic.isOwnerOrAdmin(
          data: {
            'ownerId': 'o1',
            'admins': ['a1'],
          },
          uid: 'a1',
        ),
        isTrue,
      );
      expect(
        GroupPendingJoinBadgeLogic.isOwnerOrAdmin(
          data: {
            'ownerId': 'o1',
            'admins': ['a1'],
            'members': ['m1'],
          },
          uid: 'm1',
        ),
        isFalse,
      );
    });

    test('watches only approval + moderator role', () {
      expect(
        GroupPendingJoinBadgeLogic.watchesPendingForGroup(
          data: {
            'ownerId': 'o1',
            'joinPolicy': 'approval',
          },
          uid: 'o1',
        ),
        isTrue,
      );
      expect(
        GroupPendingJoinBadgeLogic.watchesPendingForGroup(
          data: {
            'ownerId': 'o1',
            'joinPolicy': 'open',
          },
          uid: 'o1',
        ),
        isFalse,
      );
      expect(
        GroupPendingJoinBadgeLogic.watchesPendingForGroup(
          data: {
            'ownerId': 'o1',
            'joinPolicy': 'approval',
          },
          uid: 'member',
        ),
        isFalse,
      );
    });
  });

  group('GroupPendingJoinBadgeLogic counting', () {
    test('counts pending only and dedupes ids', () {
      final n = GroupPendingJoinBadgeLogic.countPendingDocs([
        MapEntry('u1', {'status': 'pending'}),
        MapEntry('u1', {'status': 'pending'}),
        MapEntry('u2', {'status': 'approved'}),
        MapEntry('u3', {'status': 'rejected'}),
        MapEntry('u4', {'status': 'pending'}),
        MapEntry('u5', {'status': 'cancelled'}),
      ]);
      expect(n, 2);
    });

    test('sum and format 99+', () {
      expect(
        GroupPendingJoinBadgeLogic.sumGroupCounts({'a': 2, 'b': 0, 'c': 3}),
        5,
      );
      expect(GroupPendingJoinBadgeLogic.formatBadge(0), isNull);
      expect(GroupPendingJoinBadgeLogic.formatBadge(1), '1');
      expect(GroupPendingJoinBadgeLogic.formatBadge(99), '99');
      expect(GroupPendingJoinBadgeLogic.formatBadge(100), '99+');
    });
  });
}
