import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/chat_read_guard.dart';
import 'package:socialchat_mvp/services/conversation_unread.dart';
import 'package:socialchat_mvp/services/message_delivery_status.dart';

void main() {
  group('ChatReadGuard', () {
    test('allows read watermark only when resumed and route is current', () {
      expect(
        ChatReadGuard.mayPersistRead(
          mounted: true,
          lifecycle: AppLifecycleState.resumed,
          routeIsCurrent: true,
        ),
        isTrue,
      );
      expect(
        ChatReadGuard.mayPersistRead(
          mounted: true,
          lifecycle: AppLifecycleState.paused,
          routeIsCurrent: true,
        ),
        isFalse,
      );
      expect(
        ChatReadGuard.mayPersistRead(
          mounted: true,
          lifecycle: AppLifecycleState.inactive,
          routeIsCurrent: true,
        ),
        isFalse,
      );
      expect(
        ChatReadGuard.mayPersistRead(
          mounted: true,
          lifecycle: AppLifecycleState.resumed,
          routeIsCurrent: false,
        ),
        isFalse,
      );
      expect(
        ChatReadGuard.mayPersistRead(
          mounted: false,
          lifecycle: AppLifecycleState.resumed,
          routeIsCurrent: true,
        ),
        isFalse,
      );
    });

    test('allows exit watermark only when resumed', () {
      expect(
        ChatReadGuard.mayPersistReadOnExit(
          mounted: true,
          lifecycle: AppLifecycleState.resumed,
        ),
        isTrue,
      );
      expect(
        ChatReadGuard.mayPersistReadOnExit(
          mounted: true,
          lifecycle: AppLifecycleState.paused,
        ),
        isFalse,
      );
    });

    test('clears unread only when viewing latest messages on current route', () {
      expect(
        ChatReadGuard.mayClearUnread(
          mounted: true,
          lifecycle: AppLifecycleState.resumed,
          routeIsCurrent: true,
          viewingLatestMessages: true,
        ),
        isTrue,
      );
      expect(
        ChatReadGuard.mayClearUnread(
          mounted: true,
          lifecycle: AppLifecycleState.resumed,
          routeIsCurrent: true,
          viewingLatestMessages: false,
        ),
        isFalse,
      );
      expect(
        ChatReadGuard.mayClearUnread(
          mounted: true,
          lifecycle: AppLifecycleState.resumed,
          routeIsCurrent: false,
          viewingLatestMessages: true,
        ),
        isFalse,
      );
      // 6. resume/background without open chat → no clear
      expect(
        ChatReadGuard.mayClearUnread(
          mounted: true,
          lifecycle: AppLifecycleState.paused,
          routeIsCurrent: true,
          viewingLatestMessages: true,
        ),
        isFalse,
      );
    });
  });

  group('ConversationUnread list badge', () {
    // 1. new message → blue dot (unread > 0)
    test('new message shows unread from unread map', () {
      expect(
        ConversationUnread.resolveMyUnread({
          'unread': {'me': 2},
        }, 'me'),
        2,
      );
    });

    // 2. open list only → stays (resolver does not mutate)
    test('list-only read does not zero unread', () {
      final data = {
        'unread': {'me': 3},
        'unreadCount': {'me': 3},
      };
      expect(ConversationUnread.resolveMyUnread(data, 'me'), 3);
      expect(data['unread'], {'me': 3});
    });

    // 3–4. open conversation clears unread key → badge gone even if legacy stale
    test('explicit unread 0 wins over stale unreadCount', () {
      expect(
        ConversationUnread.resolveMyUnread({
          'unread': {'me': 0},
          'unreadCount': {'me': 5},
        }, 'me'),
        0,
      );
    });

    // 5. new message again
    test('new message after clear shows badge again', () {
      expect(
        ConversationUnread.resolveMyUnread({
          'unread': {'me': 1},
          'unreadCount': {'me': 0},
        }, 'me'),
        1,
      );
    });

    test('falls back to unreadCount only when unread key missing', () {
      expect(
        ConversationUnread.resolveMyUnread({
          'unreadCount': {'me': 4},
        }, 'me'),
        4,
      );
      expect(
        ConversationUnread.resolveMyUnread({
          'unread': {'other': 2},
          'unreadCount': {'me': 4},
        }, 'me'),
        4,
      );
    });

    // 7. DM and group share same map shape
    test('group unread map resolves like DM', () {
      expect(
        ConversationUnread.resolveMyUnread({
          'unread': {'u1': 0, 'u2': 7},
        }, 'u2'),
        7,
      );
    });
  });

  group('ChatUnreadClearCoordinator', () {
    // Race: watermark-only in flight must queue legitimate clear
    test('queues pending clear while mark-read is in flight', () {
      expect(
        ChatUnreadClearCoordinator.shouldQueuePendingClear(
          clearUnreadRequested: true,
          routeAllowsRead: true,
          mayClear: true,
          markReadInFlight: true,
          myUnread: 2,
          wroteUnreadZero: false,
        ),
        isTrue,
      );
    });

    test('queues pending clear when unread not hydrated yet', () {
      expect(
        ChatUnreadClearCoordinator.shouldQueuePendingClear(
          clearUnreadRequested: true,
          routeAllowsRead: true,
          mayClear: true,
          markReadInFlight: false,
          myUnread: 0,
          wroteUnreadZero: false,
        ),
        isTrue,
      );
    });

    test('queues pending when not viewing latest yet', () {
      expect(
        ChatUnreadClearCoordinator.shouldQueuePendingClear(
          clearUnreadRequested: true,
          routeAllowsRead: true,
          mayClear: false,
          markReadInFlight: false,
          myUnread: 2,
          wroteUnreadZero: false,
        ),
        isTrue,
      );
    });

    test('writes unread zero once when mayClear and unread > 0', () {
      expect(
        ChatUnreadClearCoordinator.shouldWriteUnreadZero(
          mayClear: true,
          myUnread: 3,
        ),
        isTrue,
      );
      expect(
        ChatUnreadClearCoordinator.shouldWriteUnreadZero(
          mayClear: true,
          myUnread: 0,
        ),
        isFalse,
      );
      expect(
        ChatUnreadClearCoordinator.shouldWriteUnreadZero(
          mayClear: false,
          myUnread: 3,
        ),
        isFalse,
      );
    });

    test('retries pending only while viewing latest with unread', () {
      expect(
        ChatUnreadClearCoordinator.shouldRetryPendingClear(
          pendingClearUnread: true,
          myUnread: 2,
          viewingLatestMessages: true,
        ),
        isTrue,
      );
      expect(
        ChatUnreadClearCoordinator.shouldRetryPendingClear(
          pendingClearUnread: true,
          myUnread: 2,
          viewingLatestMessages: false,
        ),
        isFalse,
      );
      expect(
        ChatUnreadClearCoordinator.shouldRetryPendingClear(
          pendingClearUnread: false,
          myUnread: 2,
          viewingLatestMessages: true,
        ),
        isFalse,
      );
    });

    test('list-only and push paths never request clear', () {
      expect(
        ChatUnreadClearCoordinator.shouldQueuePendingClear(
          clearUnreadRequested: false,
          routeAllowsRead: true,
          mayClear: false,
          markReadInFlight: false,
          myUnread: 5,
          wroteUnreadZero: false,
        ),
        isFalse,
      );
    });
  });

  // 8. no regression of Enviado/Lido and Lido por N
  group('delivery status not coupled to list unread clear', () {
    test('DM Enviado/Lido still driven by peer lastReadAt watermark', () {
      final sent = MessageDeliveryStatus.dmStage(
        isMe: true,
        deleted: false,
        isLocalPending: false,
        messageCreatedAt: DateTime(2026, 1, 1, 12, 0),
        peerLastReadAt: null,
      );
      expect(sent, DeliveryStage.sent);

      final read = MessageDeliveryStatus.dmStage(
        isMe: true,
        deleted: false,
        isLocalPending: false,
        messageCreatedAt: DateTime(2026, 1, 1, 12, 0),
        peerLastReadAt: DateTime(2026, 1, 1, 12, 1),
      );
      expect(read, DeliveryStage.read);
    });

    test('group Lido por N still driven by reads map', () {
      final count = MessageDeliveryStatus.groupReadByCount(
        messageCreatedAt: DateTime(2026, 1, 1, 12, 0),
        otherMemberIds: const ['a', 'b'],
        readAtByUid: {
          'me': DateTime(2026, 1, 1, 12, 2),
          'a': DateTime(2026, 1, 1, 12, 1),
          'b': DateTime(2026, 1, 1, 11, 0),
        },
      );
      expect(count, 1);

      final stage = MessageDeliveryStatus.groupStage(
        isMe: true,
        deleted: false,
        isLocalPending: false,
        readByCount: count,
      );
      expect(stage, DeliveryStage.read);
      expect(
        MessageDeliveryStatus.labelFor(
          isMe: true,
          deleted: false,
          stage: stage,
          sendingLabel: 'Enviando',
          sentLabel: 'Enviado',
          readLabel: 'Lido',
          readByLabel: (n) => 'Lido por $n',
          readByCount: count,
        ),
        'Lido por 1',
      );
    });
  });
}
