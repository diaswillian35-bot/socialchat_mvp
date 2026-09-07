import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/international_chat_service.dart';
import 'package:socialchat_mvp/services/purchase_service.dart';
import 'package:socialchat_mvp/services/remdy_launch_access.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  group('RemdyLaunchAccess free BR+CA launch (iOS)', () {
    test('central flag exists and purchases are gated by launch mode', () {
      final dart = source('lib/services/remdy_launch_access.dart');
      expect(dart, contains('freeBrazilLaunchEnabled'));
      expect(dart, contains('freeCountryCodes'));
      expect(dart, contains("'br'"));
      expect(dart, contains("'ca'"));
      expect(dart, contains('purchasesEnabled'));
      expect(dart, contains('showPremiumUi'));
      expect(dart, contains('canAccessCountryContent'));
      expect(dart, contains('comingSoonTitle'));
    });

    test('Brazil and Canada are open; PT and world are closed', () {
      expect(RemdyLaunchAccess.isCountryOpen('br'), isTrue);
      expect(RemdyLaunchAccess.isCountryOpen('BR'), isTrue);
      expect(RemdyLaunchAccess.isCountryOpen('ca'), isTrue);
      expect(RemdyLaunchAccess.isCountryOpen('CA'), isTrue);
      expect(RemdyLaunchAccess.isCountryOpen('pt'), isFalse);
      expect(RemdyLaunchAccess.isCountryOpen('us'), isFalse);
      expect(RemdyLaunchAccess.isCountryOpen('world'), isFalse);
      expect(RemdyLaunchAccess.isWorldOpen(), isFalse);
    });

    test('same-country chat allowed; BR↔CA blocked', () {
      expect(
        RemdyLaunchAccess.canChatBetweenCountries(
          senderCountryCode: 'br',
          recipientCountryCode: 'br',
          premiumActive: false,
        ),
        isTrue,
      );
      expect(
        RemdyLaunchAccess.canChatBetweenCountries(
          senderCountryCode: 'ca',
          recipientCountryCode: 'ca',
          premiumActive: false,
        ),
        isTrue,
      );
      expect(
        RemdyLaunchAccess.canChatBetweenCountries(
          senderCountryCode: 'br',
          recipientCountryCode: 'ca',
          premiumActive: false,
        ),
        isFalse,
      );
      expect(
        RemdyLaunchAccess.canChatBetweenCountries(
          senderCountryCode: 'br',
          recipientCountryCode: 'ca',
          premiumActive: true,
        ),
        isFalse,
      );
      expect(
        RemdyLaunchAccess.canAccessCountryContent(
          userHomeCountryCode: 'br',
          targetCountryCode: 'ca',
        ),
        isFalse,
      );
    });

    test('InternationalChatService allows BR↔BR and CA↔CA only', () {
      final br = {'homeCountryCode': 'br'};
      final ca = {'homeCountryCode': 'ca'};
      expect(
        InternationalChatService.canSendMessage(
          senderData: br,
          recipientData: br,
        ),
        isTrue,
      );
      expect(
        InternationalChatService.canSendMessage(
          senderData: ca,
          recipientData: ca,
        ),
        isTrue,
      );
      expect(
        InternationalChatService.canSendMessage(
          senderData: br,
          recipientData: ca,
        ),
        isFalse,
      );
    });

    test('PurchaseService does not configure RevenueCat in launch mode', () {
      expect(RemdyLaunchAccess.purchasesEnabled, isFalse);
      expect(
        PurchaseService.evaluateKeyAvailability(),
        PurchaseAvailability.notConfigured,
      );
      final purchase = source('lib/services/purchase_service.dart');
      expect(purchase, contains('RemdyLaunchAccess.purchasesEnabled'));
    });

    test('Premium UI entry points are gated in source', () {
      final home = source('lib/pages/home_page.dart');
      final menu = source('lib/pages/menu_page.dart');
      final profile = source('lib/pages/profile_page.dart');
      final dialog = source('lib/widgets/international_premium_dialog.dart');
      final premium = source('lib/pages/premium_page.dart');

      expect(home, contains('showsComingSoonOnHome'));
      expect(home, contains('canAccessCountryContent'));
      expect(home, contains('comingSoonBadgeLabel'));
      expect(home, isNot(contains('isCanada')));
      expect(menu, contains('RemdyLaunchAccess.showPremiumUi'));
      expect(profile, contains('RemdyLaunchAccess.showPremiumUi'));
      expect(dialog, contains('RemdyLaunchAccess.isFreeBrazilLaunch'));
      expect(dialog, contains('showComingSoon'));
      expect(premium, contains('RemdyLaunchAccess.showPremiumUi'));
    });

    test('Home Em breve badge depends on profile home country BR vs CA', () {
      // Perfil BR: Brasil aberto; Canadá/PT/mundo Em breve.
      expect(
        RemdyLaunchAccess.showsComingSoonOnHome(
          userHomeCountryCode: 'br',
          targetCountryCode: 'br',
        ),
        isFalse,
      );
      expect(
        RemdyLaunchAccess.showsComingSoonOnHome(
          userHomeCountryCode: 'br',
          targetCountryCode: 'ca',
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

      // Perfil CA: Canadá aberto; Brasil/PT/mundo Em breve.
      expect(
        RemdyLaunchAccess.showsComingSoonOnHome(
          userHomeCountryCode: 'ca',
          targetCountryCode: 'ca',
        ),
        isFalse,
      );
      expect(
        RemdyLaunchAccess.showsComingSoonOnHome(
          userHomeCountryCode: 'ca',
          targetCountryCode: 'br',
        ),
        isTrue,
      );
      expect(
        RemdyLaunchAccess.canAccessCountryContent(
          userHomeCountryCode: 'ca',
          targetCountryCode: 'br',
        ),
        isFalse,
      );

      for (final home in ['br', 'ca']) {
        expect(
          RemdyLaunchAccess.showsComingSoonOnHome(
            userHomeCountryCode: home,
            targetCountryCode: 'pt',
          ),
          isTrue,
        );
        expect(
          RemdyLaunchAccess.showsComingSoonOnHome(
            userHomeCountryCode: home,
            targetCountryCode: 'world',
          ),
          isTrue,
        );
      }
    });

    test('l10n has coming soon keys in pt-BR and en', () {
      final pt = source('lib/l10n/pt-BR.json');
      final en = source('lib/l10n/en.json');
      expect(pt, contains('"coming_soon_short": "Em breve"'));
      expect(pt, contains('"country_coming_soon"'));
      expect(en, contains('"coming_soon_short"'));
      expect(en, contains('"country_coming_soon"'));
    });

    test('pubspec is 1.0.4+29', () {
      expect(source('pubspec.yaml'), contains('version: 1.0.4+29'));
    });
  });
}
