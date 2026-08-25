import 'package:flutter_test/flutter_test.dart';

import 'package:socialchat_mvp/services/dm_reply_quota.dart';

void main() {
  group('DmReplyQuota.effectiveForConversation', () {
    const freeUid = 'free_user_1';

    test('new intl conversation without replyQuota → 300 available', () {
      final q = DmReplyQuota.effectiveForConversation(
        usesReplyQuota: true,
        replyQuotaRaw: null,
        myUid: freeUid,
      );
      expect(q.enabled, isTrue);
      expect(q.used, 0);
      expect(q.limit, 300);
      expect(q.remaining, 300);
      expect(q.exhausted, isFalse);
      expect(q.freeUid, freeUid);
    });

    test('short draft allowed when quota absent on server', () {
      final q = DmReplyQuota.effectiveForConversation(
        usesReplyQuota: true,
        replyQuotaRaw: null,
        myUid: freeUid,
      );
      expect(q.draftExceeds('Oi'), isFalse);
      expect(q.draftExceeds('a' * 300), isFalse);
      expect(q.draftExceeds('a' * 301), isTrue);
    });

    test('callable snapshot overrides absent Firestore quota', () {
      final fromServer = DmReplyQuota(
        used: 12,
        limit: 300,
        freeUid: freeUid,
      );
      final q = DmReplyQuota.effectiveForConversation(
        usesReplyQuota: true,
        replyQuotaRaw: null,
        myUid: freeUid,
        fromCallable: fromServer,
      );
      expect(q.used, 12);
      expect(q.remaining, 288);
    });

    test('reopen with persisted replyQuota keeps server used', () {
      final q = DmReplyQuota.effectiveForConversation(
        usesReplyQuota: true,
        replyQuotaRaw: {
          'enabled': true,
          'freeUid': freeUid,
          'initiatorUid': 'master_1',
          'limit': 300,
          'used': 42,
          'version': 1,
        },
        myUid: freeUid,
      );
      expect(q.used, 42);
      expect(q.remaining, 258);
      expect(q.exhausted, isFalse);
    });

    test('modal only when used >= limit', () {
      final fresh = DmReplyQuota.effectiveForConversation(
        usesReplyQuota: true,
        replyQuotaRaw: null,
        myUid: freeUid,
      );
      expect(
        DmReplyQuota.shouldShowQuotaExhaustedModal(
          usesReplyQuota: true,
          quota: fresh,
        ),
        isFalse,
      );

      const exhausted = DmReplyQuota(
        used: 300,
        limit: 300,
        freeUid: freeUid,
      );
      expect(
        DmReplyQuota.shouldShowQuotaExhaustedModal(
          usesReplyQuota: true,
          quota: exhausted,
        ),
        isTrue,
      );
    });

    test('same-country path does not enable quota UI', () {
      final q = DmReplyQuota.effectiveForConversation(
        usesReplyQuota: false,
        replyQuotaRaw: null,
        myUid: freeUid,
      );
      expect(q.enabled, isFalse);
      expect(
        DmReplyQuota.shouldShowQuotaExhaustedModal(
          usesReplyQuota: false,
          quota: q,
        ),
        isFalse,
      );
    });
  });
}
