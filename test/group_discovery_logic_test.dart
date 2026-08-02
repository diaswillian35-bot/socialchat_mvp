import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/group_discovery_logic.dart';
import 'package:socialchat_mvp/services/group_discovery_service.dart';
import 'package:socialchat_mvp/services/group_geo.dart';

void main() {
  Map<String, dynamic> group({
    required String scope,
    String countryCode = 'br',
    String country = 'Brasil',
    String city = 'Navegantes',
    List<String> members = const [],
    String? ownerId,
    double? centerLat,
    double? centerLng,
    String? centerCity,
  }) =>
      {
        'scope': scope,
        'countryCode': countryCode,
        'country': country,
        'city': city,
        'members': members,
        if (ownerId != null) 'ownerId': ownerId,
        if (centerLat != null) 'regionCenterLat': centerLat,
        if (centerLng != null) 'regionCenterLng': centerLng,
        if (centerCity != null) 'regionCenterCity': centerCity,
        if (scope == 'region') ...{
          'regionCenterCountryCode': countryCode,
          'regionRadiusKm': 110,
        },
      };

  bool regionMatch(Map<String, dynamic> data, double lat, double lng) =>
      GroupDiscoveryLogic.matchesRegionDiscovery(
        data: data,
        uid: 'u1',
        userCountryCode: 'br',
        userCityLatitude: lat,
        userCityLongitude: lng,
      );

  test('1 city aparece somente em Cidade', () {
    final g = group(scope: 'city');
    expect(
      GroupDiscoveryLogic.matchesCityDiscovery(
        data: g,
        uid: 'u1',
        userCountryCode: 'br',
        userCityKey: 'navegantes',
      ),
      isTrue,
    );
    expect(regionMatch(g, -26.9, -48.65), isFalse);
    expect(
      GroupDiscoveryLogic.matchesCountryDiscovery(
        data: g,
        uid: 'u1',
        userCountryCode: 'br',
      ),
      isFalse,
    );
  });

  test('2 regional dentro de 110 km aparece somente em Região', () {
    final g = group(
      scope: 'region',
      centerLat: -26.9078,
      centerLng: -48.6619,
      centerCity: 'Itajaí',
    );
    expect(regionMatch(g, -26.8943, -48.6546), isTrue);
    expect(
      GroupDiscoveryLogic.matchesCityDiscovery(
        data: g,
        uid: 'u1',
        userCountryCode: 'br',
        userCityKey: 'navegantes',
      ),
      isFalse,
    );
    expect(
      GroupDiscoveryLogic.matchesCountryDiscovery(
        data: g,
        uid: 'u1',
        userCountryCode: 'br',
      ),
      isFalse,
    );
  });

  test('3 exatamente 110 km aparece', () {
    final deltaDegrees =
        (GroupGeo.regionRadiusKm / GroupGeo.earthRadiusKm) * 180 / math.pi;
    final g = group(
      scope: 'region',
      centerLat: 0,
      centerLng: 0,
      centerCity: 'Centro',
    );
    final distance = GroupGeo.distanceKm(
      lat1: 0,
      lng1: 0,
      lat2: deltaDegrees,
      lng2: 0,
    );
    expect(distance, closeTo(110, 1e-9));
    expect(regionMatch(g, deltaDegrees, 0), isTrue);
  });

  test('4 mais de 110 km não aparece', () {
    final g = group(
      scope: 'region',
      centerLat: 0,
      centerLng: 0,
      centerCity: 'Centro',
    );
    expect(regionMatch(g, 1.01, 0), isFalse);
  });

  test('5 country aparece somente em País', () {
    final g = group(scope: 'country', city: 'Itajaí');
    expect(
      GroupDiscoveryLogic.matchesCountryDiscovery(
        data: g,
        uid: 'u1',
        userCountryCode: 'br',
      ),
      isTrue,
    );
    expect(regionMatch(g, -26.9, -48.6), isFalse);
  });

  test('6 membro vê somente em Meus grupos', () {
    final g = group(scope: 'city', members: ['u1']);
    expect(GroupDiscoveryLogic.matchesMine(g, 'u1'), isTrue);
    expect(
      GroupDiscoveryLogic.matchesCityDiscovery(
        data: g,
        uid: 'u1',
        userCountryCode: 'br',
        userCityKey: 'navegantes',
      ),
      isFalse,
    );
  });

  test('7 cidade homônima em países diferentes não mistura', () {
    final g = group(scope: 'city', countryCode: 'ca', city: 'London');
    expect(
      GroupDiscoveryLogic.matchesCityDiscovery(
        data: g,
        uid: 'u1',
        userCountryCode: 'gb',
        userCityKey: 'london',
      ),
      isFalse,
    );
  });

  test('8 Haversine retorna distância conhecida', () {
    final distance = GroupGeo.distanceKm(
      lat1: -26.9078,
      lng1: -48.6619,
      lat2: -26.8943,
      lng2: -48.6546,
    );
    expect(distance, isNotNull);
    expect(distance!, lessThan(3));
    expect(distance, greaterThan(1));
  });

  test('9 linha internacional de data usa caminho curto', () {
    final distance = GroupGeo.distanceKm(
      lat1: 0,
      lng1: 179.9,
      lat2: 0,
      lng2: -179.9,
    );
    expect(distance, closeTo(22.24, 0.2));
  });

  test('10 latitude/longitude inválidas são rejeitadas', () {
    expect(GroupGeo.distanceKm(lat1: 91, lng1: 0, lat2: 0, lng2: 0), isNull);
    expect(
      GroupGeo.distanceKm(lat1: 0, lng1: 181, lat2: 0, lng2: 0),
      isNull,
    );
    expect(GroupGeo.geohash(double.nan, 0), isEmpty);
  });

  test('11 coordenadas ausentes não tornam usuário elegível', () {
    final g = group(
      scope: 'region',
      centerLat: -26.9,
      centerLng: -48.6,
      centerCity: 'Itajaí',
    );
    expect(
      GroupDiscoveryLogic.matchesRegionDiscovery(
        data: g,
        uid: 'u1',
        userCountryCode: 'br',
        userCityLatitude: null,
        userCityLongitude: null,
      ),
      isFalse,
    );
  });

  test('12 regional antigo sem centro não é inferido por estado', () {
    final legacy = {
      'scope': 'region',
      'countryCode': 'br',
      'stateName': 'Santa Catarina',
      'regionKey': 'sc',
      'members': <String>[],
    };
    expect(regionMatch(legacy, -26.9, -48.6), isFalse);
  });

  test('13 card País não expõe cidade/estado', () {
    final location = GroupDiscoveryLogic.cardLocation({
      ...group(scope: 'country', city: 'Itajaí'),
      'stateName': 'SC',
      'country': 'Brazil', // Places EN — ignorado em favor do countryCode
    });
    expect(location.countryOnly, isTrue);
    expect(location.city, isEmpty);
    expect(location.country, 'br');
  });

  test('14 card Cidade usa countryCode ISO, não nome Places', () {
    final location = GroupDiscoveryLogic.cardLocation({
      ...group(scope: 'city'),
      'country': 'Brazil',
      'countryCode': 'br',
    });
    expect(location.showsCity, isTrue);
    expect(location.city, 'Navegantes');
    expect(location.country, 'br');
  });

  test('15 card Região usa cidade central e não contém raio', () {
    final location = GroupDiscoveryLogic.cardLocation(group(
      scope: 'region',
      centerLat: -26.9,
      centerLng: -48.6,
      centerCity: 'Itajaí',
    ));
    expect(location.showsRegionCenter, isTrue);
    expect(location.city, 'Itajaí');
    expect(location.country, 'br');
    expect('${location.city} ${location.country}', isNot(contains('110')));
  });

  test('16 criação regional informa claramente 110 km', () {
    final source = File('lib/pages/create_group_page.dart').readAsStringSync();
    expect(source, contains('create_group_region_radius_title'));
    expect(source, contains('create_group_region_radius_description'));
    expect(source, contains('GroupGeo.regionRadiusKm'));
  });

  test('17 botão Salvar está protegido por SafeArea', () {
    final source = File('lib/pages/create_group_page.dart').readAsStringSync();
    expect(source, contains('body: SafeArea('));
    expect(source, contains('bottom: false'));
    expect(source, contains('bottomNavigationBar:'));
    expect(source, contains('viewInsets.bottom'));
    expect(source, contains('viewPadding.bottom'));
    expect(source, contains('create_group_button'));
  });

  test('18 traduções existem nos cinco idiomas', () {
    const keys = [
      'groups_region_of_city',
      'create_group_region_radius_title',
      'create_group_region_radius_description',
      'create_group_region_radius_short',
      'create_group_region_center',
      'create_group_region_coordinates_required',
    ];
    for (final file in ['en', 'pt-BR', 'pt-PT', 'es', 'fr']) {
      final map = jsonDecode(File('lib/l10n/$file.json').readAsStringSync())
          as Map<String, dynamic>;
      for (final key in keys) {
        expect(map[key]?.toString().trim(), isNotEmpty, reason: '$file $key');
      }
    }
  });

  test('19 paginação, geohash e custo são limitados', () {
    final cells = GroupGeo.candidateGeohashes(
      latitude: -26.9,
      longitude: -48.6,
    );
    expect(cells, isNotEmpty);
    final batches = GroupGeo.geohashBatches(
      latitude: -26.9,
      longitude: -48.6,
    );
    for (final b in batches) {
      expect(b.length, lessThanOrEqualTo(GroupGeo.whereInLimit));
    }
    expect(GroupDiscoveryLogic.pageSize, 20);
    expect(GroupDiscoveryLogic.overFetchMultiplier, 3);
    expect(GroupDiscoveryService.maxDocsPerPageRequest, 300);

    final candidates = [
      for (var i = 0; i < 5; i++)
        GroupDiscoveryItem(id: 'm$i', data: const {}, isMember: true),
      for (var i = 0; i < 25; i++)
        GroupDiscoveryItem(id: 'd$i', data: const {}),
    ];
    expect(
      GroupDiscoveryLogic.takePageAfterMembershipFilter(
        candidates: candidates,
        pageSize: 20,
      ).length,
      20,
    );
  });

  test('20 ausência de duplicação entre seletores', () {
    final regional = group(
      scope: 'region',
      centerLat: -26.9,
      centerLng: -48.6,
      centerCity: 'Itajaí',
    );
    expect(
      GroupDiscoveryLogic.discoveryTabForNonMember(
        data: regional,
        uid: 'u1',
        userCountryCode: 'br',
        userCityKey: 'navegantes',
        userCityLatitude: -26.89,
        userCityLongitude: -48.65,
      ),
      GroupDiscoveryTab.region,
    );

    regional['members'] = ['u1'];
    expect(
      GroupDiscoveryLogic.discoveryTabForNonMember(
        data: regional,
        uid: 'u1',
        userCountryCode: 'br',
        userCityKey: 'navegantes',
        userCityLatitude: -26.89,
        userCityLongitude: -48.65,
      ),
      GroupDiscoveryTab.mine,
    );
  });
}
