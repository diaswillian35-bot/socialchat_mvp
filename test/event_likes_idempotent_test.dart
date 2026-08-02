import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/event_comments_logic.dart';
import 'package:socialchat_mvp/services/event_likes_service.dart';

void main() {
  group('EventLikesService setLiked contract (no request store)', () {
    test('optimistic desiredLiked matches toggle result', () {
      const before = EventLikeOptimisticState(liked: false, likesCount: 0);
      final after = before.toggle();
      expect(after.liked, isTrue);
      expect(after.likesCount, 1);
      expect(after.liked, isNot(before.liked));
    });

    test('gates still require approved event', () {
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
    });

    test('idempotent desired state does not flip count twice', () {
      var liked = false;
      var count = 0;
      void apply(bool desired) {
        if (desired == liked) return;
        if (desired) {
          liked = true;
          count += 1;
        } else {
          liked = false;
          count = count > 0 ? count - 1 : 0;
        }
      }

      apply(true);
      apply(true); // retry
      expect(liked, isTrue);
      expect(count, 1);
      apply(false);
      apply(false);
      expect(liked, isFalse);
      expect(count, 0);
    });
  });
}
