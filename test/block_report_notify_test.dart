import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/block_report_logic.dart';
import 'package:socialchat_mvp/services/report_category.dart';

void main() {
  const actor = 'user-a';
  const target = 'user-b';

  group('Block → existing reports collection (Guideline 1.2)', () {
    test('blocking creates exactly one report payload', () async {
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
      final outcome = await BlockReportLogic.afterNewBlockWriteReport(
        actorUid: actor,
        targetUid: target,
        persistReport: (fields) async => reports.add(Map.from(fields)),
      );

      expect(outcome.applied, isTrue);
      expect(outcome.newlyBlocked, isTrue);
      expect(outcome.reportWritten, isTrue);
      expect(reports, hasLength(1));
      expect(reports.single['reasonCode'], 'user_blocked');
      expect(reports.single['status'], 'open');
      expect(reports.single['contextType'], 'block');
      expect(reports.single['source'], 'block_service');
      expect(reports.single['fromUid'], actor);
      expect(reports.single['reporterUid'], actor);
      expect(reports.single['reportedUid'], target);
    });

    test('blocking again while already blocked does not duplicate', () {
      expect(
        BlockReportLogic.shouldCreateBlockReport(
          actorUid: actor,
          targetUid: target,
          currentlyBlocked: [target],
        ),
        isFalse,
      );
    });

    test('unblock does not create a report (service source)', () {
      final block = File('lib/services/block_service.dart').readAsStringSync();
      final unblock = block.split('static Future<void> unblockUser').last;
      expect(
        unblock.split('isBlockedStream').first,
        isNot(contains("collection('reports')")),
      );
    });

    test('unblock then block again is a new legitimate report', () async {
      expect(
        BlockReportLogic.shouldCreateBlockReport(
          actorUid: actor,
          targetUid: target,
          currentlyBlocked: const [],
        ),
        isTrue,
      );
      final reports = <Map<String, Object>>[];
      await BlockReportLogic.afterNewBlockWriteReport(
        actorUid: actor,
        targetUid: target,
        persistReport: (fields) async => reports.add(fields),
      );
      expect(reports, hasLength(1));
    });

    test('payload has no PII or message body', () {
      final fields = BlockReportLogic.reportFields(
        actorUid: actor,
        targetUid: target,
      );
      expect(fields.keys.toSet(), BlockReportLogic.allowedReportKeys);
      for (final key in BlockReportLogic.forbiddenPiiKeys) {
        expect(fields.containsKey(key), isFalse, reason: key);
      }
      final blob = fields.values.map((e) => e.toString()).join(' ');
      expect(blob, isNot(contains('@')));
      expect(blob.toLowerCase(), isNot(contains('birth')));
      expect(ReportCategory.userBlocked.code, 'user_blocked');
    });

    test('report write failure keeps the block applied', () async {
      final outcome = await BlockReportLogic.afterNewBlockWriteReport(
        actorUid: actor,
        targetUid: target,
        persistReport: (_) async => throw StateError('rules or network'),
      );
      expect(outcome.applied, isTrue);
      expect(outcome.newlyBlocked, isTrue);
      expect(outcome.reportWritten, isFalse);
      expect(outcome.shouldWarnReportFailure, isTrue);
      expect(outcome.reportError, isA<StateError>());
    });

    test('payload matches Admin-consumable reports contract and rules create shape', () {
      final fields = BlockReportLogic.reportFields(
        actorUid: 'reporter',
        targetUid: 'reported',
      );
      // Same identifiers delete_my_account / Admin SDK already scan.
      expect(fields['fromUid'], 'reporter');
      expect(fields['reporterUid'], 'reporter');
      expect(fields['reportedUid'], 'reported');
      expect(fields['status'], 'open');
      expect(fields['reasonCode'], isNotEmpty);
      expect(fields.containsKey('createdAt'), isFalse);
      expect(
        File('lib/services/block_service.dart').readAsStringSync(),
        contains("'createdAt': FieldValue.serverTimestamp()"),
      );
      expect(
        File('firestore.rules').readAsStringSync(),
        contains('allow create: if signedIn();'),
      );
    });

    test('profile surfaces notify failure without unblocking', () {
      final profile =
          File('lib/pages/public_profile_page.dart').readAsStringSync();
      expect(profile, contains('shouldWarnReportFailure'));
      expect(profile, contains('block_report_notify_failed'));
      expect(profile, contains('BlockService.blockUser(userUid)'));
    });
  });
}
