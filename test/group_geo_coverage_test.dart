import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/group_discovery_logic.dart';
import 'package:socialchat_mvp/services/group_geo.dart';

void main() {
  GroupLatLng dest(double lat, double lng, double km, double bearing) =>
      GroupGeo.destinationPoint(
        latitude: lat,
        longitude: lng,
        distanceKm: km,
        bearingDeg: bearing,
      );

  test('círculo 110 km: N/S/E/O, diagonais e borda exata cobertos', () {
    final centers = <Map<String, Object>>[
      {'lat': -26.8943, 'lng': -48.6546, 'name': 'navegantes'},
      {'lat': 0.0, 'lng': 0.0, 'name': 'equador'},
      {'lat': 64.0, 'lng': -21.0, 'name': 'alta_lat'},
      {'lat': 1.0, 'lng': 179.5, 'name': 'dateline'},
      {'lat': -1.0, 'lng': -179.5, 'name': 'dateline_w'},
    ];

    for (final c in centers) {
      final lat = c['lat'] as double;
      final lng = c['lng'] as double;
      final name = c['name'] as String;
      final cells = GroupGeo.candidateGeohashes(
        latitude: lat,
        longitude: lng,
      );
      expect(cells, isNotEmpty, reason: name);
      expect(cells.length, lessThan(500), reason: 'custo controlado $name');

      for (final bearing in [0.0, 45.0, 90.0, 135.0, 180.0, 225.0, 270.0, 315.0]) {
        for (final km in [0.0, 55.0, 110.0]) {
          final p = dest(lat, lng, km, bearing);
          final h = GroupGeo.geohash(p.latitude, p.longitude);
          expect(
            cells.contains(h),
            isTrue,
            reason: '$name bearing=$bearing km=$km hash=$h missing',
          );
        }
      }
    }
  });

  test('lotes whereIn ≤30 e união cobre o conjunto completo', () {
    final all = GroupGeo.candidateGeohashes(
      latitude: -26.8943,
      longitude: -48.6546,
    );
    final batches = GroupGeo.geohashBatches(
      latitude: -26.8943,
      longitude: -48.6546,
    );
    expect(batches, isNotEmpty);
    for (final b in batches) {
      expect(b.length, lessThanOrEqualTo(GroupGeo.whereInLimit));
    }
    final reunited = <String>{};
    for (final b in batches) {
      reunited.addAll(b);
    }
    expect(reunited, unorderedEquals(all.toSet()));
  });

  test('células tipicamente poucas; pior caso alto sem buraco', () {
    final equatorial = GroupGeo.candidateGeohashes(latitude: 0, longitude: 0);
    final high = GroupGeo.candidateGeohashes(latitude: 70, longitude: 25);
    expect(equatorial.length, lessThan(80));
    expect(high.length, greaterThanOrEqualTo(equatorial.length));
  });

  test('paginação lógica: >60 candidatos e muitos fora do raio', () {
    const centerLat = -26.9;
    const centerLng = -48.65;
    final candidates = <GroupDiscoveryItem>[];

    for (var i = 0; i < 40; i++) {
      final far = dest(centerLat, centerLng, 200, (i * 17.0) % 360);
      candidates.add(
        GroupDiscoveryItem(
          id: 'far_$i',
          data: {
            'id': 'far_$i',
            'scope': 'region',
            'countryCode': 'br',
            'regionCenterLat': far.latitude,
            'regionCenterLng': far.longitude,
            'regionCenterCountryCode': 'br',
            'regionRadiusKm': 110,
            'updatedAt': DateTime.fromMillisecondsSinceEpoch(1000 - i),
          },
        ),
      );
    }
    for (var i = 0; i < 25; i++) {
      final near =
          dest(centerLat, centerLng, 20 + i.toDouble(), (i * 40.0) % 360);
      candidates.add(
        GroupDiscoveryItem(
          id: 'near_$i',
          data: {
            'id': 'near_$i',
            'scope': 'region',
            'countryCode': 'br',
            'regionCenterLat': near.latitude,
            'regionCenterLng': near.longitude,
            'regionCenterCountryCode': 'br',
            'regionRadiusKm': 110,
            'updatedAt': DateTime.fromMillisecondsSinceEpoch(2000 - i),
          },
        ),
      );
    }

    final matched = <GroupDiscoveryItem>[];
    for (final c in candidates) {
      final ok = GroupDiscoveryLogic.matchesRegionDiscovery(
        data: c.data,
        uid: 'u1',
        userCountryCode: 'br',
        userCityLatitude: centerLat,
        userCityLongitude: centerLng,
      );
      if (ok) matched.add(c);
    }
    expect(matched.length, 25);

    final page1 = GroupDiscoveryLogic.takePageAfterMembershipFilter(
      candidates: matched,
      pageSize: 20,
    );
    expect(page1.length, 20);
    final remaining = matched.skip(20).toList();
    final page2 = GroupDiscoveryLogic.takePageAfterMembershipFilter(
      candidates: remaining,
      pageSize: 20,
    );
    expect(page2.length, 5);
    final ids = <String>{
      ...page1.map((e) => e.id),
      ...page2.map((e) => e.id),
    };
    expect(ids.length, 25);
  });

  test('deduplicação entre lotes', () {
    final a = ['abc', 'def', 'ghi'];
    final b = ['def', 'xyz'];
    final seen = <String>{};
    final merged = <String>[];
    for (final id in [...a, ...b]) {
      if (seen.add(id)) merged.add(id);
    }
    expect(merged, ['abc', 'def', 'ghi', 'xyz']);
  });

  test('país diferente na fronteira não entra (mesmo perto)', () {
    final g = {
      'scope': 'region',
      'countryCode': 'uy',
      'regionCenterLat': -30.0,
      'regionCenterLng': -57.0,
      'regionCenterCountryCode': 'uy',
      'regionRadiusKm': 110,
    };
    expect(
      GroupDiscoveryLogic.matchesRegionDiscovery(
        data: g,
        uid: 'u1',
        userCountryCode: 'br',
        userCityLatitude: -30.0,
        userCityLongitude: -57.1,
      ),
      isFalse,
    );
  });

  test('Haversine na linha internacional de data', () {
    final d = GroupGeo.distanceKm(
      lat1: 1,
      lng1: 179.8,
      lat2: 1,
      lng2: -179.8,
    );
    expect(d, isNotNull);
    expect(d!, lessThan(50));
  });

  test('contagem típica de células (relatório)', () {
    final n = GroupGeo.candidateGeohashes(
      latitude: -26.8943,
      longitude: -48.6546,
    ).length;
    // ignore: avoid_print
    print('células tipicas Navegantes@110km: $n');
    expect(n, greaterThan(0));
    final batches = GroupGeo.geohashBatches(
      latitude: -26.8943,
      longitude: -48.6546,
    );
    // ignore: avoid_print
    print('lotes whereIn: ${batches.length}');
    expect(batches.first.length, lessThanOrEqualTo(30));
  });

  test('bbox alta latitude permanece coberta; lotes cobrem união', () {
    final cells = GroupGeo.candidateGeohashes(latitude: 75, longitude: 10);
    expect(cells, isNotEmpty);
    // Perto do pólo a caixa se alarga; se passar de 30, fatura em lotes.
    final batches = GroupGeo.geohashBatches(latitude: 75, longitude: 10);
    expect(batches, isNotEmpty);
    for (final b in batches) {
      expect(b.length, lessThanOrEqualTo(GroupGeo.whereInLimit));
    }
    final union = batches.expand((e) => e).toSet();
    expect(union.length, cells.length);

    // Caso extremo: anel completo de longitude (não esvazia por limite 30).
    final polar = GroupGeo.candidateGeohashes(latitude: 89.5, longitude: 0);
    expect(polar.length, greaterThan(30));
    final polarBatches = GroupGeo.geohashBatches(latitude: 89.5, longitude: 0);
    expect(polarBatches.length, greaterThan(1));
    expect(
      polarBatches.expand((e) => e).toSet().length,
      polar.length,
    );
  });

  test('ponto na borda exata 110 km está no conjunto', () {
    const lat = 40.0;
    const lng = -74.0;
    final cells = GroupGeo.candidateGeohashes(latitude: lat, longitude: lng);
    final east = dest(lat, lng, 110, 90);
    expect(
      GroupGeo.withinRegion(
        userLat: east.latitude,
        userLng: east.longitude,
        centerLat: lat,
        centerLng: lng,
      ),
      isTrue,
    );
    expect(cells.contains(GroupGeo.geohash(east.latitude, east.longitude)), isTrue);
    final beyond = dest(lat, lng, 110.5, 90);
    expect(
      GroupGeo.withinRegion(
        userLat: beyond.latitude,
        userLng: beyond.longitude,
        centerLat: lat,
        centerLng: lng,
      ),
      isFalse,
    );
  });

  test('math sanity earth radius', () {
    final expected =
        (GroupGeo.regionRadiusKm / GroupGeo.earthRadiusKm) * 180 / math.pi;
    expect(expected, greaterThan(0.9));
    expect(expected, lessThan(1.1));
  });
}
