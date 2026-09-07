import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/group_geo.dart';
import 'package:socialchat_mvp/services/remdy_launch_access.dart';
import 'package:socialchat_mvp/services/user_location_scope.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  Map<String, dynamic> user({
    required String cityName,
    String? stateName,
    String? stateCode,
    required String homeCountryCode,
    required double lat,
    required double lng,
    bool useCityLatKeys = true,
  }) {
    return {
      'cityName': cityName,
      if (stateName != null) 'stateName': stateName,
      if (stateCode != null) 'stateCode': stateCode,
      'homeCountryCode': homeCountryCode,
      if (useCityLatKeys) ...{
        'cityLat': lat,
        'cityLng': lng,
      } else ...{
        'lat': lat,
        'lng': lng,
      },
    };
  }

  // Coordenadas reais (centros aproximados).
  const florianopolisLat = -27.5945;
  const florianopolisLng = -48.5477;
  const saoPauloLat = -23.5505;
  const saoPauloLng = -46.6333;
  const campinasLat = -22.9099;
  const campinasLng = -47.0626;
  const campoMouraoLat = -24.0463;
  const campoMouraoLng = -52.3780;
  const peabiruLat = -23.9140;
  const peabiruLng = -52.3432;
  const curitibaLat = -25.4284;
  const curitibaLng = -49.2733;
  const dionisioCerqueiraLat = -26.2647;
  const dionisioCerqueiraLng = -53.6400; // SC
  const barracaoLat = -26.1260;
  const barracaoLng = -53.6330; // PR — fronteira, <110 km de Dionísio
  const torontoLat = 43.6532;
  const torontoLng = -79.3832;

  group('UserLocationScope geo radius 110 km', () {
    test('rejects missing city, country or coordinates', () {
      expect(
        UserLocationScope.hasCompleteProfileLocation({
          'homeCountryCode': 'br',
          'cityName': 'Curitiba',
        }),
        isFalse,
      );
      expect(
        UserLocationScope.hasCompleteProfileLocation({
          'homeCountryCode': 'br',
          'cityLat': -25.4,
          'cityLng': -49.2,
        }),
        isFalse,
      );
      expect(
        UserLocationScope.isDiscoverableProfile({
          'cityName': 'Curitiba',
          'cityLat': -25.4,
          'cityLng': -49.2,
        }),
        isFalse,
      );
    });

    test('rejects 0,0 and invalid coordinates', () {
      expect(UserLocationScope.isValidCityCoordinate(0, 0), isFalse);
      expect(UserLocationScope.isValidCityCoordinate(0.0, 0.0), isFalse);
      expect(UserLocationScope.isValidCityCoordinate(91, -46), isFalse);
      expect(UserLocationScope.isValidCityCoordinate(-23.5, 200), isFalse);
      expect(UserLocationScope.isValidCityCoordinate(null, -46), isFalse);
      expect(
        UserLocationScope.resolveCanonicalCoords({
          'cityLat': 0,
          'cityLng': 0,
          'cityName': 'X',
          'homeCountryCode': 'br',
        }),
        isNull,
      );
      expect(
        UserLocationScope.isValidCityCoordinate(
          florianopolisLat,
          florianopolisLng,
        ),
        isTrue,
      );
    });

    test('same city on Home; distant same-name UF does not match', () {
      final navA = user(
        cityName: 'Navegantes',
        stateCode: 'SC',
        homeCountryCode: 'br',
        lat: -26.8986,
        lng: -48.6542,
      );
      final navB = user(
        cityName: 'Navegantes',
        stateName: 'Santa Catarina',
        homeCountryCode: 'br',
        lat: -26.8990,
        lng: -48.6545,
      );
      expect(UserLocationScope.sameCityFromUserData(navA, navB), isTrue);

      // Homônimo distante não entra na Home.
      final saoJoseSc = user(
        cityName: 'São José',
        stateCode: 'SC',
        homeCountryCode: 'br',
        lat: -27.6136,
        lng: -48.6366,
      );
      final saoJoseSp = user(
        cityName: 'São José',
        stateCode: 'SP',
        homeCountryCode: 'br',
        lat: -23.1791,
        lng: -45.8872,
      );
      expect(
        UserLocationScope.sameCityFromUserData(saoJoseSc, saoJoseSp),
        isFalse,
      );
    });

    test('distance below, exactly and above 110 km', () {
      final viewer = user(
        cityName: 'São Paulo',
        stateCode: 'SP',
        homeCountryCode: 'br',
        lat: saoPauloLat,
        lng: saoPauloLng,
      );
      final near = user(
        cityName: 'Campinas',
        stateCode: 'SP',
        homeCountryCode: 'br',
        lat: campinasLat,
        lng: campinasLng,
      );
      final far = user(
        cityName: 'Florianópolis',
        stateCode: 'SC',
        homeCountryCode: 'br',
        lat: florianopolisLat,
        lng: florianopolisLng,
      );

      final dNear = UserLocationScope.distanceKmBetweenUsers(viewer, near)!;
      final dFar = UserLocationScope.distanceKmBetweenUsers(viewer, far)!;
      expect(dNear, lessThan(UserLocationScope.regionRadiusKm));
      expect(dFar, greaterThan(UserLocationScope.regionRadiusKm));
      expect(UserLocationScope.withinRegionRadiusFromUserData(viewer, near), isTrue);
      expect(UserLocationScope.withinRegionRadiusFromUserData(viewer, far), isFalse);

      // Exatamente 110 km: ponto sintético ao norte do viewer.
      final exact = GroupGeo.destinationPoint(
        latitude: saoPauloLat,
        longitude: saoPauloLng,
        distanceKm: 110,
        bearingDeg: 0,
      );
      final at110 = user(
        cityName: 'Ponto110',
        stateCode: 'SP',
        homeCountryCode: 'br',
        lat: exact.latitude,
        lng: exact.longitude,
      );
      final d110 = UserLocationScope.distanceKmBetweenUsers(viewer, at110)!;
      expect(d110, closeTo(110, 1.5));
      expect(
        UserLocationScope.withinRegionRadiusFromUserData(viewer, at110),
        isTrue,
      );

      final overPt = GroupGeo.destinationPoint(
        latitude: saoPauloLat,
        longitude: saoPauloLng,
        distanceKm: 111.5,
        bearingDeg: 0,
      );
      final over = user(
        cityName: 'Ponto111',
        stateCode: 'SP',
        homeCountryCode: 'br',
        lat: overPt.latitude,
        lng: overPt.longitude,
      );
      expect(
        UserLocationScope.withinRegionRadiusFromUserData(viewer, over),
        isFalse,
      );
    });

    test('different UFs within 110 km appear in region; same state beyond does not', () {
      final scBorder = user(
        cityName: 'Dionísio Cerqueira',
        stateCode: 'SC',
        homeCountryCode: 'br',
        lat: dionisioCerqueiraLat,
        lng: dionisioCerqueiraLng,
      );
      final prBorder = user(
        cityName: 'Barracão',
        stateCode: 'PR',
        homeCountryCode: 'br',
        lat: barracaoLat,
        lng: barracaoLng,
      );
      final d = UserLocationScope.distanceKmBetweenUsers(scBorder, prBorder)!;
      expect(d, lessThan(UserLocationScope.regionRadiusKm));
      expect(
        UserLocationScope.withinRegionRadiusFromUserData(scBorder, prBorder),
        isTrue,
      );
      expect(UserLocationScope.sameCityFromUserData(scBorder, prBorder), isFalse);

      // Mesmo estado, longe: Campo Mourão (PR) vs Curitiba (PR).
      final cm = user(
        cityName: 'Campo Mourão',
        stateCode: 'PR',
        homeCountryCode: 'br',
        lat: campoMouraoLat,
        lng: campoMouraoLng,
      );
      final cwb = user(
        cityName: 'Curitiba',
        stateCode: 'PR',
        homeCountryCode: 'br',
        lat: curitibaLat,
        lng: curitibaLng,
      );
      expect(
        UserLocationScope.distanceKmBetweenUsers(cm, cwb)!,
        greaterThan(UserLocationScope.regionRadiusKm),
      );
      expect(UserLocationScope.withinRegionRadiusFromUserData(cm, cwb), isFalse);
    });

    test('COMCAM cities within 110 km match by distance, not admin grouping', () {
      final peabiruUser = user(
        cityName: 'Peabiru',
        stateCode: 'PR',
        homeCountryCode: 'br',
        lat: peabiruLat,
        lng: peabiruLng,
      );
      final campoUser = user(
        cityName: 'Campo Mourão',
        stateName: 'Paraná',
        homeCountryCode: 'br',
        lat: campoMouraoLat,
        lng: campoMouraoLng,
      );
      expect(
        UserLocationScope.withinRegionRadiusFromUserData(peabiruUser, campoUser),
        isTrue,
      );
      // Curitiba (mesmo PR) fora do raio.
      final cwb = user(
        cityName: 'Curitiba',
        stateCode: 'PR',
        homeCountryCode: 'br',
        lat: curitibaLat,
        lng: curitibaLng,
      );
      expect(
        UserLocationScope.withinRegionRadiusFromUserData(peabiruUser, cwb),
        isFalse,
      );
      // Código não usa regionKey/estado para o raio.
      final scope = source('lib/services/user_location_scope.dart');
      expect(scope, isNot(contains('regionKey')));
      expect(scope, contains('regionRadiusKm'));
      expect(scope, contains('GroupGeo.withinRegion'));
    });

    test('BR and CA never match across countries even if coords close in tests', () {
      final br = user(
        cityName: 'São Paulo',
        stateCode: 'SP',
        homeCountryCode: 'br',
        lat: saoPauloLat,
        lng: saoPauloLng,
      );
      final ca = user(
        cityName: 'Toronto',
        stateName: 'Ontario',
        homeCountryCode: 'ca',
        lat: torontoLat,
        lng: torontoLng,
      );
      expect(UserLocationScope.withinRegionRadiusFromUserData(br, ca), isFalse);
      expect(UserLocationScope.sameCityFromUserData(br, ca), isFalse);
    });

    test('legacy lat/lng keys work; no national fallback in UI sources', () {
      final a = user(
        cityName: 'Campinas',
        stateCode: 'SP',
        homeCountryCode: 'br',
        lat: campinasLat,
        lng: campinasLng,
        useCityLatKeys: false,
      );
      expect(UserLocationScope.isDiscoverableProfile(a), isTrue);
      final nearby = source('lib/widgets/home_nearby_users_section.dart');
      final page = source('lib/pages/nearby_users_page.dart');
      expect(nearby, contains('matchesViewerCity'));
      expect(nearby, isNot(contains('strictCity')));
      expect(page, contains('matchesViewerRegion'));
      expect(page, contains('viewerLat'));
      expect(page, isNot(contains('strictCity: false')));
    });
  });

  group('Launch BR+CA and Home copy', () {
    test('BR and CA open; PT and world closed; cross-country blocked', () {
      expect(RemdyLaunchAccess.isCountryOpen('br'), isTrue);
      expect(RemdyLaunchAccess.isCountryOpen('ca'), isTrue);
      expect(RemdyLaunchAccess.isCountryOpen('pt'), isFalse);
      expect(RemdyLaunchAccess.isWorldOpen(), isFalse);
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
          premiumActive: true,
        ),
        isFalse,
      );
    });

    test('Home Em breve is relative to profile homeCountryCode (BR and CA)', () {
      final home = source('lib/pages/home_page.dart');
      expect(home, contains('showsComingSoonOnHome'));
      expect(home, contains('userHomeCountryCode: homeCode'));
      expect(home, isNot(contains('isCanada')));
      expect(home, isNot(contains("code == 'ca'")));

      // BR profile
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

      // CA profile
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
    });

    test('Home shows Mundo (Em breve); unavailable tap blocked', () {
      final home = source('lib/pages/home_page.dart');
      final pt = source('lib/l10n/pt-BR.json');
      expect(home, contains('world_coming_soon'));
      expect(home, contains('canAccessCountryContent'));
      expect(pt, contains('"world_coming_soon": "Mundo (Em breve)"'));
      expect(pt, contains('"live_now": "Agora ao vivo"'));
      expect(RemdyLaunchAccess.isCountryOpen('pt'), isFalse);
    });

    test('pubspec is 1.0.4+29', () {
      expect(source('pubspec.yaml'), contains('version: 1.0.4+29'));
    });
  });
}
