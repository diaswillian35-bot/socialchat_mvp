import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/group_discovery_logic.dart';
import 'package:socialchat_mvp/services/group_discovery_service.dart';
import 'package:socialchat_mvp/services/group_geo.dart';

void main() {
  const yorkLat = 43.70;
  const yorkLng = -79.45;
  const torontoLat = 43.6532;
  const torontoLng = -79.3832;

  Map<String, dynamic> yorkCity({
    String id = 'york-city',
    double? lat = yorkLat,
    double? lng = yorkLng,
    bool includeCoords = true,
    List<String> members = const ['creator'],
    String ownerId = 'creator',
  }) =>
      {
        'id': id,
        'scope': 'city',
        'countryCode': 'ca',
        'city': 'Toronto',
        'cityName': 'Toronto',
        'cityKey': 'toronto',
        'displayLocation': 'York, ON, Canadá',
        'deleted': false,
        'isActive': true,
        'ownerId': ownerId,
        'members': members,
        if (includeCoords && lat != null) 'latitude': lat,
        if (includeCoords && lng != null) 'longitude': lng,
      };

  List<String> regionIds({
    required List<Map<String, dynamic>> docs,
    required String uid,
    String cityKey = 'york',
    num? lat = yorkLat,
    num? lng = yorkLng,
  }) {
    return GroupDiscoveryLogic.visibleDiscoveryFromDocs(
      docs: docs,
      tab: GroupDiscoveryTab.region,
      uid: uid,
      userCountryCode: 'ca',
      userCityKey: cityKey,
      userCityLatitude: lat,
      userCityLongitude: lng,
      pendingIds: const {},
    ).map((item) => item.id).toList();
  }

  test('York and Toronto city centers are inside 50 km', () {
    expect(GroupGeo.nearbyCityRadiusKm, 50);
    final distance = GroupGeo.distanceKm(
      lat1: yorkLat,
      lng1: yorkLng,
      lat2: torontoLat,
      lng2: torontoLng,
    );
    expect(distance, isNotNull);
    expect(distance!, lessThan(GroupGeo.nearbyCityRadiusKm));
    expect(distance, greaterThan(1));
  });

  test('legacy York with a Toronto cityKey is Cidade for a York user', () {
    final york = yorkCity();
    expect(
      GroupDiscoveryLogic.visibleDiscoveryFromDocs(
        docs: [york],
        tab: GroupDiscoveryTab.city,
        uid: 'viewer',
        userCountryCode: 'ca',
        userCityKey: 'york',
        userCityLatitude: yorkLat,
        userCityLongitude: yorkLng,
        pendingIds: const {},
      ).map((item) => item.id),
      ['york-city'],
    );
    expect(regionIds(docs: [york], uid: 'viewer', cityKey: 'york'), isEmpty);
    expect(
      GroupDiscoveryLogic.discoveryTabForNonMember(
        data: york,
        uid: 'viewer',
        userCountryCode: 'ca',
        userCityKey: 'york',
        userCityLatitude: yorkLat,
        userCityLongitude: yorkLng,
      ),
      GroupDiscoveryTab.city,
    );
  });

  test('the same cityKey stays on Cidade and off Região', () {
    final york = yorkCity()..['cityKey'] = 'york';
    expect(
      GroupDiscoveryLogic.visibleDiscoveryFromDocs(
        docs: [york],
        tab: GroupDiscoveryTab.city,
        uid: 'viewer',
        userCountryCode: 'ca',
        userCityKey: 'york',
        userCityLatitude: yorkLat,
        userCityLongitude: yorkLng,
        pendingIds: const {},
      ).single.id,
      'york-city',
    );
    expect(regionIds(docs: [york], uid: 'viewer'), isEmpty);
  });

  test('a Toronto viewer sees a York cityKey group on Região', () {
    final york = yorkCity()..['cityKey'] = 'york';
    expect(
      GroupDiscoveryLogic.visibleDiscoveryFromDocs(
        docs: [york],
        tab: GroupDiscoveryTab.city,
        uid: 'toronto-viewer',
        userCountryCode: 'ca',
        userCityKey: 'toronto',
        userCityLatitude: torontoLat,
        userCityLongitude: torontoLng,
        pendingIds: const {},
      ),
      isEmpty,
    );
    expect(
      regionIds(
        docs: [york],
        uid: 'toronto-viewer',
        cityKey: 'toronto',
        lat: torontoLat,
        lng: torontoLng,
      ),
      ['york-city'],
    );
  });

  test('a city group beyond 50 km stays off Região', () {
    Map<String, dynamic> torontoAt(double lat, double lng) {
      return yorkCity(lat: lat, lng: lng)
        ..['displayLocation'] = 'Toronto, ON, Canada'
        ..['cityKey'] = 'toronto';
    }

    final far = GroupGeo.destinationPoint(
      latitude: yorkLat,
      longitude: yorkLng,
      distanceKm: 60,
      bearingDeg: 0,
    );
    expect(
      regionIds(docs: [torontoAt(far.latitude, far.longitude)], uid: 'viewer'),
      isEmpty,
    );
    final edge = GroupGeo.destinationPoint(
      latitude: yorkLat,
      longitude: yorkLng,
      distanceKm: GroupGeo.nearbyCityRadiusKm,
      bearingDeg: 90,
    );
    expect(
      regionIds(
        docs: [torontoAt(edge.latitude, edge.longitude)],
        uid: 'viewer',
      ),
      ['york-city'],
    );
  });

  test('a nearby regional group stays on Região', () {
    final regional = {
      'id': 'regional',
      'scope': 'region',
      'countryCode': 'ca',
      'city': 'Toronto',
      'cityKey': 'toronto',
      'regionCenterCity': 'Toronto',
      'regionCenterCountryCode': 'ca',
      'regionCenterLat': torontoLat,
      'regionCenterLng': torontoLng,
      'regionRadiusKm': GroupGeo.regionRadiusKm,
      'deleted': false,
      'members': ['someone-else'],
    };
    expect(regionIds(docs: [regional], uid: 'viewer'), ['regional']);
    expect(
      GroupDiscoveryLogic.visibleDiscoveryFromDocs(
        docs: [regional],
        tab: GroupDiscoveryTab.city,
        uid: 'viewer',
        userCountryCode: 'ca',
        userCityKey: 'york',
        userCityLatitude: yorkLat,
        userCityLongitude: yorkLng,
        pendingIds: const {},
      ),
      isEmpty,
    );
    expect(
      GroupDiscoveryLogic.visibleDiscoveryFromDocs(
        docs: [regional],
        tab: GroupDiscoveryTab.country,
        uid: 'viewer',
        userCountryCode: 'ca',
        userCityKey: 'york',
        userCityLatitude: yorkLat,
        userCityLongitude: yorkLng,
        pendingIds: const {},
      ),
      isEmpty,
    );
  });

  test('hidden, blocked and deleted groups stay off Região', () {
    final hidden = yorkCity(id: 'hidden')..['hiddenFor'] = ['viewer'];
    final blocked = yorkCity(id: 'blocked')..['blocked'] = ['viewer'];
    final blockedUsers = yorkCity(id: 'blocked-users')
      ..['blockedUsers'] = ['viewer'];
    final optedOut = yorkCity(id: 'opt-out')..['hiddenFromDiscovery'] = true;
    final deleted = yorkCity(id: 'deleted')..['deleted'] = true;
    final inactive = yorkCity(id: 'inactive')..['isActive'] = false;
    expect(
      regionIds(
        docs: [hidden, blocked, blockedUsers, optedOut, deleted, inactive],
        uid: 'viewer',
      ),
      isEmpty,
    );
    expect(
      GroupDiscoveryLogic.matchesMine(yorkCity(), 'creator'),
      isTrue,
    );
    expect(regionIds(docs: [yorkCity()], uid: 'creator'), isEmpty);
  });

  test('missing coordinates do not expose the group by city text', () {
    final nameless = yorkCity(includeCoords: false);
    expect(regionIds(docs: [nameless], uid: 'viewer'), isEmpty);
    final origin = yorkCity(lat: 0, lng: 0);
    expect(regionIds(docs: [origin], uid: 'viewer'), isEmpty);
    expect(
      regionIds(docs: [yorkCity()], uid: 'viewer', lat: null, lng: null),
      isEmpty,
    );
    expect(
      GroupDiscoveryLogic.matchesNearbyCityDiscovery(
        data: nameless,
        uid: 'viewer',
        userCountryCode: 'ca',
        userCityKey: 'york',
        userCityLatitude: yorkLat,
        userCityLongitude: yorkLng,
      ),
      isFalse,
    );
  });

  test('a nearby-city failure does not clear another tab', () {
    final region = GroupDiscoveryLogic.completeListFetch(
      liveSeen: false,
      failed: true,
      hasItems: false,
    );
    final mine = GroupDiscoveryLogic.completeListFetch(
      liveSeen: true,
      failed: false,
      hasItems: true,
    );
    expect(region.showError, isTrue);
    expect(region.loading, isFalse);
    expect(mine.showError, isFalse);
    expect(mine.loading, isFalse);
    expect(
      GroupDiscoveryLogic.decideState(
        profileLoaded: true,
        locationOk: true,
        loading: region.loading,
        hasError: region.showError,
        hasItems: false,
      ),
      GroupDiscoveryUiState.error,
    );
  });

  test('the nearby city read is bounded on the shared iOS and Android client', () {
    expect(
      GroupDiscoveryLogic.nearbyCityQueryLimit,
      inInclusiveRange(1, GroupDiscoveryService.maxDocsPerPageRequest),
    );
    final page = File('lib/pages/groups_list_page.dart').readAsStringSync();
    final service =
        File('lib/services/group_discovery_service.dart').readAsStringSync();
    expect(page, contains('GroupDiscoveryLogic.nearbyCityQueryLimit'));
    expect(service, contains('GroupDiscoveryLogic.nearbyCityQueryLimit'));
    expect(page, isNot(contains(".limit(null)")));
    expect(
      GroupDiscoveryLogic.combineRegionTabItems(
        regional: [
          GroupDiscoveryItem(id: 'regional', data: const {'id': 'regional'}),
        ],
        nearbyCities: [
          GroupDiscoveryItem(id: 'york-city', data: const {'id': 'york-city'}),
          GroupDiscoveryItem(id: 'regional', data: const {'id': 'regional'}),
        ],
      ).map((item) => item.id),
      ['regional', 'york-city'],
    );
  });
}
