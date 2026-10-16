import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/conversation_read_write.dart';
import 'package:socialchat_mvp/services/conversation_unread.dart';

void main() {
  const me = 'uidReader';
  const peer = 'uidSender';

  test('literal DM unread is visible and a nested zero wins', () {
    expect(
      ConversationUnread.resolveMyUnread({'unread.$me': 3}, me),
      3,
    );
    expect(
      ConversationUnread.resolveMyUnread({
        'unread': {me: 0},
        'unread.$me': 3,
      }, me),
      0,
    );
    expect(
      ConversationUnread.resolveMyUnread({'unread': {peer: 2}}, me),
      0,
    );
    expect(
      ConversationUnread.resolveMyUnread({'unread. $me': 4}, me),
      4,
    );
    expect(
      ConversationUnread.resolveMyUnread({
        'unread': {me: 0},
        'unread. $me': 4,
      }, me),
      0,
    );
  });

  test('view clear writes nested zero without touching the peer', () {
    final patch = ConversationReadWrite.clearMyUnreadPatch(me);
    expect(patch.keys, {'unread.$me'});
    expect(patch['unread.$me'], 0);
    expect(patch.containsKey('unread.$peer'), isFalse);

    final after = UnreadViewClearScenario.conversationAfterViewClear(
      before: {'unread': {me: 2, peer: 1}},
      viewerUid: me,
    );
    expect(ConversationUnread.resolveMyUnread(after, me), 0);
    expect(ConversationUnread.resolveMyUnread(after, peer), 1);
  });

  test('group literal unread is the same count the list badge uses', () {
    final data = {'unread.member': 4, 'unread': {'owner': 0}};
    expect(ConversationUnread.resolveMyUnread(data, 'member'), 4);
    expect(ConversationUnread.resolveMyUnread(data, 'owner'), 0);
    expect(
      ConversationUnread.groupTabBadgeCount([
        data,
        {'deleted': true, 'unread': {'member': 9}},
      ], 'member'),
      1,
    );
  });

  test('opening at the latest messages clears; history and layout do not yet', () {
    expect(
      VisibleUnreadClear.listAtLatest(hasClients: true, offset: 0),
      isTrue,
    );
    expect(
      VisibleUnreadClear.listAtLatest(hasClients: true, offset: 48),
      isTrue,
    );
    expect(
      VisibleUnreadClear.listAtLatest(hasClients: true, offset: 200),
      isFalse,
    );
    expect(
      VisibleUnreadClear.listAtLatest(hasClients: false, offset: 0),
      isFalse,
    );
    expect(
      VisibleUnreadClear.retryWhenLaidOut(pending: true, hasClients: false),
      isTrue,
    );
    expect(
      VisibleUnreadClear.retryWhenLaidOut(pending: true, hasClients: true),
      isFalse,
    );
    expect(
      VisibleUnreadClear.flushOnExit(
        pendingOrUnread: true,
        hasClients: false,
        offset: 0,
      ),
      isTrue,
    );
    expect(
      VisibleUnreadClear.flushOnExit(
        pendingOrUnread: true,
        hasClients: true,
        offset: 0,
      ),
      isTrue,
    );
    expect(
      VisibleUnreadClear.flushOnExit(
        pendingOrUnread: true,
        hasClients: true,
        offset: 200,
      ),
      isFalse,
    );
    expect(
      VisibleUnreadClear.flushOnExit(
        pendingOrUnread: false,
        hasClients: true,
        offset: 0,
      ),
      isFalse,
    );
  });

  test('chat and group screens read the shared resolver and flush on exit', () {
    final chat = File('lib/pages/chat_page.dart').readAsStringSync();
    final group = File('lib/pages/group_chat_page.dart').readAsStringSync();
    expect(chat, contains('ConversationUnread.resolveMyUnread'));
    expect(group, contains('ConversationUnread.resolveMyUnread'));
    expect(chat, contains('_persistOpenUnreadZero'));
    expect(chat, contains('requireViewingLatest: false'));
    expect(group, contains('VisibleUnreadClear.flushOnExit'));
    expect(group, contains('_scheduleGroupReadAfterLayout'));
  });
}
