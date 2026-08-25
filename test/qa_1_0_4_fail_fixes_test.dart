import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/people_browse_grouping.dart';
import 'package:socialchat_mvp/utils/user_search_normalize.dart';

void main() {
  // DM/group delivery covered by test/message_delivery_status_test.dart

  group('people browse search normalize', () {
    test('accent-insensitive city match', () {
      final q = UserSearchNormalize.normalize('sao paulo');
      final city = UserSearchNormalize.normalize('São Paulo');
      expect(city.contains(q), isTrue);
    });

    test('grouping still works under threshold', () {
      final profiles = List.generate(
        5,
        (i) => PeopleBrowseProfile(
          uid: 'u$i',
          name: 'User $i',
          city: 'Curitiba',
          state: 'PR',
        ),
      );
      final groups = PeopleBrowseGrouping.group(
        profiles: profiles,
        citySectionMinProfiles: 30,
        otherCitiesLabel: 'Outras',
      );
      expect(groups.length, 1);
      expect(groups.first.stateLabel, 'Paraná');
      expect(groups.first.sections.single.isOtherCitiesBucket, isTrue);
    });
  });

  group('wiring', () {
    test('flag route opens CountryPeoplePage', () {
      final home = File('lib/pages/home_page.dart').readAsStringSync();
      expect(home.contains('CountryPeoplePage'), isTrue);
      expect(home.contains('LanguageUsersPage'), isFalse);
    });

    test('DM status not latest-only; composer ListenableBuilder', () {
      final chat = File('lib/pages/chat_page.dart').readAsStringSync();
      expect(chat.contains('MessageDeliveryStatus.dmStage'), isTrue);
      expect(chat.contains('latestOwnMessageId'), isFalse);
      expect(chat.contains('ListenableBuilder'), isTrue);
      expect(chat.contains('_peerLastReadAt'), isTrue);
      expect(chat.contains('_legacyPeerCaughtUpAt'), isTrue);
      expect(chat.contains('_effectivePeerReadAt'), isTrue);
    });

    test('group status uses reads watermark for all own msgs', () {
      final g = File('lib/pages/group_chat_page.dart').readAsStringSync();
      expect(g.contains('MessageDeliveryStatus.groupStage'), isTrue);
      expect(g.contains('_scheduleMarkGroupAsRead'), isTrue);
      expect(g.contains('latestOwnMessageId'), isFalse);
    });

    test('Share Extension ImageIO + confirm-before-send', () {
      final swift =
          File('ios/ShareExtension/ShareViewController.swift').readAsStringSync();
      expect(swift.contains('downsampledJPEG'), isTrue);
      expect(swift.contains('applyCachedDestinations'), isTrue);
      expect(swift.contains('payloadReady'), isTrue);
      expect(swift.contains('maxImages = 3'), isTrue);
      expect(swift.contains('selectedDestination'), isTrue);
      expect(swift.contains('sendTapped'), isTrue);
    });
  });
}
