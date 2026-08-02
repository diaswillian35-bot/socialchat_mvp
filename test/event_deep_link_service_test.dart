import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/event_deep_link_service.dart';

void main() {
  group('EventDeepLinkService.parseEventId', () {
    test('accepts remdy.app /e/ /events/ /event/', () {
      expect(
        EventDeepLinkService.parseEventId(
          Uri.parse('https://remdy.app/e/abc123'),
        ),
        'abc123',
      );
      expect(
        EventDeepLinkService.parseEventId(
          Uri.parse('https://www.remdy.app/events/Evt_1'),
        ),
        'Evt_1',
      );
      expect(
        EventDeepLinkService.parseEventId(
          Uri.parse('https://remdy.app/event/xyz'),
        ),
        'xyz',
      );
    });

    test('rejects bad host or id', () {
      expect(
        EventDeepLinkService.parseEventId(
          Uri.parse('https://evil.com/e/abc'),
        ),
        isNull,
      );
      expect(
        EventDeepLinkService.parseEventId(
          Uri.parse('https://remdy.app/e/bad id'),
        ),
        isNull,
      );
      expect(
        EventDeepLinkService.parseEventId(Uri.parse('https://remdy.app/e/')),
        isNull,
      );
    });
  });
}
