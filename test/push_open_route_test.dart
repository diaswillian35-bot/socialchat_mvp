import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/push_open_logic.dart';

void main() {
  const conversation = 'uidAlpha_uidBeta';
  const peer = 'uidBeta';
  const group = 'groupYork1';
  const event = 'eventToronto1';

  PushOpenQueue queue() {
    final q = PushOpenQueue();
    addTearDown(q.reset);
    return q;
  }

  test('DM, group and event payloads keep their destination', () {
    final chat = PushOpenParser.parse({
      'type': 'chat',
      'conversationId': conversation,
      'otherUid': peer,
      'otherName': 'Ana & Bia',
    });
    expect(chat.kind, PushOpenKind.chat);
    expect(chat.shellIndex, 1);
    expect(chat.conversationId, conversation);
    expect(chat.displayName, 'Ana & Bia');

    final privateChat = PushOpenParser.parse({
      'type': 'private',
      'conversationId': conversation,
      'senderId': peer,
    });
    expect(privateChat.kind, PushOpenKind.chat);

    final groupChat = PushOpenParser.parse({
      'type': 'group',
      'groupId': group,
    });
    expect(groupChat.kind, PushOpenKind.groupChat);
    expect(groupChat.shellIndex, 2);

    for (final type in [
      'event',
      'event_comment',
      'event_reply',
      'event_approved',
      'event_moderation',
      'event_changes_approved',
    ]) {
      final target = PushOpenParser.parse({
        'type': type,
        'eventId': event,
      });
      expect(target.kind, PushOpenKind.event, reason: type);
      expect(target.shellIndex, 3, reason: type);
      expect(target.eventId, event, reason: type);
    }
  });

  test('invalid payload does not become a route', () {
    expect(
      PushOpenParser.parse({'type': 'chat', 'conversationId': conversation}).kind,
      PushOpenKind.none,
    );
    expect(
      PushOpenParser.parse({
        'type': 'group',
        'groupId': 'bad/id',
      }).kind,
      PushOpenKind.none,
    );
    expect(
      PushOpenParser.parse({'type': 'event'}).kind,
      PushOpenKind.none,
    );
    expect(PushOpenParser.parse({'type': 'unknown'}).kind, PushOpenKind.none);
    expect(PushOpenParser.logFields(PushOpenTarget.none)['kind'], 'none');
  });

  test('local payload round-trips names without leaking into the log', () {
    final raw = {
      'type': 'chat',
      'conversationId': conversation,
      'otherUid': peer,
      'otherName': 'Ana & Bia=1',
    };
    final encoded = PushOpenParser.encodeData(raw);
    expect(encoded.contains('Ana & Bia=1'), isFalse);
    final decoded = PushOpenParser.decodeData(encoded);
    final target = PushOpenParser.parse(decoded);
    expect(target.kind, PushOpenKind.chat);
    expect(target.displayName, 'Ana & Bia=1');
    final log = PushOpenParser.logFields(target).values.join(' ');
    expect(log.contains(conversation), isFalse);
    expect(log.contains('Ana'), isFalse);
  });

  test('cold start stays pending until the shell is ready, then once', () {
    final q = queue();
    final target = PushOpenParser.parse(
      {
        'type': 'chat',
        'conversationId': conversation,
        'otherUid': peer,
      },
      messageId: 'msg-1',
    );
    expect(q.offer(target), isTrue);
    expect(q.peekIfReady(ready: false), isNull);
    expect(q.pending, isNotNull);
    final ready = q.peekIfReady(ready: true);
    expect(ready?.kind, PushOpenKind.chat);
    q.consume(ready!);
    expect(q.pending, isNull);
    expect(q.offer(target), isFalse);
  });

  test('background and cold start with the same message open once', () {
    final q = queue();
    final data = {
      'type': 'group',
      'groupId': group,
    };
    final cold = PushOpenParser.parse(data, messageId: 'same');
    final background = PushOpenParser.parse(data, messageId: 'same');
    expect(q.offer(cold), isTrue);
    expect(q.offer(background), isTrue);
    expect(q.pending?.dedupeKey, 'm:same');
    q.consume(cold);
    expect(
      q.offer(PushOpenParser.parse(data, messageId: 'same')),
      isFalse,
    );
  });

  test('a later message in the same chat is not dropped', () {
    final q = queue();
    final first = PushOpenParser.parse(
      {
        'type': 'chat',
        'conversationId': conversation,
        'otherUid': peer,
      },
      messageId: 'msg-1',
    );
    final second = PushOpenParser.parse(
      {
        'type': 'chat',
        'conversationId': conversation,
        'otherUid': peer,
      },
      messageId: 'msg-2',
    );
    q.offer(first);
    q.consume(first);
    expect(q.offer(second), isTrue);
    expect(q.pending?.dedupeKey, 'm:msg-2');
  });
}
