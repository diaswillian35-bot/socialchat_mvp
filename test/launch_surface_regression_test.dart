import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';
import 'package:socialchat_mvp/pages/privacy_page.dart';
import 'package:socialchat_mvp/pages/terms_page.dart';
import 'package:socialchat_mvp/services/premium_access_service.dart';
import 'package:socialchat_mvp/services/remdy_launch_access.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  Map<String, dynamic> locale(String code) =>
      jsonDecode(source('lib/l10n/$code.json')) as Map<String, dynamic>;

  const locales = ['en', 'pt-BR', 'pt-PT', 'es', 'fr'];

  const visibleFaqAnswers = [
    'faq_what_is_remdy_a',
    'faq_countries_available_a',
    'faq_delete_account_a',
    'faq_message_anyone_a',
    'faq_world_option_a',
    'faq_cant_join_group_a',
    'faq_block_person_a',
    'faq_report_person_a',
  ];

  const bannedInLaunchCopy = [
    'premium',
    'subscribe',
    'subscription',
    'assinatura',
    'subscri',
    'abonnement',
    'coming soon',
    'em breve',
    'próximamente',
    'proximamente',
    'bientôt',
    'bientot',
  ];

  group('iOS launch hides Premium surfaces', () {
    test('purchase, invites, Remi FAQ and subscription copy stay off', () {
      expect(RemdyLaunchAccess.isFreeBrazilLaunch, isTrue);
      expect(RemdyLaunchAccess.showPremiumUi, isFalse);
      expect(RemdyLaunchAccess.showInviteRewards, isFalse);
      expect(RemdyLaunchAccess.showSubscriptionManagementCopy, isFalse);
      expect(RemdyLaunchAccess.showRemiUi, isFalse);
      expect(RemdyLaunchAccess.faqSectionVisible('faq_cat_premium'), isFalse);
      expect(RemdyLaunchAccess.faqSectionVisible('faq_cat_invites'), isFalse);
      expect(RemdyLaunchAccess.faqSectionVisible('faq_cat_remi'), isFalse);
      expect(RemdyLaunchAccess.faqSectionVisible('faq_cat_account'), isTrue);
      expect(RemdyLaunchAccess.termsSectionVisible('premium'), isFalse);
      expect(RemdyLaunchAccess.termsSectionVisible('remi'), isFalse);
      expect(RemdyLaunchAccess.termsSectionVisible('deletion'), isTrue);
    });

    test('master, paid and expired Premium do not paint a badge', () {
      final future = DateTime.now().toUtc().add(const Duration(days: 3));
      final past = DateTime.now().toUtc().subtract(const Duration(days: 3));
      final cases = <Map<String, dynamic>>[
        {'isMaster': true, 'isPremium': false},
        {'isMaster': false, 'isPremium': true},
        {
          'isMaster': false,
          'isPremium': false,
          'premiumUntil': future.toIso8601String(),
        },
        {
          'isMaster': false,
          'isPremium': false,
          'premiumUntil': past.toIso8601String(),
        },
        {'isMaster': false, 'isPremium': false},
      ];
      for (final data in cases) {
        final active = PremiumAccessService.isPremiumActiveFromData(data);
        expect(
          RemdyLaunchAccess.showsPremiumBadge(premiumActive: active),
          isFalse,
          reason: data.toString(),
        );
      }
      expect(
        PremiumAccessService.isPremiumActiveFromData({'isMaster': true}),
        isTrue,
      );
    });

    test('new session offers only BR and CA; locked accounts stay', () {
      expect(RemdyLaunchAccess.isSignupCountryOffered('br'), isTrue);
      expect(RemdyLaunchAccess.isSignupCountryOffered('ca'), isTrue);
      expect(RemdyLaunchAccess.isSignupCountryOffered('pt'), isFalse);
      expect(RemdyLaunchAccess.isSignupCountryOffered('us'), isFalse);
      expect(
        RemdyLaunchAccess.acceptsHomeCountry(
          code: 'ca',
          alreadyLocked: false,
          lockedCode: '',
        ),
        isTrue,
      );
      expect(
        RemdyLaunchAccess.acceptsHomeCountry(
          code: 'us',
          alreadyLocked: false,
          lockedCode: '',
        ),
        isFalse,
      );
      expect(
        RemdyLaunchAccess.acceptsHomeCountry(
          code: 'us',
          alreadyLocked: true,
          lockedCode: 'us',
        ),
        isTrue,
      );
      expect(
        RemdyLaunchAccess.acceptsHomeCountry(
          code: 'ca',
          alreadyLocked: true,
          lockedCode: 'br',
        ),
        isFalse,
      );
      expect(
        RemdyLaunchAccess.canAccessCountryContent(
          userHomeCountryCode: 'ca',
          targetCountryCode: 'ca',
        ),
        isTrue,
      );
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

    test('reachable FAQ answers and terms omit Premium and coming soon', () {
      for (final code in locales) {
        final map = locale(code);
        for (final key in visibleFaqAnswers) {
          final shownKey = RemdyLaunchAccess.faqAnswerKey(key);
          final text = (map[shownKey] ?? '').toString().toLowerCase();
          expect(text, isNotEmpty, reason: '$code $shownKey');
          for (final banned in bannedInLaunchCopy) {
            expect(text.contains(banned), isFalse,
                reason: '$code $shownKey $banned');
          }
        }
        AppTexts.loadFromMap(map);
        final terms = TermsPage().debugTerms.toLowerCase();
        expect(terms, isNot(contains('premium')));
        expect(terms, isNot(contains('subscription')));
        expect(terms, isNot(contains('assinatura')));
        expect(terms, isNot(contains('subscri')));
        expect(terms, isNot(contains('abonnement')));
        expect(terms, isNot(contains('remi')));
        expect(
          terms,
          anyOf(
            contains('delet'),
            contains('exclu'),
            contains('elimin'),
            contains('supprim'),
          ),
        );
        final privacy = PrivacyPage().debugPrivacy.toLowerCase();
        for (final banned in [
          'premium',
          'subscription',
          'purchase',
          'assinatura',
          'compra',
          'suscrip',
          'achat',
          'abonnement',
          'revenuecat',
        ]) {
          expect(privacy.contains(banned), isFalse, reason: '$code $banned');
        }
        expect(privacy.contains('remi'), isFalse, reason: '$code remi');
        expect(
          privacy,
          anyOf(contains('18'), contains('crian'), contains('enfant'), contains('niñ'), contains('teen')),
        );
        expect(
          privacy,
          anyOf(
            contains('reten'),
            contains('conserv'),
            contains('keep'),
          ),
        );
        expect(
          privacy,
          anyOf(
            contains('delet'),
            contains('exclu'),
            contains('elimin'),
            contains('supprim'),
            contains('direito'),
            contains('right'),
            contains('droit'),
          ),
        );
      }
    });

    test('source gates menu, chat, profile, deletion, invites and country', () {
      final menu = source('lib/pages/menu_page.dart');
      final chat = source('lib/pages/chat_page.dart');
      final profile = source('lib/pages/profile_page.dart');
      final delete = source('lib/pages/delete_account_page.dart');
      final invite = source('lib/pages/invite_page.dart');
      final service = source('lib/services/invite_premium_service.dart');
      final main = source('lib/main.dart');
      final auth = source('lib/pages/auth_gate.dart');
      final edit = source('lib/pages/edit_profile_page.dart');
      final faq = source('lib/pages/faq_page.dart');
      final delegate = source('ios/Runner/AppDelegate.swift');
      final scene = source('ios/Runner/SceneDelegate.swift');

      expect(menu, contains('showsPremiumBadge'));
      expect(menu, contains('showInviteRewards'));
      expect(chat, contains('showsPremiumBadge'));
      expect(profile, contains('showPremiumUi'));
      expect(delete, contains('showSubscriptionManagementCopy'));
      expect(delete, contains('DeleteAccountPage'));
      expect(invite, contains('showInviteRewards'));
      expect(
          service,
          contains(
              'if (!RemdyLaunchAccess.showInviteRewards) return _blocked'));
      expect(
          main, contains('if (!RemdyLaunchAccess.showInviteRewards) return'));
      expect(auth, contains("prefs.remove('pending_invite_ref')"));
      expect(edit, contains('isSignupCountryOffered'));
      expect(edit, contains('acceptsHomeCountry'));
      expect(faq, contains('faqSectionVisible'));
      expect(faq, contains('faqAnswerKey'));
      expect(delegate,
          contains('didRegisterForRemoteNotificationsWithDeviceToken'));
      expect(delegate, contains('registerForRemoteNotifications'));
      expect(scene, contains('sceneDidBecomeActive'));
      expect(scene, contains('registerIfReady'));
      expect(source('pubspec.yaml'), contains('version: 1.0.4+37'));
    });

    test('safety surfaces stay reachable', () {
      final profile = source('lib/pages/public_profile_page.dart');
      final chat = source('lib/pages/chat_page.dart');
      final menu = source('lib/pages/menu_page.dart');
      expect(profile, contains('BlockService.blockUser'));
      expect(profile, contains('_openReportSheet'));
      expect(chat, contains('_openChatReportSheet'));
      expect(menu, contains('DeleteAccountPage'));
      expect(source('lib/pages/terms_page.dart'),
          contains('terms_zero_tolerance_title'));
    });
  });
}
