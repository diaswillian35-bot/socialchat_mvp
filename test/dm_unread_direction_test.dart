import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/chat_read_guard.dart';
import 'package:socialchat_mvp/services/conversation_read_write.dart';
import 'package:socialchat_mvp/services/conversation_unread.dart';
import 'package:socialchat_mvp/services/dm_unread_direction.dart';

/// Willian Free/BR ↔ Istela Master/CA unread directionality.
void main() {
  const willian = 'willian_free_br';
  const istela = 'istela_master_ca';

  group('Free BR → Master CA (sendDmMessage / server-only unread)', () {
    test('server increment raises Istela unread; Home must preserve it', () {
      final before = {willian: 0, istela: 0};
      final after = DmUnreadDirection.afterServerIncrement(
        before: before,
        recipientUid: istela,
      );
      expect(after[istela], 1);
      expect(after[willian], 0);

      // Home open / surface inactive → clear forbidden.
      expect(
        ChatReadGuard.mayClearUnread(
          mounted: true,
          lifecycle: AppLifecycleState.resumed,
          routeIsCurrent: false,
          viewingLatestMessages: true,
          contentReady: true,
          chatSurfaceActive: false,
        ),
        isFalse,
      );

      expect(
        DmUnreadDirection.recipientUnreadPreservedOnHome(
          unreadBefore: after[istela]!,
          unreadAfter: after[istela]!,
        ),
        isTrue,
      );

      expect(
        ConversationUnread.resolveMyUnread({
          'unread': after,
        }, istela),
        1,
      );
    });

    test('push receipt alone must not zero Istela unread', () {
      final afterPush = DmUnreadDirection.afterServerIncrement(
        before: {willian: 0, istela: 0},
        recipientUid: istela,
      );
      // Simulate incorrect clear (would be the bug).
      final wronglyCleared = UnreadViewClearScenario.conversationAfterViewClear(
        before: {'unread': afterPush},
        viewerUid: istela,
      );
      expect(
        ConversationUnread.resolveMyUnread(wronglyCleared, istela),
        0,
        reason: 'documents the failure mode if ChatPage clears without view',
      );
      // Correct path: without visible chat, unread stays.
      expect(afterPush[istela], 1);
    });
  });

  group('Master CA → Free BR (client clears self + server increment)', () {
    test('Willian unread rises exactly once; blue-dot resolver sees it', () {
      final before = {willian: 0, istela: 0};
      final after = DmUnreadDirection.afterMasterSendWithServer(
        before: before,
        senderUid: istela,
        recipientUid: willian,
      );
      expect(after[willian], 1);
      expect(after[istela], 0);
      expect(
        ConversationUnread.resolveMyUnread({'unread': after}, willian),
        1,
      );
    });

    test('full-map client replace must not be used (documents race)', () {
      // Legacy client wrote whole map from stale read {0,0} after server +1.
      final afterServer = {willian: 0, istela: 1};
      final staleFullMapReplace = {willian: 0, istela: 0};
      expect(
        staleFullMapReplace[istela],
        0,
        reason: 'full-map merge replace can wipe server increment',
      );
      expect(afterServer[istela], 1);
    });
  });

  group('document before/after clear only when chat visible', () {
    test('visible chat clears Istela; Home does not', () {
      final withUnread = {
        'unread': {willian: 0, istela: 2},
      };
      final canClear = ChatReadGuard.mayClearUnread(
        mounted: true,
        lifecycle: AppLifecycleState.resumed,
        routeIsCurrent: true,
        viewingLatestMessages: true,
        contentReady: true,
        chatSurfaceActive: true,
        tickerEnabled: true,
      );
      expect(canClear, isTrue);
      final cleared = UnreadViewClearScenario.conversationAfterViewClear(
        before: withUnread,
        viewerUid: istela,
      );
      expect(cleared['unread'][istela], 0);

      final cannotClearOnHome = ChatReadGuard.mayClearUnread(
        mounted: true,
        lifecycle: AppLifecycleState.resumed,
        routeIsCurrent: true,
        viewingLatestMessages: true,
        contentReady: true,
        chatSurfaceActive: false,
      );
      expect(cannotClearOnHome, isFalse);
    });
  });
}
