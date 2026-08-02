import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/event_comments_service.dart';

void main() {
  group('EventCommentsService helpers', () {
    test('asInt handles num and null', () {
      expect(EventCommentsService.asInt(3), 3);
      expect(EventCommentsService.asInt(3.9), 3);
      expect(EventCommentsService.asInt(null), 0);
      expect(EventCommentsService.asInt('x', 7), 7);
    });

    test('asUidList filters', () {
      expect(EventCommentsService.asUidList(null), isEmpty);
      expect(EventCommentsService.asUidList(['a', '', 1]), ['a', '1']);
    });

    test('requestId format', () {
      final id = EventCommentsService.newRequestId();
      expect(id.startsWith('c_'), isTrue);
      expect(id.length, greaterThanOrEqualTo(8));
    });
  });
}
