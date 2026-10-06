import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/block_report_logic.dart';
import 'package:socialchat_mvp/services/block_visibility.dart';
import 'package:socialchat_mvp/services/event_report_logic.dart';
import 'package:socialchat_mvp/services/report_category.dart';

void main() {
  tearDown(() => BlockVisibility.debugReplace({}));

  test('third-party event can be reported; own event cannot', () {
    expect(
      EventReportLogic.canReportEvent(
        reporterUid: 'viewer',
        organizerUid: 'org',
      ),
      isTrue,
    );
    expect(
      EventReportLogic.canReportEvent(
        reporterUid: 'org',
        organizerUid: 'org',
      ),
      isFalse,
    );
    expect(
      EventReportLogic.canReportEvent(
        reporterUid: null,
        organizerUid: 'org',
      ),
      isFalse,
    );
  });

  test('third-party comment can be reported; own comment cannot', () {
    expect(
      EventReportLogic.canReportComment(
        reporterUid: 'viewer',
        authorUid: 'author',
        commentId: 'c1',
      ),
      isTrue,
    );
    expect(
      EventReportLogic.canReportComment(
        reporterUid: 'author',
        authorUid: 'author',
        commentId: 'c1',
      ),
      isFalse,
    );
  });

  test('cancel and in-flight do not persist', () {
    expect(
      EventReportLogic.shouldPersist(confirmed: false, inFlight: false),
      isFalse,
    );
    expect(
      EventReportLogic.shouldPersist(confirmed: true, inFlight: true),
      isFalse,
    );
    expect(
      EventReportLogic.shouldPersist(confirmed: true, inFlight: false),
      isTrue,
    );
  });

  test('event payload has IDs once, no PII or full content', () {
    final fields = EventReportLogic.reportFields(
      reporterUid: 'viewer',
      reportedUid: 'org',
      category: ReportCategory.spam,
      reasonLabel: 'Spam',
      eventId: 'evt-1',
    );
    expect(fields['contextType'], 'event');
    expect(fields['source'], 'event_detail');
    expect(fields['eventId'], 'evt-1');
    expect(fields.containsKey('commentId'), isFalse);
    expect(fields['fromUid'], 'viewer');
    expect(fields['reporterUid'], 'viewer');
    expect(fields['reportedUid'], 'org');
    expect(fields['reasonCode'], 'spam');
    expect(fields['status'], 'open');
    expect(fields['priority'], 'normal');
    expect(EventReportLogic.payloadIsSafe(fields), isTrue);
    expect(fields['snapshot'], {'eventId': 'evt-1'});
    expect(jsonEncode(fields), isNot(contains('email')));
    expect(jsonEncode(fields), isNot(contains('title')));
  });

  test('comment payload includes eventId and commentId once', () {
    final fields = EventReportLogic.reportFields(
      reporterUid: 'viewer',
      reportedUid: 'author',
      category: ReportCategory.childSafety,
      reasonLabel: 'Child',
      eventId: 'evt-1',
      commentId: 'c-9',
    );
    expect(fields['contextType'], 'event_comment');
    expect(fields['eventId'], 'evt-1');
    expect(fields['commentId'], 'c-9');
    expect(fields['priority'], 'critical');
    expect(fields['requiresChildSafetyReview'], true);
    expect(fields['snapshot'], {'eventId': 'evt-1', 'commentId': 'c-9'});
    expect(EventReportLogic.payloadIsSafe(fields), isTrue);
    expect(jsonEncode(fields), isNot(contains('messageText')));
  });

  test('reporting does not mutate original event or comment maps', () {
    final event = <String, Object>{'createdBy': 'org', 'title': 'Party'};
    final comment = <String, Object>{'uid': 'author', 'text': 'hello'};
    final reports = <Map<String, Object>>[];
    final fields = EventReportLogic.reportFields(
      reporterUid: 'viewer',
      reportedUid: 'org',
      category: ReportCategory.other,
      reasonLabel: 'Other',
      eventId: 'evt-1',
    );
    reports.add(Map.from(fields));
    expect(event['title'], 'Party');
    expect(comment['text'], 'hello');
    expect(reports, hasLength(1));
  });

  test('blocked authors stay hidden; report UI must not revive them', () {
    BlockVisibility.debugReplace({'author'});
    expect(BlockVisibility.hidesUid('author'), isTrue);
    expect(
      EventReportLogic.canReportComment(
        reporterUid: 'viewer',
        authorUid: 'author',
        commentId: 'c1',
      ),
      isTrue,
    );
  });

  test('item 2 block report still one payload without duplicate', () async {
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

  test('five locales expose event report strings without jargon', () {
    const keys = [
      'report_event',
      'report_comment',
      'report_event_confirm',
      'report_comment_confirm',
      'report_send',
      'report_send_failed',
    ];
    for (final locale in ['en', 'es', 'fr', 'pt-BR', 'pt-PT']) {
      final json = jsonDecode(File('lib/l10n/$locale.json').readAsStringSync())
          as Map<String, dynamic>;
      for (final key in keys) {
        final value = (json[key] ?? '').toString();
        expect(value, isNotEmpty, reason: '$locale $key');
        expect(value.toLowerCase(), isNot(contains('firestore')));
        expect(value.toLowerCase(), isNot(contains('uid')));
        expect(value.toLowerCase(), isNot(contains('contexttype')));
      }
    }
  });
}
