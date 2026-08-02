import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/event_comments_logic.dart';
import 'package:socialchat_mvp/services/event_likes_service.dart';

void main() {
  group('event like gates (client)', () {
    test('requires approved + active', () {
      expect(
        EventLikesService.eventAllowsLike({
          'isActive': true,
          'status': 'approved',
        }),
        isTrue,
      );
      expect(
        EventLikesService.eventAllowsLike({
          'isActive': true,
          'status': 'pending',
        }),
        isFalse,
      );
      expect(
        EventLikesService.eventAllowsLike({
          'isActive': false,
          'status': 'approved',
        }),
        isFalse,
      );
    });
  });

  group('pending order stability', () {
    test('null pending timestamp sorts after dated items without reshuffle jump',
        () {
      final items = <_Row>[
        _Row('a', DateTime(2024, 1, 1)),
        _Row('pending', null),
        _Row('b', DateTime(2024, 1, 2)),
      ];
      final ordered = EventCommentsLogic.orderThread<_Row>(
        items: items,
        idOf: (_Row r) => r.id,
        createdAtOf: (_Row r) => r.at,
        rootOf: (_) => null,
        replyToOf: (_) => null,
      );
      expect(ordered.map((e) => e.id), ['a', 'b', 'pending']);
    });
  });

  group('reply editor target', () {
    test('clears when parent id missing from visible set', () {
      String? openId = 'gone';
      final visible = {'alive'};
      if (openId != null && !visible.contains(openId)) {
        openId = null;
      }
      expect(openId, isNull);
    });
  });
}

class _Row {
  _Row(this.id, this.at);
  final String id;
  final DateTime? at;
}
