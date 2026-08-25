/// Per-message delivery stages for own bubbles (DM + group).
///
/// Derived from local pending + server watermark(s). Never regresses when
/// combined with [latchStage] / [latchReadByCount].
enum DeliveryStage {
  /// Local optimistic bubble — not on server yet.
  sending,

  /// Confirmed on server; not covered by peer/member read watermark.
  sent,

  /// Covered by peer (DM) or at least one other member (group label).
  read,
}

class MessageDeliveryStatus {
  MessageDeliveryStatus._();

  /// Prefer presence `lastReadAt` (new clients). Fall back to legacy catch-up
  /// when peer cleared `unread` without writing a watermark (old clients).
  static DateTime? effectivePeerReadAt({
    DateTime? presenceLastReadAt,
    DateTime? legacyCaughtUpAt,
  }) {
    final a = presenceLastReadAt;
    final b = legacyCaughtUpAt;
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  /// When peer `unread == 0`, they caught up through [lastMessageAt].
  /// Watermark only advances (never regresses).
  static DateTime? latchLegacyCaughtUpAt({
    required DateTime? previous,
    required int peerUnread,
    required DateTime? lastMessageAt,
  }) {
    if (peerUnread != 0 || lastMessageAt == null) return previous;
    if (previous == null || lastMessageAt.isAfter(previous)) {
      return lastMessageAt;
    }
    return previous;
  }

  /// DM: compare each message to effective peer read watermark.
  static DeliveryStage dmStage({
    required bool isMe,
    required bool deleted,
    required bool isLocalPending,
    required DateTime? messageCreatedAt,
    required DateTime? peerLastReadAt,
  }) {
    if (!isMe || deleted) {
      // Caller should not show a label; stage unused.
      return DeliveryStage.sent;
    }
    if (isLocalPending) return DeliveryStage.sending;
    if (peerLastReadAt != null &&
        messageCreatedAt != null &&
        !messageCreatedAt.isAfter(peerLastReadAt)) {
      return DeliveryStage.read;
    }
    return DeliveryStage.sent;
  }

  /// Group: count other members with `lastReadAt >= messageCreatedAt`.
  static int groupReadByCount({
    required DateTime? messageCreatedAt,
    required Iterable<String> otherMemberIds,
    required Map<String, DateTime> readAtByUid,
  }) {
    if (messageCreatedAt == null) return 0;
    var n = 0;
    for (final id in otherMemberIds) {
      final at = readAtByUid[id];
      if (at != null && !at.isBefore(messageCreatedAt)) n += 1;
    }
    return n;
  }

  static DeliveryStage groupStage({
    required bool isMe,
    required bool deleted,
    required bool isLocalPending,
    required int readByCount,
  }) {
    if (!isMe || deleted) return DeliveryStage.sent;
    if (isLocalPending) return DeliveryStage.sending;
    if (readByCount > 0) return DeliveryStage.read;
    return DeliveryStage.sent;
  }

  /// Monotonic: sending < sent < read.
  static DeliveryStage latchStage(DeliveryStage? previous, DeliveryStage next) {
    if (previous == null) return next;
    return next.index >= previous.index ? next : previous;
  }

  /// Monotonic read-by count (never decreases for a message id).
  static int latchReadByCount(int? previous, int next) {
    final p = previous ?? 0;
    final n = next < 0 ? 0 : next;
    return n >= p ? n : p;
  }

  static String? labelFor({
    required bool isMe,
    required bool deleted,
    required DeliveryStage stage,
    required String sendingLabel,
    required String sentLabel,
    required String readLabel,
    String Function(int count)? readByLabel,
    int readByCount = 0,
  }) {
    if (!isMe || deleted) return null;
    switch (stage) {
      case DeliveryStage.sending:
        return sendingLabel;
      case DeliveryStage.sent:
        return sentLabel;
      case DeliveryStage.read:
        if (readByLabel != null) {
          final n = readByCount < 1 ? 1 : readByCount;
          return readByLabel(n);
        }
        return readLabel;
    }
  }
}
