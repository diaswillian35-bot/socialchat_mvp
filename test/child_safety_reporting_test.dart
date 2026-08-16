import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/report_category.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test('child safety reason has canonical code and critical priority', () {
    expect(
      ReportCategory.childSafety.code,
      'child_sexual_exploitation_or_abuse',
    );
    expect(ReportCategory.childSafety.priority, 'critical');
    expect(reportClassification(ReportCategory.childSafety), {
      'reasonCode': 'child_sexual_exploitation_or_abuse',
      'priority': 'critical',
      'requiresChildSafetyReview': true,
    });
  });

  test('all supported locales contain the same canonical child-safety keys',
      () {
    const expected = <String, String>{
      'pt-BR': 'Exploração ou abuso sexual infantil',
      'pt-PT': 'Exploração ou abuso sexual infantil',
      'en': 'Child sexual exploitation or abuse',
      'es': 'Explotación o abuso sexual infantil',
      'fr': 'Exploitation ou abus sexuel d’enfants',
    };

    for (final entry in expected.entries) {
      final json = jsonDecode(source('lib/l10n/${entry.key}.json'))
          as Map<String, dynamic>;
      expect(
        json['report_reason_child_sexual_exploitation'],
        entry.value,
        reason: entry.key,
      );
      expect(
        (json['report_child_safety_authorities_notice'] as String),
        isNotEmpty,
        reason: entry.key,
      );
    }
  });

  test('profile, private chat/message, group/message expose child safety', () {
    final profile = source('lib/pages/public_profile_page.dart');
    final chat = source('lib/pages/chat_page.dart');
    final group = source('lib/pages/group_chat_page.dart');

    expect(profile, contains('ReportCategory.childSafety'));
    expect(chat, contains('_openPrivateMessageReportSheet'));
    expect(chat, contains('ReportCategory.childSafety'));
    expect(chat,
        contains("'contextType': messageId == null ? 'dm' : 'dm_message'"));
    expect(group, contains('_openGroupMessageReportSheet'));
    expect(group, contains('ReportCategory.childSafety'));
    expect(group, contains("'contextType': 'group'"));

    // No event/content report writer currently exists; the requirement applies
    // when such a UI is introduced.
    for (final path in Directory('lib/pages')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.contains('event'))) {
      expect(source(path.path), isNot(contains("collection('reports')")));
    }
  });

  test('report payloads retain references and never copy message media', () {
    for (final path in <String>[
      'lib/pages/public_profile_page.dart',
      'lib/pages/chat_page.dart',
      'lib/pages/group_chat_page.dart',
    ]) {
      final file = source(path);
      expect(file, contains('reportClassification(category)'), reason: path);
    }

    final helper = source('lib/services/report_category.dart');
    expect(helper, isNot(contains("'imageUrl'")));
    expect(helper, isNot(contains("'audioUrl'")));
    expect(helper, isNot(contains("'messageText'")));
  });

  test('reports are invisible and immutable to every client role', () {
    final rules = source('firestore.rules');
    final match = RegExp(
      r'match /reports/\{reportId\} \{([\s\S]*?)\n\s*\}',
    ).firstMatch(rules);

    expect(match, isNotNull);
    final block = match!.group(1)!;
    expect(block, contains('allow read: if false;'));
    expect(block, contains('allow update, delete: if false;'));
    expect(block, isNot(contains('premium')));
    expect(block, isNot(contains('admin')));
  });

  test('SOP states manual lawful escalation without claiming automation', () {
    final sop = source('docs/CHILD_SAFETY_RESPONSE_SOP.md');
    expect(sop, contains('contact@remdy.app'));
    expect(sop, contains('critical priority'));
    expect(sop, contains('NCMEC'));
    expect(sop, contains('does not currently claim an automated integration'));
    expect(sop, contains('Do not duplicate suspected illegal media'));
  });
}
