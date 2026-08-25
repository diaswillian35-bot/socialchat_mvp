import 'package:flutter/widgets.dart';

/// Guards server-side read watermarks (`lastReadAt`, `unread`) for DM chats.
///
/// Receiving/syncing a message must never mark the peer's messages as read.
/// Writes are allowed only when the chat is foreground, unlocked, and the
/// active route.
class ChatReadGuard {
  ChatReadGuard._();

  static bool mayPersistRead({
    required bool mounted,
    required AppLifecycleState? lifecycle,
    required bool routeIsCurrent,
  }) {
    if (!mounted) return false;
    if (lifecycle != AppLifecycleState.resumed) return false;
    if (!routeIsCurrent) return false;
    return true;
  }

  /// Leaving the chat via back navigation while the app stays foreground.
  static bool mayPersistReadOnExit({
    required bool mounted,
    required AppLifecycleState? lifecycle,
  }) {
    if (!mounted) return false;
    return lifecycle == AppLifecycleState.resumed;
  }

  /// Clearing `unread.{uid}` is stricter than a read watermark: only when the
  /// user is actively viewing the latest messages in an open chat.
  static bool mayClearUnread({
    required bool mounted,
    required AppLifecycleState? lifecycle,
    required bool routeIsCurrent,
    required bool viewingLatestMessages,
  }) {
    if (!mayPersistRead(
      mounted: mounted,
      lifecycle: lifecycle,
      routeIsCurrent: routeIsCurrent,
    )) {
      return false;
    }
    return viewingLatestMessages;
  }
}
