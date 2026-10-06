import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/block_report_logic.dart';
import 'package:socialchat_mvp/services/block_visibility.dart';

void main() {
  tearDown(() {
    BlockVisibility.debugReplace({});
  });

  test('noteBlocked hides immediately without restart', () {
    expect(BlockVisibility.hidesUid('peer'), isFalse);
    BlockVisibility.noteBlocked('peer');
    expect(BlockVisibility.hidesUid('peer'), isTrue);
    expect(
      BlockVisibility.hidesConversation(
        data: {
          'participants': ['me', 'peer'],
        },
        myUid: 'me',
      ),
      isTrue,
    );
  });

  test('noteUnblocked restores visibility', () {
    BlockVisibility.noteBlocked('peer');
    BlockVisibility.noteUnblocked('peer');
    expect(BlockVisibility.hidesUid('peer'), isFalse);
    expect(
      BlockVisibility.hidesConversation(
        data: {
          'participants': ['me', 'peer'],
        },
        myUid: 'me',
      ),
      isFalse,
    );
  });

  test('group messages from others hide; own sender stays', () {
    BlockVisibility.debugReplace({'peer'});
    expect(
      BlockVisibility.hidesGroupSender(
        senderId: 'peer',
        myUid: 'me',
      ),
      isTrue,
    );
    expect(
      BlockVisibility.hidesGroupSender(
        senderId: 'me',
        myUid: 'me',
      ),
      isFalse,
    );
  });

  test('event authored by blocked user is hidden locally', () {
    BlockVisibility.debugReplace({'org'});
    expect(
      BlockVisibility.hidesEventMap({'createdBy': 'org'}),
      isTrue,
    );
    expect(
      BlockVisibility.hidesEventMap({'createdBy': 'other'}),
      isFalse,
    );
  });

  test('inbox hide is only for the blocker list, not a content delete', () {
    BlockVisibility.debugReplace({'peer'});
    final convo = {
      'participants': ['viewer', 'peer'],
      'lastText': 'hello',
    };
    expect(
      BlockVisibility.hidesConversation(data: convo, myUid: 'viewer'),
      isTrue,
    );
    expect(
      BlockVisibility.hidesConversation(data: convo, myUid: 'peer'),
      isFalse,
    );
    expect(convo['lastText'], 'hello');
  });

  test('item 2 block report still one payload and not duplicated', () async {
    const actor = 'user-a';
    const target = 'user-b';
    final blocked = <String>[];
    final reports = <Map<String, Object>>[];

    expect(
      BlockReportLogic.shouldCreateBlockReport(
        actorUid: actor,
        targetUid: target,
        currentlyBlocked: blocked,
      ),
      isTrue,
    );
    blocked.add(target);
    await BlockReportLogic.afterNewBlockWriteReport(
      actorUid: actor,
      targetUid: target,
      persistReport: (fields) async => reports.add(Map.from(fields)),
    );
    expect(reports, hasLength(1));
    expect(
      BlockReportLogic.shouldCreateBlockReport(
        actorUid: actor,
        targetUid: target,
        currentlyBlocked: blocked,
      ),
      isFalse,
    );
  });
}
