import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/group_discovery_logic.dart';
import 'package:socialchat_mvp/services/group_location_normalize.dart';

void main() {
  const yorkLat = 43.70;
  const yorkLng = -79.45;
  const yorkPlace = 'york-place';

  Map<String, dynamic> group({
    required String id,
    String cityKey = 'toronto',
    String city = 'Toronto',
    String display = 'York, ON, Canadá',
    String placeId = yorkPlace,
    double? lat = yorkLat,
    double? lng = yorkLng,
    bool coords = true,
    List<String> members = const ['creator'],
  }) =>
      {
        'id': id,
        'scope': 'city',
        'countryCode': 'ca',
        'city': city,
        'cityName': city,
        'cityKey': cityKey,
        'displayLocation': display,
        'placeId': placeId,
        'deleted': false,
        'members': members,
        if (coords && lat != null) 'latitude': lat,
        if (coords && lng != null) 'longitude': lng,
      };

  List<String> ids({
    required List<Map<String, dynamic>> docs,
    required GroupDiscoveryTab tab,
    String cityKey = 'york',
    String placeId = yorkPlace,
    num? lat = yorkLat,
    num? lng = yorkLng,
    String uid = 'viewer',
  }) {
    return GroupDiscoveryLogic.visibleDiscoveryFromDocs(
      docs: docs,
      tab: tab,
      uid: uid,
      userCountryCode: 'ca',
      userCityKey: cityKey,
      userPlaceId: placeId,
      userCityLatitude: lat,
      userCityLongitude: lng,
      pendingIds: const {},
    ).map((item) => item.id).toList();
  }

  test('legacy York with cityKey toronto appears on York Cidade', () {
    final legacy = group(id: 'legacy-york');
    expect(GroupLocationNormalize.discoveryCityKey(legacy), 'york');
    expect(ids(docs: [legacy], tab: GroupDiscoveryTab.city), ['legacy-york']);
    expect(ids(docs: [legacy], tab: GroupDiscoveryTab.region), isEmpty);
    expect(ids(docs: [legacy], tab: GroupDiscoveryTab.country), isEmpty);
    expect(
      GroupDiscoveryLogic.matchesMine(legacy, 'creator'),
      isTrue,
    );
    expect(
      ids(docs: [legacy], tab: GroupDiscoveryTab.city, uid: 'creator'),
      isEmpty,
    );
  });

  test('true Toronto near York stays off York Cidade and can be Região', () {
    final toronto = group(
      id: 'true-toronto',
      display: 'Toronto, ON, Canada',
      placeId: 'toronto-place',
    );
    expect(GroupLocationNormalize.discoveryCityKey(toronto), 'toronto');
    expect(ids(docs: [toronto], tab: GroupDiscoveryTab.city), isEmpty);
    expect(ids(docs: [toronto], tab: GroupDiscoveryTab.region), ['true-toronto']);
  });

  test('the same group is not listed on Cidade and Região', () {
    final legacy = group(id: 'legacy-york');
    final toronto = group(
      id: 'true-toronto',
      display: 'Toronto, ON, Canada',
      placeId: 'toronto-place',
    );
    final city = ids(docs: [legacy, toronto], tab: GroupDiscoveryTab.city);
    final region = ids(docs: [legacy, toronto], tab: GroupDiscoveryTab.region);
    expect(city, ['legacy-york']);
    expect(region, ['true-toronto']);
    expect(city.toSet().intersection(region.toSet()), isEmpty);
  });

  test('identical placeId wins over a parent city name', () {
    final aliased = group(
      id: 'same-place',
      display: 'Toronto, ON, Canada',
      cityKey: 'toronto',
      placeId: yorkPlace,
    );
    expect(ids(docs: [aliased], tab: GroupDiscoveryTab.city), ['same-place']);
    expect(ids(docs: [aliased], tab: GroupDiscoveryTab.region), isEmpty);
  });

  test('ambiguous or missing coordinates do not invent a York match', () {
    final unnamed = group(
      id: 'unnamed',
      display: '',
      placeId: '',
      cityKey: 'toronto',
    );
    expect(ids(docs: [unnamed], tab: GroupDiscoveryTab.city), isEmpty);
    expect(ids(docs: [unnamed], tab: GroupDiscoveryTab.region), ['unnamed']);

    final noCoords = group(
      id: 'no-coords',
      display: '',
      placeId: '',
      coords: false,
    );
    expect(
      ids(docs: [noCoords], tab: GroupDiscoveryTab.city, lat: null, lng: null),
      isEmpty,
    );
    expect(
      ids(docs: [noCoords], tab: GroupDiscoveryTab.region, lat: null, lng: null),
      isEmpty,
    );

    final namedWithoutCoords = group(
      id: 'named',
      coords: false,
    );
    expect(
      ids(
        docs: [namedWithoutCoords],
        tab: GroupDiscoveryTab.city,
        lat: null,
        lng: null,
      ),
      ['named'],
    );
    expect(
      ids(
        docs: [namedWithoutCoords],
        tab: GroupDiscoveryTab.region,
        lat: null,
        lng: null,
      ),
      isEmpty,
    );
  });

  test('North York is not treated as York', () {
    final north = group(
      id: 'north-york',
      display: 'North York, ON, Canadá',
      placeId: 'north-york-place',
    );
    expect(GroupLocationNormalize.discoveryCityKey(north), 'north york');
    expect(ids(docs: [north], tab: GroupDiscoveryTab.city), isEmpty);
  });

  test('hidden, blocked and deleted legacy groups stay off Cidade', () {
    final hidden = group(id: 'hidden')..['hiddenFor'] = ['viewer'];
    final blocked = group(id: 'blocked')..['blocked'] = ['viewer'];
    final deleted = group(id: 'deleted')..['deleted'] = true;
    final optedOut = group(id: 'opt')..['hiddenFromDiscovery'] = true;
    expect(
      ids(
        docs: [hidden, blocked, deleted, optedOut],
        tab: GroupDiscoveryTab.city,
      ),
      isEmpty,
    );
  });

  test('iOS and Android share one bounded candidate read for both tabs', () {
    final page = File('lib/pages/groups_list_page.dart').readAsStringSync();
    expect(
      'nearbyCityQueryLimit'.allMatches(page).length,
      1,
    );
    expect(page, contains('_publishCity(uid)'));
    expect(page, contains('_publishRegion(uid)'));
    expect(page, isNot(contains('collectionGroup(')));
  });
}
