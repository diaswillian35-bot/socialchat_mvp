import 'package:flutter_test/flutter_test.dart';

import 'package:socialchat_mvp/services/dm_reply_quota.dart';

void main() {
  group('DmReplyQuota.countCodePoints', () {
    test('ascii spaces and accents', () {
      expect(DmReplyQuota.countCodePoints(''), 0);
      expect(DmReplyQuota.countCodePoints('abc'), 3);
      expect(DmReplyQuota.countCodePoints('a b'), 3);
      expect(DmReplyQuota.countCodePoints('ação'), 4);
      expect(DmReplyQuota.countCodePoints('a\nb'), 3);
    });

    test('emoji code points', () {
      expect(DmReplyQuota.countCodePoints('😀'), 1);
      expect(DmReplyQuota.countCodePoints('a😀b'), 3);
    });

    test('0/300 boundaries via remaining', () {
      const q0 = DmReplyQuota(used: 0, limit: 300, freeUid: 'u');
      expect(q0.remaining, 300);
      expect(q0.draftExceeds('x'), false);

      const q299 = DmReplyQuota(used: 299, limit: 300, freeUid: 'u');
      expect(q299.remaining, 1);
      expect(q299.draftExceeds('ab'), true);
      expect(q299.draftExceeds('a'), false);

      const q300 = DmReplyQuota(used: 300, limit: 300, freeUid: 'u');
      expect(q300.exhausted, true);
      expect(q300.draftExceeds(''), false);
      expect(q300.draftExceeds('a'), true);
    });
  });

  group('DmSendPath', () {
    test('callable only for free international', () {
      expect(
        DmSendPath.requiresCallable(
          senderIsPremium: false,
          isInternational: true,
        ),
        isTrue,
      );
      expect(
        DmSendPath.requiresCallable(
          senderIsPremium: true,
          isInternational: true,
        ),
        isFalse,
      );
      expect(
        DmSendPath.requiresCallable(
          senderIsPremium: false,
          isInternational: false,
        ),
        isFalse,
      );
    });
  });
}
