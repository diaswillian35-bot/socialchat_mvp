/// Pure routing for a notification tap. No Firestore, no Navigator, no PII.
class PushOpenTarget {
  const PushOpenTarget({
    required this.kind,
    required this.dedupeKey,
    this.conversationId = '',
    this.otherUid = '',
    this.groupId = '',
    this.eventId = '',
    this.placeId = '',
    this.actorUid = '',
    this.displayName = '',
    this.shellIndex = 0,
  });

  final PushOpenKind kind;
  final String dedupeKey;
  final String conversationId;
  final String otherUid;
  final String groupId;
  final String eventId;
  final String placeId;
  final String actorUid;
  final String displayName;

  /// Messages = 1, groups = 2, events = 3. Home stays 0 for an invalid tap.
  final int shellIndex;

  bool get isValid => kind != PushOpenKind.none;

  static const none = PushOpenTarget(kind: PushOpenKind.none, dedupeKey: '');
}

enum PushOpenKind { none, chat, groupChat, groupInfo, groupTab, event, place }

enum PushOpenSource { foregroundLocal, background, coldStart }

/// Holds one tap until auth, age verification and the navigator exist.
/// The same [RemoteMessage.messageId] from cold start and background is one tap.
class PushOpenQueue {
  PushOpenTarget? pending;
  String? consumedKey;

  void reset() {
    pending = null;
    consumedKey = null;
  }

  /// Returns true when the tap is now the pending destination.
  bool offer(PushOpenTarget target) {
    if (!target.isValid || target.dedupeKey.isEmpty) return false;
    if (consumedKey == target.dedupeKey) return false;
    if (pending?.dedupeKey == target.dedupeKey) return true;
    pending = target;
    return true;
  }

  /// Null while the shell is not ready. Does not drop [pending].
  PushOpenTarget? peekIfReady({required bool ready}) {
    if (!ready) return null;
    return pending;
  }

  /// Call only after the destination route was pushed.
  void consume(PushOpenTarget target) {
    if (pending?.dedupeKey == target.dedupeKey) {
      pending = null;
    }
    consumedKey = target.dedupeKey;
  }
}

class PushOpenParser {
  PushOpenParser._();

  static final RegExp _id = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

  static bool isSafeId(String raw) {
    final value = raw.trim();
    return _id.hasMatch(value);
  }

  static PushOpenTarget parse(
    Map<String, dynamic> data, {
    String? messageId,
  }) {
    final type = (data['type'] ?? '').toString().trim();
    final conversationId = (data['conversationId'] ?? '').toString().trim();
    final otherUid =
        (data['otherUid'] ?? data['senderId'] ?? '').toString().trim();
    final groupId = (data['groupId'] ?? '').toString().trim();
    final eventId = (data['eventId'] ?? '').toString().trim();
    final placeId = (data['placeId'] ?? '').toString().trim();
    final actorUid = (data['senderId'] ??
            data['fromUid'] ??
            data['commentAuthorUid'] ??
            data['authorUid'] ??
            '')
        .toString()
        .trim();
    final displayName =
        (data['otherName'] ?? data['groupName'] ?? '').toString().trim();

    PushOpenKind kind = PushOpenKind.none;
    var shellIndex = 0;
    if (type == 'place_review' || type == 'place_reply') {
      if (!isSafeId(placeId)) return PushOpenTarget.none;
      kind = PushOpenKind.place;
      shellIndex = 4;
    } else if (_isEvent(type)) {
      if (!isSafeId(eventId)) return PushOpenTarget.none;
      kind = PushOpenKind.event;
      shellIndex = 3;
    } else if (type == 'group' || type == 'group_join_approved') {
      if (!isSafeId(groupId)) return PushOpenTarget.none;
      kind = PushOpenKind.groupChat;
      shellIndex = 2;
    } else if (type == 'group_join_request') {
      if (!isSafeId(groupId)) return PushOpenTarget.none;
      kind = PushOpenKind.groupInfo;
      shellIndex = 2;
    } else if (type == 'group_join_rejected') {
      if (!isSafeId(groupId)) return PushOpenTarget.none;
      kind = PushOpenKind.groupTab;
      shellIndex = 2;
    } else if (type == 'chat' || type == 'private') {
      if (!isSafeId(conversationId) || !isSafeId(otherUid)) {
        return PushOpenTarget.none;
      }
      kind = PushOpenKind.chat;
      shellIndex = 1;
    } else {
      return PushOpenTarget.none;
    }

    final mid = (messageId ?? '').trim();
    final dedupeKey = mid.isNotEmpty
        ? 'm:$mid'
        : 't:$type|c:$conversationId|g:$groupId|e:$eventId|p:$placeId|o:$otherUid';
    return PushOpenTarget(
      kind: kind,
      dedupeKey: dedupeKey,
      conversationId: conversationId,
      otherUid: otherUid,
      groupId: groupId,
      eventId: eventId,
      placeId: placeId,
      actorUid: isSafeId(actorUid) ? actorUid : '',
      displayName: displayName,
      shellIndex: shellIndex,
    );
  }

  static bool _isEvent(String type) {
    return type == 'event' ||
        type == 'event_approved' ||
        type == 'event_rejected' ||
        type == 'event_needs_changes' ||
        type == 'event_changes_approved' ||
        type == 'event_changes_submitted' ||
        type == 'event_moderation' ||
        type == 'event_comment' ||
        type == 'event_reply';
  }

  /// Local-notification payload. Query encoding survives `&` and `=` in names.
  static String encodeData(Map<String, dynamic> data) {
    final params = <String, String>{};
    for (final entry in data.entries) {
      final key = entry.key.trim();
      if (key.isEmpty || key.contains('&') || key.contains('=')) continue;
      params[key] = entry.value?.toString() ?? '';
    }
    return Uri(queryParameters: params).query;
  }

  static Map<String, String> decodeData(String payload) {
    if (payload.trim().isEmpty) return const {};
    try {
      return Uri.splitQueryString(payload);
    } catch (_) {
      return const {};
    }
  }

  /// Log fields only. Never the id, name, or token.
  static Map<String, String> logFields(PushOpenTarget target) {
    return <String, String>{
      'kind': target.kind.name,
      'shell': '${target.shellIndex}',
      'hasConversation': target.conversationId.isEmpty ? '0' : '1',
      'hasGroup': target.groupId.isEmpty ? '0' : '1',
      'hasEvent': target.eventId.isEmpty ? '0' : '1',
      'hasPlace': target.placeId.isEmpty ? '0' : '1',
    };
  }
}
