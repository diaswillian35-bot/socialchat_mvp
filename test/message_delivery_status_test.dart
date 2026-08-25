import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/message_delivery_status.dart';

void main() {
  group('MessageDeliveryStatus per-message monotonic DM', () {
    final t0 = DateTime.utc(2026, 8, 21, 12, 0);
    final t1 = DateTime.utc(2026, 8, 21, 12, 1);
    final t2 = DateTime.utc(2026, 8, 21, 12, 2);
    final t3 = DateTime.utc(2026, 8, 21, 12, 3);

    test('scenario: A Lido, B Enviado, C Enviando → confirm → peer reads', () {
      final latch = <String, DeliveryStage>{};

      DeliveryStage stageFor({
        required String id,
        required bool pending,
        required DateTime? at,
        required DateTime? peerRead,
      }) {
        final raw = MessageDeliveryStatus.dmStage(
          isMe: true,
          deleted: false,
          isLocalPending: pending,
          messageCreatedAt: at,
          peerLastReadAt: peerRead,
        );
        final latched = MessageDeliveryStatus.latchStage(latch[id], raw);
        latch[id] = latched;
        return latched;
      }

      expect(
        stageFor(id: 'A', pending: false, at: t0, peerRead: t0),
        DeliveryStage.read,
      );
      expect(
        stageFor(id: 'B', pending: false, at: t1, peerRead: t0),
        DeliveryStage.sent,
      );
      expect(
        stageFor(id: 'C', pending: true, at: null, peerRead: t0),
        DeliveryStage.sending,
      );

      expect(
        stageFor(id: 'C', pending: false, at: t2, peerRead: t0),
        DeliveryStage.sent,
      );
      expect(latch['A'], DeliveryStage.read);
      expect(latch['B'], DeliveryStage.sent);

      expect(
        stageFor(id: 'A', pending: false, at: t0, peerRead: t1),
        DeliveryStage.read,
      );
      expect(
        stageFor(id: 'B', pending: false, at: t1, peerRead: t1),
        DeliveryStage.read,
      );
      expect(
        stageFor(id: 'C', pending: false, at: t2, peerRead: t1),
        DeliveryStage.sent,
      );

      expect(
        stageFor(id: 'C', pending: false, at: t2, peerRead: t2),
        DeliveryStage.read,
      );

      expect(
        stageFor(id: 'A', pending: false, at: t0, peerRead: t2),
        DeliveryStage.read,
      );
      expect(
        stageFor(id: 'B', pending: false, at: t1, peerRead: t2),
        DeliveryStage.read,
      );
      expect(
        stageFor(id: 'C', pending: false, at: t2, peerRead: t2),
        DeliveryStage.read,
      );

      expect(
        stageFor(id: 'D', pending: true, at: null, peerRead: t2),
        DeliveryStage.sending,
      );
      expect(
        stageFor(id: 'D', pending: false, at: t3, peerRead: t2),
        DeliveryStage.sent,
      );
      expect(latch['A'], DeliveryStage.read);
      expect(latch['B'], DeliveryStage.read);
      expect(latch['C'], DeliveryStage.read);

      expect(
        stageFor(id: 'A', pending: false, at: t0, peerRead: null),
        DeliveryStage.read,
      );
      expect(
        stageFor(id: 'B', pending: false, at: t1, peerRead: null),
        DeliveryStage.read,
      );

      expect(
        MessageDeliveryStatus.latchStage(
          DeliveryStage.read,
          DeliveryStage.sent,
        ),
        DeliveryStage.read,
      );
    });

    test('received messages get no label', () {
      expect(
        MessageDeliveryStatus.labelFor(
          isMe: false,
          deleted: false,
          stage: DeliveryStage.read,
          sendingLabel: 'Enviando',
          sentLabel: 'Enviado',
          readLabel: 'Lido',
        ),
        isNull,
      );
    });
  });

  group('DM peer new vs legacy old', () {
    final t0 = DateTime.utc(2026, 8, 22, 12, 0);
    final t1 = DateTime.utc(2026, 8, 22, 12, 1);
    final t2 = DateTime.utc(2026, 8, 22, 12, 2);

    test('new peer: presence lastReadAt drives Lido', () {
      final effective = MessageDeliveryStatus.effectivePeerReadAt(
        presenceLastReadAt: t1,
        legacyCaughtUpAt: null,
      );
      expect(
        MessageDeliveryStatus.dmStage(
          isMe: true,
          deleted: false,
          isLocalPending: false,
          messageCreatedAt: t0,
          peerLastReadAt: effective,
        ),
        DeliveryStage.read,
      );
      expect(
        MessageDeliveryStatus.dmStage(
          isMe: true,
          deleted: false,
          isLocalPending: false,
          messageCreatedAt: t2,
          peerLastReadAt: effective,
        ),
        DeliveryStage.sent,
      );
    });

    test('old peer: unread==0 advances legacy to lastMessageAt', () {
      DateTime? legacy;
      legacy = MessageDeliveryStatus.latchLegacyCaughtUpAt(
        previous: legacy,
        peerUnread: 1,
        lastMessageAt: t1,
      );
      expect(legacy, isNull);
      expect(
        MessageDeliveryStatus.dmStage(
          isMe: true,
          deleted: false,
          isLocalPending: false,
          messageCreatedAt: t0,
          peerLastReadAt: MessageDeliveryStatus.effectivePeerReadAt(
            presenceLastReadAt: null,
            legacyCaughtUpAt: legacy,
          ),
        ),
        DeliveryStage.sent,
      );

      legacy = MessageDeliveryStatus.latchLegacyCaughtUpAt(
        previous: legacy,
        peerUnread: 0,
        lastMessageAt: t1,
      );
      expect(legacy, t1);
      final effective = MessageDeliveryStatus.effectivePeerReadAt(
        presenceLastReadAt: null,
        legacyCaughtUpAt: legacy,
      );
      expect(
        MessageDeliveryStatus.dmStage(
          isMe: true,
          deleted: false,
          isLocalPending: false,
          messageCreatedAt: t0,
          peerLastReadAt: effective,
        ),
        DeliveryStage.read,
      );
      expect(
        MessageDeliveryStatus.dmStage(
          isMe: true,
          deleted: false,
          isLocalPending: false,
          messageCreatedAt: t1,
          peerLastReadAt: effective,
        ),
        DeliveryStage.read,
      );

      final afterSend = MessageDeliveryStatus.latchLegacyCaughtUpAt(
        previous: legacy,
        peerUnread: 1,
        lastMessageAt: t2,
      );
      expect(afterSend, t1);
      expect(
        MessageDeliveryStatus.dmStage(
          isMe: true,
          deleted: false,
          isLocalPending: false,
          messageCreatedAt: t2,
          peerLastReadAt: MessageDeliveryStatus.effectivePeerReadAt(
            presenceLastReadAt: null,
            legacyCaughtUpAt: afterSend,
          ),
        ),
        DeliveryStage.sent,
      );
      expect(
        MessageDeliveryStatus.dmStage(
          isMe: true,
          deleted: false,
          isLocalPending: false,
          messageCreatedAt: t0,
          peerLastReadAt: MessageDeliveryStatus.effectivePeerReadAt(
            presenceLastReadAt: null,
            legacyCaughtUpAt: afterSend,
          ),
        ),
        DeliveryStage.read,
      );
    });

    test('presence watermark wins when newer than legacy', () {
      final effective = MessageDeliveryStatus.effectivePeerReadAt(
        presenceLastReadAt: t2,
        legacyCaughtUpAt: t0,
      );
      expect(effective, t2);
    });
  });

  group('MessageDeliveryStatus group per-message', () {
    final t0 = DateTime.utc(2026, 8, 21, 12);
    final t1 = DateTime.utc(2026, 8, 21, 12, 5);

    test('new send does not lower prior read-by latch', () {
      final stageLatch = <String, DeliveryStage>{};
      final countLatch = <String, int>{};

      int apply(String id, DateTime at, Map<String, DateTime> reads) {
        final raw = MessageDeliveryStatus.groupReadByCount(
          messageCreatedAt: at,
          otherMemberIds: ['u1', 'u2'],
          readAtByUid: reads,
        );
        final count = MessageDeliveryStatus.latchReadByCount(
          countLatch[id],
          raw,
        );
        countLatch[id] = count;
        final stage = MessageDeliveryStatus.latchStage(
          stageLatch[id],
          MessageDeliveryStatus.groupStage(
            isMe: true,
            deleted: false,
            isLocalPending: false,
            readByCount: count,
          ),
        );
        stageLatch[id] = stage;
        return count;
      }

      expect(apply('A', t0, {'u1': t0, 'u2': t0}), 2);
      expect(stageLatch['A'], DeliveryStage.read);
      expect(apply('A', t0, {}), 2);
      expect(stageLatch['A'], DeliveryStage.read);
      expect(apply('B', t1, {'u1': t0, 'u2': t0}), 0);
      expect(stageLatch['B'], DeliveryStage.sent);
      expect(stageLatch['A'], DeliveryStage.read);
    });
  });

  group('wiring', () {
    test('chat uses peer lastReadAt not global peerUnread for status', () {
      final src = File('lib/pages/chat_page.dart').readAsStringSync();
      expect(src.contains('_peerLastReadAt'), isTrue);
      expect(src.contains('_legacyPeerCaughtUpAt'), isTrue);
      expect(src.contains('_effectivePeerReadAt'), isTrue);
      expect(src.contains('dmStage'), isTrue);
      expect(src.contains('latchStage'), isTrue);
      expect(src.contains('peerUnread: _peerUnread'), isFalse);
    });
  });
}
