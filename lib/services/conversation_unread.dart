/// Resolves the list-row unread badge for a conversation/group document.
///
/// Prefer `unread.{uid}` when the key exists (including explicit `0`). Only fall
/// back to legacy `unreadCount.{uid}` when the modern key is absent — otherwise
/// a successful clear of `unread` can leave a stale badge from `unreadCount`.
class ConversationUnread {
  ConversationUnread._();

  static int resolveMyUnread(Map<String, dynamic> data, String myUid) {
    final uid = myUid.trim();
    if (uid.isEmpty) return 0;
    final unreadRaw = data['unread'];
    if (unreadRaw is Map && unreadRaw.containsKey(uid)) {
      return _asInt(unreadRaw[uid]);
    }
    // set(merge) with a dotted key stores a top-level field named
    // "unread.<uid>" (or "unread. <uid>" when a space was interpolated).
    // An explicit nested 0 still wins; the literal field is only a fallback.
    final literal = _literalUnread(data, uid);
    if (literal != null) return literal;
    final countRaw = data['unreadCount'];
    if (countRaw is Map && countRaw.containsKey(uid)) {
      return _asInt(countRaw[uid]);
    }
    return 0;
  }

  /// Red tab badge: number of group docs with unread for [uid]. Hidden groups
  /// stay in this count; the list hides them separately.
  static int groupTabBadgeCount(
    Iterable<Map<String, dynamic>> groups,
    String uid,
  ) {
    var total = 0;
    for (final data in groups) {
      if (data['deleted'] == true) continue;
      if (resolveMyUnread(data, uid) > 0) total++;
    }
    return total;
  }

  static int? _literalUnread(Map<String, dynamic> data, String uid) {
    for (final key in <String>['unread.$uid', 'unread. $uid']) {
      if (!data.containsKey(key) || data[key] == null) continue;
      return _asInt(data[key]);
    }
    return null;
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

/// Reversed chat lists keep the latest messages at offset 0.
/// A clear that waits for a scroll event never runs when the user opens the
/// thread already at the bottom and then leaves.
class VisibleUnreadClear {
  VisibleUnreadClear._();

  static const double latestOffset = 48;

  static bool listAtLatest({
    required bool hasClients,
    required double offset,
  }) {
    if (!hasClients) return false;
    return offset <= latestOffset;
  }

  /// Layout has not attached the list yet. Retry on the next frame.
  static bool retryWhenLaidOut({
    required bool pending,
    required bool hasClients,
  }) {
    return pending && !hasClients;
  }

  /// Leaving an open thread that was showing the latest messages must persist
  /// the clear. Scrolling up into history must not.
  static bool flushOnExit({
    required bool pendingOrUnread,
    required bool hasClients,
    required double offset,
  }) {
    if (!pendingOrUnread) return false;
    if (!hasClients) return true;
    return listAtLatest(hasClients: true, offset: offset);
  }
}
