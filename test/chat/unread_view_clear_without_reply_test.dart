import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/conversation_read_write.dart';
import 'package:socialchat_mvp/services/conversation_unread.dart';

/// Regression: blue badge must clear when A opens/views chat WITHOUT replying.
///
/// Physical FAIL on build 16: badge only cleared after A sent a reply because
/// `_markAsRead` wrote `unreadCount` (denied by Rules) while `_send`/`summary`
/// wrote only `unread` (allowed) and zeroed `unread.me` as a side-effect.
void main() {
  group('B→A view-clear without reply (DM national shape)', () {
    const a = 'userA';
    const b = 'userB';

    test('1–5: list keeps badge until view clear; no reply required', () {
      // B sends to A
      final afterSend = <String, dynamic>{
        'participants': [a, b],
        'lastMessage': 'oi',
        'unread': {a: 1, b: 0},
        'unreadCount': {a: 1, b: 0},
      };
      expect(
        UnreadViewClearScenario.badgeAfterPeerSend(
          conversation: afterSend,
          viewerUid: a,
        ),
        1,
      );
      // A opens list only → same doc, badge remains
      expect(ConversationUnread.resolveMyUnread(afterSend, a), 1);

      // A enters chat and views — clear write (no send)
      final afterView = UnreadViewClearScenario.conversationAfterViewClear(
        before: afterSend,
        viewerUid: a,
      );
      expect(ConversationUnread.resolveMyUnread(afterView, a), 0);
      expect(afterView['lastMessage'], 'oi'); // unchanged — no reply
      expect(
        (afterView['unread'] as Map)[b],
        0,
      ); // sender's counter untouched

      // Close/reopen list → still cleared
      expect(ConversationUnread.resolveMyUnread(afterView, a), 0);

      // B sends another → badge returns
      final again = Map<String, dynamic>.from(afterView);
      again['unread'] = {a: 1, b: 0};
      expect(ConversationUnread.resolveMyUnread(again, a), 1);
    });

    test('sender viewing must not clear peer unread', () {
      final before = <String, dynamic>{
        'unread': {a: 3, b: 0},
      };
      final afterSenderView =
          UnreadViewClearScenario.conversationAfterSenderView(
        before: before,
        senderUid: b,
        peerUid: a,
      );
      expect(
        UnreadViewClearScenario.peerStillHasUnread(
          conversation: afterSenderView,
          peerUid: a,
        ),
        isTrue,
      );
      expect(ConversationUnread.resolveMyUnread(afterSenderView, b), 0);
    });
  });

  group('DM international shape', () {
    test('viewer clear zeros only viewer uid', () {
      const free = 'free1';
      const prem = 'prem1';
      final before = <String, dynamic>{
        'participants': [free, prem],
        'unread': {free: 2, prem: 0},
      };
      final after = UnreadViewClearScenario.conversationAfterViewClear(
        before: before,
        viewerUid: free,
      );
      expect(ConversationUnread.resolveMyUnread(after, free), 0);
      expect(ConversationUnread.resolveMyUnread(after, prem), 0);
      expect(
        UnreadViewClearScenario.peerStillHasUnread(
          conversation: after,
          peerUid: prem,
        ),
        isFalse,
      );
    });
  });

  group('Group shape', () {
    test('member clear zeros only that member in unread map', () {
      const me = 'm1';
      const other = 'm2';
      final before = <String, dynamic>{
        'members': [me, other],
        'unread': {me: 4, other: 1},
      };
      final after = UnreadViewClearScenario.conversationAfterViewClear(
        before: before,
        viewerUid: me,
      );
      expect(ConversationUnread.resolveMyUnread(after, me), 0);
      expect(ConversationUnread.resolveMyUnread(after, other), 1);
    });
  });

  group('ConversationReadWrite patch ↔ Rules contract', () {
    test('clear patch only touches unread (Rules hasOnly without deploy risk)', () {
      final patch = ConversationReadWrite.clearMyUnreadPatch('uidA');
      expect(patch.keys.toSet(), {'unread.uidA'});
      expect(patch.containsKey('unreadCount.uidA'), isFalse);
      expect(patch.containsKey('lastMessage'), isFalse);
      expect(patch.containsKey('participants'), isFalse);
    });

    test('send-side zero of own unread is independent of view clear', () {
      // Document that reply still zeros own counter (hygiene) but must not be
      // required for the list badge to clear.
      final afterSendByViewer = <String, dynamic>{
        'lastMessage': 'minha resposta',
        'unread': {'uidA': 0, 'uidB': 1},
      };
      expect(ConversationUnread.resolveMyUnread(afterSendByViewer, 'uidA'), 0);
      // View clear alone already achieves the same for uidA without lastMessage change.
      final viewOnly = UnreadViewClearScenario.conversationAfterViewClear(
        before: {
          'lastMessage': 'oi',
          'unread': {'uidA': 2, 'uidB': 0},
        },
        viewerUid: 'uidA',
      );
      expect(viewOnly['lastMessage'], 'oi');
      expect(ConversationUnread.resolveMyUnread(viewOnly, 'uidA'), 0);
    });
  });

  group('coordinator: view clear not gated on send', () {
    test('writes unread zero when mayClear and myUnread > 0', () {
      expect(
        ChatUnreadClearCoordinator.shouldWriteUnreadZero(
          mayClear: true,
          myUnread: 2,
        ),
        isTrue,
      );
    });

    test('does not write when not viewing / mayClear false', () {
      expect(
        ChatUnreadClearCoordinator.shouldWriteUnreadZero(
          mayClear: false,
          myUnread: 2,
        ),
        isFalse,
      );
    });
  });
}
