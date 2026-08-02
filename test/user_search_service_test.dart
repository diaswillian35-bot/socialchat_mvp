import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/international_chat_service.dart';
import 'package:socialchat_mvp/services/user_search_service.dart';
import 'package:socialchat_mvp/utils/user_search_normalize.dart';

void main() {
  group('UserSearchNormalize', () {
    test('case and accents', () {
      expect(UserSearchNormalize.normalize('MaRiA'), 'maria');
      expect(UserSearchNormalize.normalize('José'), 'jose');
      expect(UserSearchNormalize.normalize('Ação'), 'acao');
      expect(UserSearchNormalize.normalize('François'), 'francois');
    });

    test('unicode characters preserved when no diacritic map', () {
      expect(UserSearchNormalize.normalize('東京'), '東京');
      expect(UserSearchNormalize.normalize('Москва'), 'москва');
    });

    test('min length', () {
      expect(UserSearchNormalize.isQueryReady(''), false);
      expect(UserSearchNormalize.isQueryReady('a'), false);
      expect(UserSearchNormalize.isQueryReady('ab'), true);
    });
  });

  group('UserSearchDebounce', () {
    test('cancel invalidates previous token', () {
      final d = UserSearchDebounce(
        delay: const Duration(milliseconds: 1),
      );
      final t1 = d.schedule();
      expect(d.isCurrent(t1), true);
      d.cancel();
      expect(d.isCurrent(t1), false);
      final t2 = d.schedule();
      expect(d.isCurrent(t2), true);
    });
  });

  group('Search types and public fields', () {
    test('api values are whitelist only', () {
      expect(UserSearchType.name.apiValue, 'name');
      expect(UserSearchType.city.apiValue, 'city');
      expect(UserSearchType.region.apiValue, 'region');
      expect(UserSearchType.country.apiValue, 'country');
    });

    test('PublicUserSearchFields builds normalized public-only fields', () {
      final map = PublicUserSearchFields.build(
        name: 'José',
        city: 'São Paulo',
        region: 'São Paulo',
        country: 'Brasil',
        countryCode: 'BR',
      );
      expect(map['nameSearch'], 'jose');
      expect(map['citySearch'], 'sao paulo');
      expect(map['regionSearch'], 'sao paulo');
      expect(map['countrySearch'], 'brasil');
      expect(map['countryCode'], 'br');
      expect(map.containsKey('email'), false);
      expect(map.containsKey('isPremium'), false);
    });
  });

  group('Privacy payload', () {
    test('fromCallable keeps only safe fields', () {
      final hit = UserSearchHit.fromCallable(<Object?, Object?>{
        'uid': 'u1',
        'name': 'Ana',
        'photoUrl': 'https://x/a.jpg',
        'city': 'Lisboa',
        'region': 'Lisboa',
        'country': 'Portugal',
        'countryCode': 'pt',
        'email': 'secret@x.com',
        'isPremium': true,
        'fcmToken': 'tok',
        'lat': -23.5,
        'role': 'admin',
      });
      expect(hit, isNotNull);
      final map = hit!.toSafeMap();
      expect(
        map.keys.toSet(),
        {'uid', 'name', 'photoUrl', 'city', 'region', 'country', 'countryCode'},
      );
    });

    test('parseResult cursor map and types', () {
      final result = UserSearchService.parseResult({
        'results': [
          {'uid': 'u1', 'name': 'Ana', 'city': 'Rio', 'country': 'Brasil'},
          {'uid': 'u2', 'name': 'Bea'},
        ],
        'nextCursor': {'v': 'bea', 'id': 'u2'},
        'hasMore': true,
        'type': 'city',
      });
      expect(result.hits.length, 2);
      expect(result.nextCursor?.v, 'bea');
      expect(result.nextCursor?.id, 'u2');
      expect(result.type, UserSearchType.city);
      expect(result.hasMore, true);
    });

    test('invalid cursor rejected', () {
      expect(UserSearchCursor.fromDynamic('joao'), isNull);
      expect(UserSearchCursor.fromDynamic({'v': 'x'}), isNull);
      expect(
        UserSearchCursor.fromDynamic({'v': 'x', 'id': 'bad id'}),
        isNull,
      );
    });
  });

  group('Conversation legacy / premium / race helpers', () {
    test('pairKey deterministic', () {
      expect(
        InternationalChatService.pairKey('b', 'a'),
        InternationalChatService.pairKey('a', 'b'),
      );
    });

    test('legacy with pairKey preferred', () {
      expect(
        InternationalChatService.resolveExistingConversationId(
          myUid: 'u1',
          otherUid: 'u2',
          pairKeyMatchIds: const ['legacy_id'],
          participantConversations: const {
            'other': ['u1', 'u2'],
          },
        ),
        'legacy_id',
      );
    });

    test('legacy without pairKey via participants', () {
      expect(
        InternationalChatService.resolveExistingConversationId(
          myUid: 'u1',
          otherUid: 'u2',
          pairKeyMatchIds: const [],
          participantConversations: const {
            'old': ['u2', 'u1'],
            'x': ['u1', 'u3'],
          },
        ),
        'old',
      );
    });

    test('more than 50 conversations map still finds match', () {
      final map = <String, List<String>>{
        for (var i = 0; i < 60; i++) 'c$i': ['u1', 'other_$i'],
        'target': ['u1', 'u2'],
      };
      expect(
        InternationalChatService.resolveExistingConversationId(
          myUid: 'u1',
          otherUid: 'u2',
          pairKeyMatchIds: const [],
          participantConversations: map,
        ),
        'target',
      );
    });

    test('needsPremiumToStartChat free international without existing', () {
      expect(
        InternationalChatService.needsPremiumToStartChat(
          senderData: {'countryCode': 'br', 'isPremium': false},
          recipientData: {'countryCode': 'ca'},
          conversationAlreadyExists: false,
        ),
        true,
      );
    });

    test('needsPremiumToStartChat allows existing international', () {
      expect(
        InternationalChatService.needsPremiumToStartChat(
          senderData: {'countryCode': 'br', 'isPremium': false},
          recipientData: {'countryCode': 'ca'},
          conversationAlreadyExists: true,
        ),
        false,
      );
    });

    test('premium can start international', () {
      expect(
        InternationalChatService.needsPremiumToStartChat(
          senderData: {'countryCode': 'br', 'isPremium': true},
          recipientData: {'countryCode': 'ca'},
          conversationAlreadyExists: false,
        ),
        false,
      );
    });

    test('same country free does not need premium', () {
      expect(
        InternationalChatService.needsPremiumToStartChat(
          senderData: {'countryCode': 'br'},
          recipientData: {'countryCode': 'br'},
          conversationAlreadyExists: false,
        ),
        false,
      );
    });

    test('ConversationLookupException carries message key', () {
      final e = ConversationLookupException(
        'user_search_conversation_lookup_error',
      );
      expect(e.messageKey, 'user_search_conversation_lookup_error');
    });
  });

  group('UI state keys', () {
    test('loading empty error retry keys exist conceptually', () {
      const keys = [
        'user_search_loading',
        'user_search_empty',
        'user_search_error',
        'user_search_retry',
      ];
      expect(keys.length, 4);
    });
  });

  group('l10n user search keys', () {
    const requiredKeys = [
      'user_search_title',
      'user_search_action',
      'user_search_hint',
      'user_search_hint_city',
      'user_search_hint_region',
      'user_search_hint_country',
      'user_search_people',
      'user_search_city',
      'user_search_state',
      'user_search_province',
      'user_search_region',
      'user_search_country',
      'user_search_by_location',
      'user_search_results',
      'user_search_results_city',
      'user_search_results_region',
      'user_search_results_country',
      'user_search_empty',
      'user_search_empty_city',
      'user_search_empty_region',
      'user_search_empty_country',
      'user_search_loading',
      'user_search_retry',
      'user_search_error',
      'user_search_start_chat',
      'user_search_profile_unavailable',
      'user_search_min_chars',
      'user_search_clear',
      'user_search_intl_title',
      'user_search_premium_required',
      'user_search_view_premium',
      'user_search_cancel',
      'user_search_conversation_lookup_error',
    ];

    const files = [
      'lib/l10n/en.json',
      'lib/l10n/pt-BR.json',
      'lib/l10n/pt-PT.json',
      'lib/l10n/es.json',
      'lib/l10n/fr.json',
    ];

    test('all locales contain required keys without duplicates', () {
      for (final path in files) {
        final raw = File(path).readAsStringSync();
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final keys = map.keys.toList();
        expect(keys.toSet().length, keys.length, reason: 'duplicates in $path');
        for (final key in requiredKeys) {
          expect(map.containsKey(key), true, reason: '$key missing in $path');
          expect(
            (map[key] as String).trim().isNotEmpty,
            true,
            reason: '$key empty in $path',
          );
        }
      }
    });
  });
}
