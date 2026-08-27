import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/app_notification_state.dart';
import 'package:socialchat_mvp/services/conversation_read_write.dart';
import 'package:socialchat_mvp/services/notification_policy.dart';

void main() {
  group('iOS foreground transitions Home → chat → Home → background', () {
    late AppNotificationState state;

    setUp(() {
      state = AppNotificationState.instance;
      state.debugReset();
      state.debugSetLifecycle(AppLifecycleState.resumed);
    });

    test('foreground suppresses system presentation on Home and in chat', () {
      expect(
        NotificationPolicy.shouldEnableIosForegroundPresentation(
          lifecycle: AppLifecycleState.resumed,
        ),
        isFalse,
      );

      state.enterPrivateChat('c1');
      expect(state.shouldSuppressVisualNotification({
        'type': 'chat',
        'conversationId': 'c1',
      }), isTrue);

      state.leavePrivateChat('c1');
      expect(state.activeConversationId, isNull);
      expect(
        NotificationPolicy.shouldEnableIosForegroundPresentation(
          lifecycle: AppLifecycleState.resumed,
        ),
        isFalse,
      );
    });

    test('background restores full remote presentation', () {
      state.enterPrivateChat('c1');
      state.debugSetLifecycle(AppLifecycleState.paused);
      expect(
        NotificationPolicy.shouldSendFullRemotePush(
          lifecycle: AppLifecycleState.paused,
        ),
        isTrue,
      );
      expect(
        NotificationPolicy.shouldEnableIosForegroundPresentation(
          lifecycle: AppLifecycleState.paused,
        ),
        isTrue,
      );
    });

    test('active surface callback fires on enter/leave (no stuck silent)', () {
      var calls = 0;
      state.onActiveSurfaceChanged = () => calls++;
      state.enterPrivateChat('c1');
      state.leavePrivateChat('c1');
      expect(calls, 2);
    });
  });

  group('Unread document before/after canonical clear', () {
    test('DM: server increment then view clear zeros only viewer unread', () {
      const viewer = 'alice';
      const peer = 'bob';
      final before = {
        'unread': {viewer: 0, peer: 0},
      };

      final afterSend = Map<String, dynamic>.from(before);
      final unread = Map<String, dynamic>.from(afterSend['unread'] as Map);
      unread[viewer] = 1;
      afterSend['unread'] = unread;

      expect(
        UnreadViewClearScenario.badgeAfterPeerSend(
          conversation: afterSend,
          viewerUid: viewer,
        ),
        1,
      );

      final afterClear = UnreadViewClearScenario.conversationAfterViewClear(
        before: afterSend,
        viewerUid: viewer,
      );
      expect(afterClear['unread'][viewer], 0);
      expect(
        UnreadViewClearScenario.peerStillHasUnread(
          conversation: afterClear,
          peerUid: peer,
        ),
        isFalse,
      );
    });

    test('group unread map shape matches DM clear', () {
      final before = {
        'unread': {'u1': 2, 'u2': 0},
      };
      final after = UnreadViewClearScenario.conversationAfterViewClear(
        before: before,
        viewerUid: 'u1',
      );
      expect(after['unread']['u1'], 0);
      expect(after['unread']['u2'], 0);
    });
  });
}
