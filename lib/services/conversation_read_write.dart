import 'package:cloud_firestore/cloud_firestore.dart';

/// Single view-scoped clear of the current user's DM unread badge.
///
/// Must NOT depend on sending a reply. The send path may also zero `unread.me`
/// as a side-effect of bumping the peer's counter — that is separate.
class ConversationReadWrite {
  ConversationReadWrite._();

  /// Fields written when the user actually views latest messages.
  ///
  /// Keep this list inside `firestore.rules` conversations update
  /// `hasOnly([...])`. Writing a key outside that set fails the whole batch
  /// with permission-denied (silent in UI) — physical symptom on build 16:
  /// "badge only clears after I reply" because `_send`/`summary` zeros
  /// `unread.me` without touching forbidden keys.
  ///
  /// Only `unread.{uid}` is required for the list badge. `unreadCount` is
  /// legacy and may be cleared after Rules that allow it are deployed; do
  /// not include it here until production Rules include `unreadCount`.
  static Map<String, Object?> clearMyUnreadPatch(String myUid) {
    return <String, Object?>{
      'unread.$myUid': 0,
    };
  }

  /// Presence watermark written with the clear (or alone).
  static Map<String, Object?> presenceReadWatermarkPatch(String myUid) {
    return <String, Object?>{
      'uid': myUid,
      'lastReadAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Apply clear + watermark in one batch. Throws on permission-denied so
  /// callers can keep a pending retry (never swallow permanently).
  static Future<void> commitClearUnread({
    required FirebaseFirestore db,
    required DocumentReference<Map<String, dynamic>> conversationRef,
    required DocumentReference<Map<String, dynamic>> presenceRef,
    required String myUid,
    required bool clearUnread,
  }) async {
    final batch = db.batch();
    batch.set(
      presenceRef,
      presenceReadWatermarkPatch(myUid),
      SetOptions(merge: true),
    );
    if (clearUnread) {
      batch.update(conversationRef, clearMyUnreadPatch(myUid));
    }
    await batch.commit();
  }
}

/// Pure scenario for "B→A unread clears on A's view without A sending".
class UnreadViewClearScenario {
  UnreadViewClearScenario._();

  /// After B sends, A's list badge must be > 0.
  static int badgeAfterPeerSend({
    required Map<String, dynamic> conversation,
    required String viewerUid,
  }) {
    return _unreadFor(conversation, viewerUid);
  }

  /// After viewer opens chat and clear write succeeds (no reply).
  static Map<String, dynamic> conversationAfterViewClear({
    required Map<String, dynamic> before,
    required String viewerUid,
  }) {
    final next = Map<String, dynamic>.from(before);
    final unread = Map<String, dynamic>.from(
      (before['unread'] is Map) ? before['unread'] as Map : {},
    );
    unread[viewerUid] = 0;
    next['unread'] = unread;
    final count = Map<String, dynamic>.from(
      (before['unreadCount'] is Map) ? before['unreadCount'] as Map : {},
    );
    if (count.containsKey(viewerUid) || before['unreadCount'] is Map) {
      count[viewerUid] = 0;
      next['unreadCount'] = count;
    }
    return next;
  }

  /// Sender must never zero the peer's unread by viewing.
  static Map<String, dynamic> conversationAfterSenderView({
    required Map<String, dynamic> before,
    required String senderUid,
    required String peerUid,
  }) {
    // Sender viewing their own sent thread: only sender's counter is cleared.
    return conversationAfterViewClear(before: before, viewerUid: senderUid);
  }

  static bool peerStillHasUnread({
    required Map<String, dynamic> conversation,
    required String peerUid,
  }) {
    return _unreadFor(conversation, peerUid) > 0;
  }

  static int _unreadFor(Map<String, dynamic> data, String uid) {
    final unreadRaw = data['unread'];
    if (unreadRaw is Map && unreadRaw.containsKey(uid)) {
      final v = unreadRaw[uid];
      if (v is int) return v;
      if (v is num) return v.toInt();
    }
    final countRaw = data['unreadCount'];
    if (countRaw is Map && countRaw.containsKey(uid)) {
      final v = countRaw[uid];
      if (v is int) return v;
      if (v is num) return v.toInt();
    }
    return 0;
  }
}
