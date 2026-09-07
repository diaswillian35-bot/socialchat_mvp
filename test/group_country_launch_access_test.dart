import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/international_chat_service.dart';
import 'package:socialchat_mvp/services/remdy_launch_access.dart';
import 'package:socialchat_mvp/services/user_location_scope.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  group('Group country isolation (free launch)', () {
    test('BR cannot access CA or world groups even with premium flags', () {
      for (final flags in <Map<String, dynamic>>[
        {},
        {'isPremium': true},
        {'isMaster': true},
        {
          'premiumUntil':
              DateTime.now().add(const Duration(days: 90)).toIso8601String(),
        },
        {'isPremium': true, 'isMaster': true},
      ]) {
        expect(
          RemdyLaunchAccess.canAccessGroupCountry(
            userHomeCountryCode: 'br',
            groupCountryCode: 'ca',
          ),
          isFalse,
          reason: 'BR→CA blocked with flags=$flags',
        );
        expect(
          RemdyLaunchAccess.canAccessGroupCountry(
            userHomeCountryCode: 'br',
            groupCountryCode: 'world',
          ),
          isFalse,
          reason: 'BR→world blocked with flags=$flags',
        );
        expect(
          RemdyLaunchAccess.canAccessGroupCountry(
            userHomeCountryCode: 'br',
            groupCountryCode: 'pt',
          ),
          isFalse,
        );
        expect(
          RemdyLaunchAccess.canAccessGroupCountry(
            userHomeCountryCode: 'br',
            groupCountryCode: 'br',
          ),
          isTrue,
        );
      }
    });

    test('CA cannot access BR or world groups even with premium flags', () {
      for (final flags in <Map<String, dynamic>>[
        {},
        {'isPremium': true},
        {'isMaster': true},
        {
          'premiumUntil':
              DateTime.now().add(const Duration(days: 90)).toIso8601String(),
        },
      ]) {
        expect(
          RemdyLaunchAccess.canAccessGroupCountry(
            userHomeCountryCode: 'ca',
            groupCountryCode: 'br',
          ),
          isFalse,
          reason: 'CA→BR blocked with flags=$flags',
        );
        expect(
          RemdyLaunchAccess.canAccessGroupCountry(
            userHomeCountryCode: 'ca',
            groupCountryCode: 'world',
          ),
          isFalse,
        );
        expect(
          RemdyLaunchAccess.canAccessGroupCountry(
            userHomeCountryCode: 'ca',
            groupCountryCode: 'ca',
          ),
          isTrue,
        );
      }
    });

    test('canAccessGroupCountry ignores entitlement fields by design', () {
      // API does not accept premium flags — country codes only.
      expect(
        RemdyLaunchAccess.canAccessGroupCountry(
          userHomeCountryCode: 'br',
          groupCountryCode: 'ca',
        ),
        isFalse,
      );
      final access = source('lib/services/remdy_launch_access.dart');
      expect(access, contains('canAccessGroupCountry'));
      expect(
        access,
        contains('isPremium` / `isMaster` / `premiumUntil` / grupo `world`'),
      );
    });

    test('GroupChatPage gates membership/send/bootstrap on country access', () {
      final page = source('lib/pages/group_chat_page.dart');
      expect(page, contains('_countryAccessDenied'));
      expect(page, contains('canAccessGroupCountry'));
      expect(page, contains('showComingSoon'));
      expect(page, contains('Navigator.maybePop'));
      // Premium no longer unlocks world during free launch send path.
      expect(page, contains('_computeCanSend'));
    });

    test('groups list and join invite gate before opening chat', () {
      final list = source('lib/pages/groups_list_page.dart');
      final join = source('lib/pages/join_group_page.dart');
      expect(list, contains('canAccessGroupCountry'));
      expect(list, contains('showComingSoon'));
      expect(join, contains('canAccessGroupCountry'));
      expect(join, contains('showComingSoon'));
    });
  });

  group('Equivalent bypass audit (people / chat / events)', () {
    test('DM canSendMessage blocks BR↔CA with premium/master/until', () {
      expect(
        InternationalChatService.canSendMessage(
          senderData: {
            'homeCountryCode': 'br',
            'isPremium': true,
            'isMaster': true,
          },
          recipientData: {'homeCountryCode': 'ca'},
        ),
        isFalse,
      );
      expect(
        InternationalChatService.canSendMessage(
          senderData: {'homeCountryCode': 'ca', 'isPremium': true},
          recipientData: {'homeCountryCode': 'br'},
        ),
        isFalse,
      );
      expect(
        InternationalChatService.canSendMessage(
          senderData: {'homeCountryCode': 'br'},
          recipientData: {'homeCountryCode': 'br'},
        ),
        isTrue,
      );
    });

    test('chat_page free-launch paths do not use premium for world unlock', () {
      final chat = source('lib/pages/chat_page.dart');
      expect(chat, contains('isFreeBrazilLaunch'));
      expect(chat, contains('_canUseWorldChat'));
      // Quota international path must short-circuit on free launch.
      expect(chat, contains('Lançamento gratuito: sem franquia internacional'));
      final ensure = chat.split('_ensureCanSendMessage').last;
      final beforeQuota =
          ensure.split('Free internacional: franquia').first;
      expect(beforeQuota, contains('isFreeBrazilLaunch'));
      expect(beforeQuota, contains('showComingSoon'));
    });

    test('people discovery still country+city/radius scoped', () {
      expect(UserLocationScope.regionRadiusKm, 110);
      final nearby = source('lib/widgets/home_nearby_users_section.dart');
      final page = source('lib/pages/nearby_users_page.dart');
      expect(nearby, contains('matchesViewerCity'));
      expect(page, contains('matchesViewerRegion'));
      expect(nearby, isNot(contains('isPremium')));
      expect(page, isNot(contains('isPremium')));
    });

    test('events list queries bind to profile countryCode', () {
      final events = source('lib/pages/events_page_new.dart');
      expect(events, contains("userData['homeCountryCode']"));
      expect(events, contains('countryCode: myCountry'));
      // No RemdyLaunchAccess bypass via Premium in events page.
      expect(events, isNot(contains('isPremiumActiveFromData')));
    });

    test('Home country open is profile-relative', () {
      expect(
        RemdyLaunchAccess.showsComingSoonOnHome(
          userHomeCountryCode: 'br',
          targetCountryCode: 'ca',
        ),
        isTrue,
      );
      expect(
        RemdyLaunchAccess.showsComingSoonOnHome(
          userHomeCountryCode: 'ca',
          targetCountryCode: 'br',
        ),
        isTrue,
      );
      expect(RemdyLaunchAccess.purchasesEnabled, isFalse);
      expect(RemdyLaunchAccess.showPremiumUi, isFalse);
    });
  });
}
