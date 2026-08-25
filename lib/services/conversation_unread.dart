/// Resolves the list-row unread badge for a conversation/group document.
///
/// Prefer `unread.{uid}` when the key exists (including explicit `0`). Only fall
/// back to legacy `unreadCount.{uid}` when the modern key is absent — otherwise
/// a successful clear of `unread` can leave a stale badge from `unreadCount`.
class ConversationUnread {
  ConversationUnread._();

  static int resolveMyUnread(Map<String, dynamic> data, String myUid) {
    final unreadRaw = data['unread'];
    if (unreadRaw is Map && unreadRaw.containsKey(myUid)) {
      return _asInt(unreadRaw[myUid]);
    }
    final countRaw = data['unreadCount'];
    if (countRaw is Map && countRaw.containsKey(myUid)) {
      return _asInt(countRaw[myUid]);
    }
    return 0;
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }
}

/// Pure helpers for the DM "clear unread once per real view" coordinator.
///
/// Avoids dropping a legitimate clear when an earlier watermark-only write is
/// still in flight, when `_myUnread` has not been hydrated yet, or when the
/// user is not yet viewing the latest messages.
class ChatUnreadClearCoordinator {
  ChatUnreadClearCoordinator._();

  /// Queue another clear attempt after conditions allow a real write.
  static bool shouldQueuePendingClear({
    required bool clearUnreadRequested,
    required bool routeAllowsRead,
    required bool mayClear,
    required bool markReadInFlight,
    required int myUnread,
    required bool wroteUnreadZero,
  }) {
    if (!clearUnreadRequested || !routeAllowsRead || wroteUnreadZero) {
      return false;
    }
    // In-flight, not viewing latest yet, or unread not hydrated.
    return markReadInFlight || !mayClear || myUnread <= 0;
  }

  static bool shouldWriteUnreadZero({
    required bool mayClear,
    required int myUnread,
  }) {
    return mayClear && myUnread > 0;
  }

  /// Retry after in-flight only when unread remains and a view is possible.
  static bool shouldRetryPendingClear({
    required bool pendingClearUnread,
    required int myUnread,
    required bool viewingLatestMessages,
  }) {
    return pendingClearUnread && myUnread > 0 && viewingLatestMessages;
  }
}
