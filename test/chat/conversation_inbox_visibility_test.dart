import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/conversation_inbox_visibility.dart';

void main() {
  const me = 'uidMe';
  const mom = 'uidMom';
  const stranger = 'uidNeverChatted';

  group('ConversationInboxVisibility', () {
    test('delete-for-me leaves hiddenFor; list hides until unhide', () {
      final afterDelete = <String, dynamic>{
        'participants': [me, mom],
        'lastMessage': 'oi mãe',
        'hiddenFor': [me],
      };
      expect(
        ConversationInboxVisibility.shouldShowInMessagesTab(
          data: afterDelete,
          myUid: me,
        ),
        isFalse,
      );
      expect(
        ConversationInboxVisibility.isHiddenForMe(afterDelete['hiddenFor'], me),
        isTrue,
      );
    });

    test('new real send unhides sender and conversation reappears', () {
      final hidden = <String>[me];
      final afterSendHidden = List<String>.from(hidden)..remove(me);
      final afterSend = <String, dynamic>{
        'participants': [me, mom],
        'lastMessage': 'oi de novo',
        'hiddenFor': afterSendHidden,
      };
      expect(
        ConversationInboxVisibility.shouldShowInMessagesTab(
          data: afterSend,
          myUid: me,
        ),
        isTrue,
      );
    });

    test('incoming real message unhides recipient', () {
      final afterReceive = <String, dynamic>{
        'participants': [me, mom],
        'lastMessage': 'filha',
        'hiddenFor': <String>[],
      };
      expect(
        ConversationInboxVisibility.shouldShowInMessagesTab(
          data: afterReceive,
          myUid: me,
        ),
        isTrue,
      );
    });

    test('user with empty lastMessage stays off Messages (flag only)', () {
      final shell = <String, dynamic>{
        'participants': [me, stranger],
        'lastMessage': '',
        'hiddenFor': <String>[],
      };
      expect(
        ConversationInboxVisibility.shouldShowInMessagesTab(
          data: shell,
          myUid: me,
        ),
        isFalse,
      );
      expect(ConversationInboxVisibility.hasListPreview(''), isFalse);
      expect(ConversationInboxVisibility.hasListPreview('   '), isFalse);
    });

    test('does not restore message-level hiddenFor as inbox visibility', () {
      final inbox = <String, dynamic>{
        'participants': [me, mom],
        'lastMessage': 'nova',
        'hiddenFor': <String>[],
      };
      expect(
        ConversationInboxVisibility.shouldShowInMessagesTab(
          data: inbox,
          myUid: me,
        ),
        isTrue,
      );
      // Message docs can still have hiddenFor; inbox helper only reads parent.
      expect(inbox.containsKey('deletedFor'), isFalse);
    });

    test('parent summary patch includes lastMessage and hiddenFor unhide', () {
      final patch = ConversationInboxVisibility.parentSummaryAfterRealMessage(
        lastMessage: 'oi de novo',
        myUid: me,
        otherUid: mom,
      );
      expect(patch['lastMessage'], 'oi de novo');
      expect(patch.containsKey('lastMessageAt'), isTrue);
      expect(patch.containsKey('updatedAt'), isTrue);
      expect(patch['unread.$me'], 0);
      expect(patch.containsKey('hiddenFor'), isTrue);
      expect(patch.containsKey('participants'), isFalse);
    });

    test('list and send paths unhide parent hiddenFor, not message docs', () {
      final messages = File('lib/pages/messages_page.dart').readAsStringSync();
      expect(messages, contains('ConversationInboxVisibility.shouldShowInMessagesTab'));
      expect(messages, contains("arrayUnion([myUid])"));

      final chat = File('lib/pages/chat_page.dart').readAsStringSync();
      expect(chat, contains('parentSummaryAfterRealMessage'));
      expect(chat, contains('hiddenForUnhide'));

      final outgoing =
          File('lib/services/outgoing_text_message_service.dart').readAsStringSync();
      expect(outgoing, contains('parentSummaryAfterRealMessage'));

      final trigger = File('functions/index.js').readAsStringSync();
      expect(trigger, contains('senderId, ...targetUids'));
      expect(trigger.contains('arrayRemove(...targetUids)'), isFalse);
    });
  });
}
