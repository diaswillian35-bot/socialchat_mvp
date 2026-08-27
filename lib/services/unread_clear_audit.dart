import 'package:flutter/foundation.dart';

/// Profile/debug-only sanitized traces for unread clear diagnosis.
/// Never logs full UIDs, tokens, or message bodies.
class UnreadClearAudit {
  UnreadClearAudit._();

  static bool get _enabled => !kIsWeb && (kProfileMode || kDebugMode);

  static String get _bundleVersion {
    final mode = kProfileMode ? 'profile' : (kDebugMode ? 'debug' : 'release');
    return 'com.remdy.app ($mode)';
  }

  static String maskUid(String? uid) {
    final u = (uid ?? '').trim();
    if (u.length < 10) return '[short]';
    return '${u.substring(0, 6)}…${u.substring(u.length - 4)}';
  }

  /// One-line sanitized clear attempt (or skip).
  static void logClearAttempt({
    required String caller,
    required String reason,
    required bool willClear,
    required int unreadBefore,
    required String lifecycle,
    required bool routeIsCurrent,
    required bool chatSurfaceActive,
    required bool tickerEnabled,
    required bool contentReady,
    required bool viewingLatest,
    required bool mounted,
    String? uidMasked,
    String? activeSurface,
    String? activeConversationMasked,
    String? thisConversationMasked,
    Map<String, bool>? mayClearConditions,
  }) {
    if (!_enabled) return;
    final cond = mayClearConditions == null
        ? ''
        : ' mayClearConditions=${mayClearConditions.entries.map((e) => '${e.key}=${e.value}').join(',')}';
    // ignore: avoid_print
    print(
      'UnreadClearAudit '
      'bundle=$_bundleVersion '
      'uid=${uidMasked ?? "-"} '
      'surface=${activeSurface ?? "-"} '
      'caller=$caller '
      'reason=$reason '
      'willClear=$willClear '
      'unreadBefore=$unreadBefore '
      'lifecycle=$lifecycle '
      'routeCurrent=$routeIsCurrent '
      'surfaceActive=$chatSurfaceActive '
      'ticker=$tickerEnabled '
      'contentReady=$contentReady '
      'viewingLatest=$viewingLatest '
      'mounted=$mounted '
      'activeConv=${activeConversationMasked ?? "-"} '
      'thisConv=${thisConversationMasked ?? "-"}'
      '$cond',
    );
  }

  static void logReadWrite({
    required String caller,
    required bool clearUnread,
    required String uidMasked,
  }) {
    if (!_enabled) return;
    // ignore: avoid_print
    print(
      'UnreadClearAudit ConversationReadWrite '
      'bundle=$_bundleVersion '
      'caller=$caller '
      'clearUnread=$clearUnread '
      'uid=$uidMasked',
    );
  }

  static void logBadgeSync({required int count, required String source}) {
    if (!_enabled) return;
    // ignore: avoid_print
    print('UnreadClearAudit badgeSync source=$source count=$count');
  }
}
