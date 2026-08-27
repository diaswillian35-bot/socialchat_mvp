import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/notification_policy.dart';

void main() {
  const dmData = {'type': 'chat', 'conversationId': 'c1'};
  const otherDm = {'type': 'chat', 'conversationId': 'c2'};
  const groupData = {'type': 'group', 'groupId': 'g1'};
  const otherGroup = {'type': 'group', 'groupId': 'g2'};

  group('NotificationPolicy foreground', () {
    test('same DM: no local banner, suppress system, skip unread intent', () {
      expect(
        NotificationPolicy.shouldShowLocalNotification(
          lifecycle: AppLifecycleState.resumed,
          isForActiveSurface: true,
          data: dmData,
        ),
        isFalse,
      );
      expect(
        NotificationPolicy.shouldSuppressSystemVisual(
          lifecycle: AppLifecycleState.resumed,
          isForActiveSurface: true,
          data: dmData,
        ),
        isTrue,
      );
      expect(
        NotificationPolicy.shouldSkipUnreadIncrement(isForActiveSurface: true),
        isTrue,
      );
    });

    test('Home/other screen: suppress system, allow in-app unread', () {
      expect(
        NotificationPolicy.shouldSuppressSystemVisual(
          lifecycle: AppLifecycleState.resumed,
          isForActiveSurface: false,
          data: otherDm,
        ),
        isTrue,
      );
      expect(
        NotificationPolicy.shouldIncrementInAppUnread(
          lifecycle: AppLifecycleState.resumed,
          isForActiveSurface: false,
        ),
        isTrue,
      );
      expect(
        NotificationPolicy.shouldSkipUnreadIncrement(isForActiveSurface: false),
        isFalse,
      );
    });

    test('other conversation open: no banner, increment unread for other only',
        () {
      expect(
        NotificationPolicy.shouldSuppressSystemVisual(
          lifecycle: AppLifecycleState.resumed,
          isForActiveSurface: false,
          data: otherDm,
        ),
        isTrue,
      );
    });

    test('group same rules as DM', () {
      expect(
        NotificationPolicy.shouldSuppressSystemVisual(
          lifecycle: AppLifecycleState.resumed,
          isForActiveSurface: true,
          data: groupData,
        ),
        isTrue,
      );
      expect(
        NotificationPolicy.shouldIncrementInAppUnread(
          lifecycle: AppLifecycleState.resumed,
          isForActiveSurface: false,
        ),
        isTrue,
      );
    });
  });

  group('NotificationPolicy background', () {
    test('background/killed: full remote push path', () {
      for (final lifecycle in [
        AppLifecycleState.paused,
        AppLifecycleState.detached,
        AppLifecycleState.hidden,
      ]) {
        expect(
          NotificationPolicy.shouldSendFullRemotePush(lifecycle: lifecycle),
          isTrue,
        );
        expect(
          NotificationPolicy.shouldEnableIosForegroundPresentation(
            lifecycle: lifecycle,
          ),
          isTrue,
        );
        expect(
          NotificationPolicy.shouldShowLocalNotification(
            lifecycle: lifecycle,
            isForActiveSurface: false,
            data: dmData,
          ),
          isFalse,
          reason: 'OS shows FCM notification — no duplicate local',
        );
      }
    });
  });

  group('Android safety', () {
    test('foreground never creates local notification for chat', () {
      expect(
        NotificationPolicy.shouldShowLocalNotification(
          lifecycle: AppLifecycleState.resumed,
          isForActiveSurface: false,
          data: groupData,
        ),
        isFalse,
      );
    });
  });
}
