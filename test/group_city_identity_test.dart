import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/group_create_flow.dart';
import 'package:socialchat_mvp/services/group_discovery_logic.dart';
import 'package:socialchat_mvp/services/group_location_normalize.dart';
import 'package:socialchat_mvp/services/group_places_client.dart';

void main() {
  Map<String, dynamic> yorkGroup({String cityKey = 'york'}) => {
        'id': 'g-york',
        'scope': 'city',
        'countryCode': 'ca',
        'city': 'York',
        'cityName': 'York',
        'cityKey': cityKey,
        'stateName': 'ON',
        'displayLocation': 'York, ON, Canadá',
        'deleted': false,
        'ownerId': 'owner',
        'members': ['owner'],
        'admins': ['owner'],
      };

  test('autocomplete keeps York when Toronto is only the parent segment', () {
    final york = GroupPlacesClient.parseDescription(
      description: 'York, ON, Canadá',
      placeId: 'york-place',
    );
    expect(york?.cityName, 'York');
    expect(york?.stateName, 'ON');
    expect(york?.cityName, isNot('Toronto'));

    final nested = GroupPlacesClient.parseDescription(
      description: 'York, Toronto, ON, Canada',
      placeId: 'york-place',
    );
    expect(nested?.cityName, 'York');
    expect(nested?.stateName, 'ON');

    final toronto = GroupPlacesClient.parseDescription(
      description: 'Toronto, ON, Canada',
      placeId: 'toronto-place',
    );
    expect(toronto?.cityName, 'Toronto');
    expect(toronto?.stateName, 'ON');
  });

  test('stored parent locality still displays the selected place', () {
    expect(
      GroupLocationNormalize.cityDisplayName({
        'city': 'Toronto',
        'cityName': 'Toronto',
        'displayLocation': 'York, ON, Canadá',
      }),
      'York',
    );
    expect(
      GroupLocationNormalize.cityDisplayName({
        'city': 'Toronto',
        'cityName': 'Toronto',
        'displayLocation': 'Toronto, ON, Canada',
      }),
      'Toronto',
    );
    expect(
      GroupDiscoveryLogic.cardLocation({
        'scope': 'city',
        'countryCode': 'ca',
        'city': 'Toronto',
        'displayLocation': 'York, ON, Canadá',
      }).city,
      'York',
    );
  });

  test('selected York is not replaced by a Toronto profile suggestion', () {
    final decision = GroupCreateFlow.resolveCity(
      required: true,
      typed: 'York, ON, Canadá',
      selectedPlaceId: 'york-place',
      selectedCityName: 'York',
      selectedStateName: 'ON',
      selectedDisplay: 'York, ON, Canadá',
      suggestions: const [
        GroupCityCandidate(
          cityName: 'Toronto',
          stateName: 'ON',
          countryName: 'Canadá',
          display: 'Toronto, ON, Canadá',
          placeId: 'toronto-place',
        ),
      ],
      searched: true,
    );
    expect(decision.accepted, isTrue);
    expect(decision.cityName, 'York');
    expect(decision.placeId, 'york-place');
  });

  test('creator and member see their group on any city filter', () {
    final data = yorkGroup();
    expect(GroupDiscoveryLogic.matchesMine(data, 'owner'), isTrue);
    expect(
      GroupDiscoveryLogic.discoveryTabForNonMember(
        data: data,
        uid: 'owner',
        userCountryCode: 'ca',
        userCityKey: 'toronto',
        userCityLatitude: 43.65,
        userCityLongitude: -79.38,
      ),
      GroupDiscoveryTab.mine,
    );
    final asMember = {
      ...data,
      'members': ['owner', 'member'],
    };
    expect(GroupDiscoveryLogic.matchesMine(asMember, 'member'), isTrue);
    expect(
      GroupDiscoveryLogic.visibleDiscoveryFromDocs(
        docs: [asMember],
        tab: GroupDiscoveryTab.city,
        uid: 'member',
        userCountryCode: 'ca',
        userCityKey: 'toronto',
        userCityLatitude: null,
        userCityLongitude: null,
        pendingIds: const {},
      ),
      isEmpty,
    );
  });

  test('external user sees York only on the York city scope', () {
    final data = {
      ...yorkGroup(),
      'members': ['owner'],
      'ownerId': 'owner',
    };
    final yorkViewer = GroupDiscoveryLogic.visibleDiscoveryFromDocs(
      docs: [data],
      tab: GroupDiscoveryTab.city,
      uid: 'viewer',
      userCountryCode: 'ca',
      userCityKey: 'york',
      userCityLatitude: null,
      userCityLongitude: null,
      pendingIds: const {},
    );
    expect(yorkViewer, hasLength(1));

    final torontoViewer = GroupDiscoveryLogic.visibleDiscoveryFromDocs(
      docs: [data],
      tab: GroupDiscoveryTab.city,
      uid: 'viewer',
      userCountryCode: 'ca',
      userCityKey: 'toronto',
      userCityLatitude: null,
      userCityLongitude: null,
      pendingIds: const {},
    );
    expect(torontoViewer, isEmpty);

    final torontoGroup = {
      ...data,
      'id': 'g-toronto',
      'city': 'Toronto',
      'cityName': 'Toronto',
      'cityKey': 'toronto',
      'displayLocation': 'Toronto, ON, Canada',
    };
    final seesToronto = GroupDiscoveryLogic.visibleDiscoveryFromDocs(
      docs: [torontoGroup],
      tab: GroupDiscoveryTab.city,
      uid: 'viewer',
      userCountryCode: 'ca',
      userCityKey: 'toronto',
      userCityLatitude: null,
      userCityLongitude: null,
      pendingIds: const {},
    );
    expect(seesToronto.single.data['city'], 'Toronto');
  });

  test('a new group and a city edit show up without an unread change', () {
    final before = [
      GroupDiscoveryItem(
        id: 'old',
        data: {
          'name': 'Old',
          'city': 'Toronto',
          'unread': {'owner': 0},
        },
        isMember: true,
      ),
    ];
    final created = GroupDiscoveryLogic.replaceMembershipSnapshot(
      previous: before,
      updates: {
        'old': before.single.data,
        'g-york': yorkGroup(),
      },
    );
    expect(created.map((item) => item.id), contains('g-york'));
    expect(
      GroupDiscoveryLogic.listSurfaceChanged(
        before: before,
        after: created,
        uid: 'owner',
      ),
      isTrue,
    );

    final edited = GroupDiscoveryLogic.replaceMembershipSnapshot(
      previous: created,
      updates: {
        for (final item in created)
          item.id: item.id == 'g-york'
              ? {...item.data, 'city': 'Toronto', 'displayLocation': 'Toronto, ON, Canada'}
              : item.data,
      },
    );
    expect(
      GroupDiscoveryLogic.listSurfaceChanged(
        before: created,
        after: edited,
        uid: 'owner',
      ),
      isTrue,
    );
  });

  test('list and editor expose the live query and owner edits', () {
    final list = File('lib/pages/groups_list_page.dart').readAsStringSync();
    expect(list, contains('_bindDiscovery'));
    expect(list, contains("where('cityKey', isEqualTo: _myCityKey)"));
    expect(list, contains('replaceMembershipSnapshot'));
    expect(list, isNot(contains('markGroupAsRead')));

    final info = File('lib/pages/group_info_page.dart').readAsStringSync();
    expect(info, contains('_editName'));
    expect(info, contains('_editCity'));
    expect(info, contains('showGroupCityPicker'));
    expect(info, contains('snapshots()'));

    for (final code in ['pt-BR', 'pt-PT', 'en', 'es', 'fr']) {
      final json = jsonDecode(
        File('lib/l10n/$code.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(json['group_edit_name'], isNotEmpty);
      expect(json['group_edit_city'], isNotEmpty);
      expect(json['group_edit_cover'], isNotEmpty);
      expect(json['editBio'], isNotEmpty);
      expect(json['field_pending'], isNotEmpty);
    }
  });
}
