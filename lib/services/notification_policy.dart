import 'package:flutter/widgets.dart';

/// Pure policy for contextual DM/group notifications (client-side).
///
/// No Firebase writes, no heartbeat. Android-safe: foreground never shows
/// local/system visual; background relies on FCM `notification` payload.
class NotificationPolicy {
  NotificationPolicy._();

  /// DM / group message types handled by this policy.
  static const chatTypes = {'chat', 'private', 'group', 'group_join_approved'};

  static bool isChatMessage(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString().trim().toLowerCase();
    if (chatTypes.contains(type)) return true;
    if (type.startsWith('group') &&
        type != 'group_join_request' &&
        type != 'group_join_rejected') {
      return true;
    }
    return (data['conversationId'] ?? '').toString().trim().isNotEmpty ||
        (data['groupId'] ?? '').toString().trim().isNotEmpty;
  }

  /// iOS foreground presentation: never alert/sound/badge from FCM while app
  /// is visible — in-app unread/bolinha comes from Firestore streams.
  static bool shouldEnableIosForegroundPresentation({
    required AppLifecycleState lifecycle,
  }) {
    return lifecycle != AppLifecycleState.resumed &&
        lifecycle != AppLifecycleState.inactive;
  }

  /// System banner/sound from Flutter local notifications (onMessage path).
  static bool shouldShowLocalNotification({
    required AppLifecycleState lifecycle,
    required bool isForActiveSurface,
    required Map<String, dynamic> data,
  }) {
    if (!isChatMessage(data)) return false;
    if (_isForeground(lifecycle)) return false;
    if (isForActiveSurface) return false;
    return false;
  }

  /// Suppresses iOS system presentation + local banner in foreground.
  static bool shouldSuppressSystemVisual({
    required AppLifecycleState lifecycle,
    required bool isForActiveSurface,
    required Map<String, dynamic> data,
  }) {
    if (!isChatMessage(data)) return false;
    if (_isForeground(lifecycle)) return true;
    if (isForActiveSurface) return true;
    return false;
  }

  /// Active chat/group: server may increment unread but client clears; policy
  /// says do not treat as "new unread" for badge/bolinha intent.
  static bool shouldSkipUnreadIncrement({required bool isForActiveSurface}) {
    return isForActiveSurface;
  }

  /// Foreground on Home/other screen: allow Firestore unread (bolinha) but not
  /// system badge bump from push — handled by suppressing iOS presentation.
  static bool shouldIncrementInAppUnread({
    required AppLifecycleState lifecycle,
    required bool isForActiveSurface,
  }) {
    if (isForActiveSurface) return false;
    return true;
  }

  /// Background/killed/locked: full push (title/body/sound/badge) via FCM.
  static bool shouldSendFullRemotePush({
    required AppLifecycleState lifecycle,
  }) {
    return !_isForeground(lifecycle);
  }

  static bool _isForeground(AppLifecycleState lifecycle) {
    return lifecycle == AppLifecycleState.resumed ||
        lifecycle == AppLifecycleState.inactive;
  }
}
