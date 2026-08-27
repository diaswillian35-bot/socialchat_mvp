/// Bidirectional DM unread accounting (Free/BR ↔ Master/CA) — pure helpers.
///
/// Free international sends use `sendDmMessage` (server unread in same tx).
/// Master/same-country client must NOT replace the unread map; server
/// `onPrivateMessageCreated` owns peer +1.
class DmUnreadDirection {
  DmUnreadDirection._();

  /// After Free→Master via callable: server increment applies once.
  static Map<String, int> afterServerIncrement({
    required Map<String, int> before,
    required String recipientUid,
  }) {
    final next = Map<String, int>.from(before);
    next[recipientUid] = (next[recipientUid] ?? 0) + 1;
    return next;
  }

  /// Master client summary: only clears sender; peer left to server.
  static Map<String, int> afterMasterClientSummary({
    required Map<String, int> before,
    required String senderUid,
    required String recipientUid,
  }) {
    final next = Map<String, int>.from(before);
    next[senderUid] = 0;
    // recipient unchanged until server increment
    next.putIfAbsent(recipientUid, () => before[recipientUid] ?? 0);
    return next;
  }

  /// Full Master→Free path: client clears self, then server +1 on recipient.
  static Map<String, int> afterMasterSendWithServer({
    required Map<String, int> before,
    required String senderUid,
    required String recipientUid,
  }) {
    final afterClient = afterMasterClientSummary(
      before: before,
      senderUid: senderUid,
      recipientUid: recipientUid,
    );
    return afterServerIncrement(
      before: afterClient,
      recipientUid: recipientUid,
    );
  }

  /// Home open / chat not visible: clear must not run → unread preserved.
  static bool recipientUnreadPreservedOnHome({
    required int unreadBefore,
    required int unreadAfter,
  }) {
    return unreadAfter == unreadBefore && unreadBefore > 0;
  }
}
