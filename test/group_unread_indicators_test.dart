import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/conversation_unread.dart';
import 'package:socialchat_mvp/services/group_discovery_logic.dart';

void main() {
  const me = 'member';
  const owner = 'owner';

  test('third-party message shows on the card and the tab', () {
    final data = <String, dynamic>{
      'deleted': false,
      'unread.member': 2,
      'unread': {'owner': 0},
    };
    expect(ConversationUnread.resolveMyUnread(data, me), 2);
    expect(ConversationUnread.groupTabBadgeCount([data], me), 1);
    expect(ConversationUnread.resolveMyUnread(data, owner), 0);
  });

  test('own message does not count for the sender', () {
    final data = <String, dynamic>{
      'unread': {owner: 0, me: 1},
    };
    expect(ConversationUnread.resolveMyUnread(data, owner), 0);
    expect(ConversationUnread.groupTabBadgeCount([data], owner), 0);
    expect(ConversationUnread.groupTabBadgeCount([data], me), 1);
  });

  test('explicit nested zero wins over a stale literal field', () {
    expect(
      ConversationUnread.resolveMyUnread({
        'unread': {me: 0},
        'unread.$me': 4,
      }, me),
      0,
    );
  });

  test('opening only the list does not clear unread', () {
    final cached = [
      GroupDiscoveryItem(
        id: 'g1',
        data: {'unread': {me: 0}},
        isMember: true,
      ),
    ];
    final merged = GroupDiscoveryLogic.mergeUnreadSnapshot(
      items: cached,
      updates: {
        'g1': {'unread.$me': 2, 'unread': {owner: 0}},
      },
    );
    expect(ConversationUnread.resolveMyUnread(merged.single.data, me), 2);
    expect(merged.single.data['unread.$me'], 2);
  });

  test('background snapshot updates both surfaces and keeps several messages', () {
    final cached = [
      GroupDiscoveryItem(
        id: 'g1',
        data: {'name': 'kept', 'unread': {me: 1}},
        isMember: true,
      ),
    ];
    final merged = GroupDiscoveryLogic.mergeUnreadSnapshot(
      items: cached,
      updates: {
        'g1': {'name': 'kept', 'unread': {me: 3}},
      },
    );
    expect(
      GroupDiscoveryLogic.unreadSurfaceChanged(
        before: cached,
        after: merged,
        uid: me,
      ),
      isTrue,
    );
    expect(ConversationUnread.resolveMyUnread(merged.single.data, me), 3);
    expect(
      ConversationUnread.groupTabBadgeCount(
        merged.map((item) => item.data),
        me,
      ),
      1,
    );
  });

  test('hidden ids stay filtered while the badge still sees the document', () {
    final hidden = GroupDiscoveryLogic.excludeHidden(
      items: [
        GroupDiscoveryItem(
          id: 'secret',
          data: {'unread': {me: 2}},
          isMember: true,
        ),
      ],
      hiddenIds: {'secret'},
    );
    expect(hidden, isEmpty);
    expect(
      ConversationUnread.groupTabBadgeCount([
        {'unread': {me: 2}},
      ], me),
      1,
    );
  });

  test('group list listens for unread and does not mark the group read', () {
    final source = File('lib/pages/groups_list_page.dart').readAsStringSync();
    expect(source, contains('_bindMemberUnread'));
    expect(source, contains("where('deleted', isEqualTo: false)"));
    expect(source, isNot(contains('markGroupAsRead')));
    expect(source, isNot(contains('markAsRead')));
    final shell = File('lib/pages/main_shell_page.dart').readAsStringSync();
    expect(shell, contains('ConversationUnread.resolveMyUnread'));
  });
}
