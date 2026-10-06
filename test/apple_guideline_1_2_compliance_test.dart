import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/auth_terms_gate.dart';
import 'package:socialchat_mvp/services/objectionable_content_filter.dart';
import 'package:socialchat_mvp/services/report_category.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  Map<String, dynamic> localeJson(String code) =>
      jsonDecode(source('lib/l10n/$code.json')) as Map<String, dynamic>;

  group('Apple 1.2 — Terms acceptance before auth', () {
    test('gate blocks when terms not accepted', () {
      expect(AuthTermsGate.canAuthenticate(termsAccepted: false), isFalse);
      expect(
        AuthTermsGate.rejectReason(termsAccepted: false),
        AuthTermsGate.requiredKey,
      );
    });

    test('gate allows when terms accepted', () {
      expect(AuthTermsGate.canAuthenticate(termsAccepted: true), isTrue);
      expect(AuthTermsGate.rejectReason(termsAccepted: true), isNull);
    });

    test('LoginPage requires AuthTermsGate for email/Google/Apple/Facebook', () {
      final login = source('lib/pages/login_page.dart');
      expect(login, contains("import '../services/auth_terms_gate.dart';"));
      expect(login, contains('AuthTermsGate.rejectReason'));
      for (final method in [
        '_submitEmailPass',
        '_loginGoogle',
        '_loginApple',
        '_loginFacebook',
      ]) {
        expect(login, contains(method), reason: method);
      }
      // Terms checkbox must be available for login mode (not signup-only).
      final acceptIdx = login.indexOf("t.get('age_accept_terms')");
      final signupClose = login.indexOf("age_18_plus_notice");
      expect(acceptIdx, greaterThan(signupClose));
      expect(login.contains('_loginGoogle() async'), isTrue);
      expect(login.contains('_loginApple() async'), isTrue);
      expect(login.contains('deixei o botão'), isFalse);
      expect(login, contains('_appleSignInService.signIn()'));
      expect(
        login.indexOf('AuthTermsGate.rejectReason', login.indexOf('_loginGoogle')),
        greaterThan(login.indexOf('_loginGoogle')),
      );
      expect(
        login.indexOf('AuthTermsGate.rejectReason', login.indexOf('_loginApple')),
        greaterThan(login.indexOf('_loginApple')),
      );
      expect(
        login.indexOf(
          'AuthTermsGate.rejectReason',
          login.indexOf('_loginFacebook'),
        ),
        greaterThan(login.indexOf('_loginFacebook')),
      );
      expect(
        login.indexOf(
          'AuthTermsGate.rejectReason',
          login.indexOf('_submitEmailPass'),
        ),
        greaterThan(login.indexOf('_submitEmailPass')),
      );
    });
  });

  group('Apple 1.2 — Zero tolerance in Terms (all locales)', () {
    const locales = ['en', 'pt-BR', 'pt-PT', 'es', 'fr'];

    test('every locale has explicit zero-tolerance strings', () {
      for (final code in locales) {
        final json = localeJson(code);
        final title = (json['terms_zero_tolerance_title'] ?? '').toString();
        final body = (json['terms_zero_tolerance_body'] ?? '').toString();
        expect(title, isNotEmpty, reason: code);
        expect(body, isNotEmpty, reason: code);
        final blob = '$title $body'.toLowerCase();
        final hasZero = blob.contains('zero') ||
            blob.contains('tolerância zero') ||
            blob.contains('tolerancia cero') ||
            blob.contains('tolérance zéro');
        expect(hasZero, isTrue, reason: '$code missing zero-tolerance wording');
        expect(
          body.toLowerCase().contains('abus'),
          isTrue,
          reason: '$code should mention abusive users',
        );
      }
    });

    test('TermsPage renders zero-tolerance keys', () {
      final terms = source('lib/pages/terms_page.dart');
      expect(terms, contains("terms_zero_tolerance_title"));
      expect(terms, contains("terms_zero_tolerance_body"));
    });
  });

  group('Apple 1.2 — Objectionable content filter', () {
    test('allows ordinary friendly messages', () {
      expect(ObjectionableContentFilter.allows('Oi, tudo bem?'), isTrue);
      expect(ObjectionableContentFilter.allows('Hello from Toronto'), isTrue);
      expect(ObjectionableContentFilter.rejectReason('Bom dia'), isNull);
    });

    test('blocks clearly objectionable phrases', () {
      expect(
        ObjectionableContentFilter.rejectReason('child porn link'),
        ObjectionableContentFilter.blockedErrorKey,
      );
      expect(
        ObjectionableContentFilter.rejectReason('vou te matar agora'),
        ObjectionableContentFilter.blockedErrorKey,
      );
      expect(
        ObjectionableContentFilter.allows('pornografia infantil'),
        isFalse,
      );
    });

    test('blocks exact "vou matar" and locale equivalents, not food/time idioms',
        () {
      const threats = [
        'vou matar',
        'VOU MATAR',
        'vou matar.',
        'eu vou matar',
        'vou matar voce',
        'vou te matar',
        "i will kill",
        'i will kill you',
        "i'm going to kill you",
        'gonna kill you',
        'voy a matar',
        'te voy a matar',
        'je vais tuer',
        'je vais te tuer',
      ];
      for (final t in threats) {
        expect(
          ObjectionableContentFilter.allows(t),
          isFalse,
          reason: t,
        );
      }
      const idioms = [
        'vou matar a fome',
        'matar saudade',
        'kill time at the airport',
        'just kill it',
        'skill issue',
        'the killer app',
        'voy a matar el hambre',
        'je vais tuer le temps',
        'Oi, tudo bem?',
      ];
      for (final t in idioms) {
        expect(
          ObjectionableContentFilter.allows(t),
          isTrue,
          reason: t,
        );
      }
      final src =
          File('lib/services/objectionable_content_filter.dart').readAsStringSync();
      expect(src.contains("'vou matar'"), isFalse);
      expect(src, contains('vou(?:\\s+'));
    });

    test('wired into DM/group send paths', () {
      final outgoing = source('lib/services/outgoing_text_message_service.dart');
      final chat = source('lib/pages/chat_page.dart');
      final group = source('lib/pages/group_chat_page.dart');
      for (final file in [outgoing, chat, group]) {
        expect(file, contains('ObjectionableContentFilter.rejectReason'));
      }
      expect(localeJson('en')['content_filter_blocked'], isNotEmpty);
    });

    test('server filter is enforced on DM send, group create, and comments', () {
      final core = source('functions/send_dm_message_core.js');
      final index = source('functions/index.js');
      final comments = source('functions/event_interactions_helpers.js');
      expect(core, contains('isObjectionableText(text)'));
      expect(core, contains('content_filter_blocked'));
      expect(index, contains('deletedReason: "objectionable"'));
      expect(index, contains('isObjectionableText(msg.text)'));
      expect(comments, contains('isObjectionableText(text)'));
      expect(
        source('functions/objectionable_content_filter.js'),
        contains('function isObjectionableText'),
      );
    });
  });

  group('Apple 1.2 — Report and block preserved', () {
    test('BlockService still exposes block/unblock', () {
      final block = source('lib/services/block_service.dart');
      expect(block, contains('static Future<BlockUserOutcome> blockUser'));
      expect(block, contains('static Future<void> unblockUser'));
      expect(block, contains('isEitherBlocked'));
      expect(block, contains("collection('reports')"));
      expect(block, contains('_tryMarkBlocked'));
      final unblock = block.split('static Future<void> unblockUser').last;
      expect(unblock.split('isBlockedStream').first, isNot(contains('reports')));
    });

    test('profile exposes Reportar and Bloquear', () {
      final profile = source('lib/pages/public_profile_page.dart');
      expect(profile, contains('_openReportSheet'));
      expect(profile, contains('_toggleBlock'));
      expect(profile, contains('BlockService.blockUser'));
      expect(profile, contains("collection('reports')"));
    });

    test('private and group chats keep report sheets', () {
      final chat = source('lib/pages/chat_page.dart');
      final group = source('lib/pages/group_chat_page.dart');
      expect(chat, contains('_openChatReportSheet'));
      expect(chat, contains('_openPrivateMessageReportSheet'));
      expect(group, contains('_openGroupMessageReportSheet'));
      expect(group, contains('_openGroupReportSheet'));
    });

    test('report categories remain intact', () {
      expect(ReportCategory.inappropriate.code, isNotEmpty);
      expect(ReportCategory.harassment.code, isNotEmpty);
      expect(ReportCategory.childSafety.code, 'child_sexual_exploitation_or_abuse');
    });

    test('reports rules stay create-only for signed-in users', () {
      final rules = source('firestore.rules');
      final match = RegExp(
        r'match /reports/\{reportId\} \{([\s\S]*?)\n\s*\}',
      ).firstMatch(rules);
      expect(match, isNotNull);
      final block = match!.group(1)!;
      expect(block, contains('allow read: if false;'));
      expect(block, contains('allow create: if signedIn();'));
      expect(block, contains('allow update, delete: if false;'));
    });
  });

  group('Apple 1.2 — versioning', () {
    test('ships 1.0.4+34 after 1.0.4 (33) was rejected for UGC and incomplete UI', () {
      expect(source('pubspec.yaml'), contains('version: 1.0.4+34'));
      expect(source('pubspec.yaml'), isNot(contains('version: 1.0.4+33')));
      expect(source('pubspec.yaml'), isNot(contains('version: 1.0.4+32')));
      expect(source('pubspec.yaml'), isNot(contains('version: 1.0.4+31')));
    });
  });
}
