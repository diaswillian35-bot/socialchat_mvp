import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';
import 'package:socialchat_mvp/services/remdy_launch_access.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  final uiRoots = [
    Directory('lib/pages'),
    Directory('lib/widgets'),
    Directory('lib/widget'),
  ];

  Iterable<File> uiDartFiles() sync* {
    for (final dir in uiRoots) {
      if (!dir.existsSync()) continue;
      yield* dir.listSync(recursive: true).whereType<File>().where(
            (f) => f.path.endsWith('.dart'),
          );
    }
  }

  group('Guideline 2.1(a) launch UI has no incomplete Coming Soon', () {
    test('reachable pages do not call showComingSoon or comingSoon copy APIs', () {
      const forbidden = [
        'showComingSoon(',
        'comingSoonMessage(',
        'comingSoonTitle(',
        "t.get('coming_soon')",
        't.get("coming_soon")',
        "t.get('coming_soon_short')",
        "t.get('country_coming_soon')",
        "t.get('country_coming_soon_title')",
        "t.get('world_coming_soon')",
      ];
      for (final file in uiDartFiles()) {
        final text = file.readAsStringSync();
        for (final needle in forbidden) {
          expect(
            text.contains(needle),
            isFalse,
            reason: '${file.path} still exposes $needle',
          );
        }
      }
    });

    test('comingSoonBadgeLabel on Home is unreachable during launch', () {
      final home = source('lib/pages/home_page.dart');
      expect(home, contains('comingSoonBadgeLabel'));
      expect(
        home,
        contains('!RemdyLaunchAccess.isFreeBrazilLaunch &&'),
      );
      expect(home, contains('isFreeBrazilLaunch'));
      expect(
        RemdyLaunchAccess.showsComingSoonOnHome(
          userHomeCountryCode: 'br',
          targetCountryCode: 'ca',
        ),
        isTrue,
      );
    });

    test('Home keeps CA, PT and Mundo visible without Coming Soon copy', () {
      final home = source('lib/pages/home_page.dart');
      expect(home, contains("code: 'CA'"));
      expect(home, contains("code: 'PT'"));
      expect(home, contains("t.get('live_now')"));
      expect(home, contains("t.get('world')"));
      expect(home, isNot(contains('world_coming_soon')));
      expect(home, contains('showUnavailable'));
      expect(home, contains('canAccessCountryContent'));
      expect(home, contains('return c.code.isNotEmpty && c.name.isNotEmpty;'));
      expect(
        RemdyLaunchAccess.canAccessCountryContent(
          userHomeCountryCode: 'br',
          targetCountryCode: 'br',
        ),
        isTrue,
      );
      expect(
        RemdyLaunchAccess.canAccessCountryContent(
          userHomeCountryCode: 'br',
          targetCountryCode: 'ca',
        ),
        isFalse,
      );
    });

    test('Premium stays hidden: no placeholder sheet on PremiumPage', () {
      final premium = source('lib/pages/premium_page.dart');
      final menu = source('lib/pages/menu_page.dart');
      final profile = source('lib/pages/profile_page.dart');
      expect(premium, isNot(contains('showComingSoon')));
      expect(premium, isNot(contains('showUnavailable')));
      expect(premium, contains('maybePop'));
      expect(menu, contains('showPremiumUi'));
      expect(profile, contains('showPremiumUi'));
      expect(RemdyLaunchAccess.showPremiumUi, isFalse);
    });

    test('About omits paragraph 9 during launch', () {
      final about = source('lib/pages/about_page.dart');
      expect(about, contains('isFreeBrazilLaunch'));
      expect(about, contains('about_remdy_paragraph_9'));
      AppTexts.loadFromMap({
        'about_remdy_paragraph_1': 'p1',
        'about_remdy_paragraph_2': 'p2',
        'about_remdy_our_idea_title': 'idea',
        'about_remdy_paragraph_3': 'p3',
        'about_remdy_paragraph_4': 'p4',
        'about_remdy_paragraph_5': 'p5',
        'about_remdy_bullet_1': 'b1',
        'about_remdy_bullet_2': 'b2',
        'about_remdy_bullet_3': 'b3',
        'about_remdy_bullet_4': 'b4',
        'about_remdy_paragraph_6': 'p6',
        'about_remdy_global_title': 'global',
        'about_remdy_paragraph_7': 'p7',
        'about_remdy_safety_title': 'safety',
        'about_remdy_paragraph_8': 'p8',
        'about_remdy_getting_started_title': 'started',
        'about_remdy_paragraph_9': 'FEATURES_ON_THE_WAY',
        'about_remdy_thanks_title': 'thanks',
        'about_remdy_paragraph_10': 'p10',
      });
      expect(RemdyLaunchAccess.isFreeBrazilLaunch, isTrue);
      // Source keeps the key for non-launch; launch branch is empty string.
      expect(about, contains("isFreeBrazilLaunch ? ''"));
    });

    test('Contact WhatsApp stays disabled and coming_soon is unused', () {
      final contact = source('lib/pages/contact_page.dart');
      expect(contact, contains('enableWhatsApp = false'));
      expect(contact, isNot(contains("t.get('coming_soon')")));
      expect(contact, contains('launch_content_unavailable'));
    });

    test('five locales keep coming-soon keys and add unavailable copy', () {
      final files = {
        'lib/l10n/en.json': 'Coming soon',
        'lib/l10n/es.json': 'Próximamente',
        'lib/l10n/fr.json': 'Bientôt',
        'lib/l10n/pt-BR.json': 'Em breve',
        'lib/l10n/pt-PT.json': null,
      };
      for (final entry in files.entries) {
        final map =
            jsonDecode(source(entry.key)) as Map<String, dynamic>;
        expect(map.containsKey('launch_content_unavailable'), isTrue);
        final unavailable = map['launch_content_unavailable'].toString();
        expect(unavailable.toLowerCase(), isNot(contains('coming soon')));
        expect(unavailable.toLowerCase(), isNot(contains('em breve')));
        expect(unavailable.toLowerCase(), isNot(contains('próximamente')));
        expect(unavailable.toLowerCase(), isNot(contains('bientôt')));
        if (entry.value != null) {
          expect(map['coming_soon_short'], entry.value);
        }
      }
      final ptPt = jsonDecode(source('lib/l10n/pt-PT.json')) as Map<String, dynamic>;
      expect(ptPt.containsKey('coming_soon_short'), isFalse);
    });

    test('unavailable helper has no future-promise copy', () {
      AppTexts.loadFromMap({
        'launch_content_unavailable': 'This content is not available.',
      });
      final msg = RemdyLaunchAccess.unavailableMessage();
      expect(msg, 'This content is not available.');
      expect(msg.toLowerCase(), isNot(contains('coming')));
      expect(msg.toLowerCase(), isNot(contains('breve')));
      expect(source('lib/services/remdy_launch_access.dart'),
          contains('showComingSoon'));
    });

    test('pubspec stays 1.0.4+37', () {
      expect(source('pubspec.yaml'), contains('version: 1.0.4+37'));
    });
  });
}
