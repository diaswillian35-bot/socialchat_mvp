import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/events_geo_constants.dart';
import 'package:socialchat_mvp/services/events_scope_classifier.dart';
import 'package:socialchat_mvp/services/events_brasil_explore_logic.dart';

void main() {
  const radius = EventsGeoConstants.EVENTS_SURROUNDINGS_RADIUS_KM;
  const yorkLat = 43.6956787;
  const yorkLng = -79.4503544;
  const missLat = 43.5890;
  const missLng = -79.6442;
  const ottawaLat = 45.4215;
  const ottawaLng = -75.6972;
  const curitibaLat = -25.4284;
  const curitibaLng = -49.2733;

  EventsClassicScopeBucket classifyCa({
    required String eventCityKey,
    required String eventCityName,
    required double? eventLat,
    required double? eventLng,
    String eventCountry = 'ca',
    String eventScope = 'region',
    double? userLat = yorkLat,
    double? userLng = yorkLng,
  }) {
    return EventsScopeClassifier.classify(
      userCountryCode: 'ca',
      eventCountryCode: eventCountry,
      userCityKey: 'york',
      eventCityKey: eventCityKey,
      userCityName: 'York',
      eventCityName: eventCityName,
      userLat: userLat,
      userLng: userLng,
      eventLat: eventLat,
      eventLng: eventLng,
      eventScope: eventScope,
    );
  }

  double lngAtKm(double targetKm) {
    var lo = yorkLng;
    var hi = yorkLng + 3.0;
    for (var i = 0; i < 48; i++) {
      final mid = (lo + hi) / 2;
      final d = EventsBrasilExploreLogic.distanceKm(
        yorkLat,
        yorkLng,
        yorkLat,
        mid,
      );
      if (d < targetKm) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return hi;
  }

  group('matriz exclusiva York', () {
    test('1 mesma cidade → somente Cidade', () {
      final b = classifyCa(
        eventCityKey: 'york',
        eventCityName: 'York',
        eventLat: yorkLat,
        eventLng: yorkLng,
      );
      expect(b, EventsClassicScopeBucket.city);
      expect(
        EventsScopeClassifier.matchesSelectedScope(
          bucket: b,
          selectedScopeIndex: 0,
        ),
        isTrue,
      );
      expect(
        EventsScopeClassifier.matchesSelectedScope(
          bucket: b,
          selectedScopeIndex: 1,
        ),
        isFalse,
      );
      expect(
        EventsScopeClassifier.matchesSelectedScope(
          bucket: b,
          selectedScopeIndex: 2,
        ),
        isFalse,
      );
    });

    test('2 Mississauga 19,60 km → somente Arredores', () {
      final d = EventsBrasilExploreLogic.distanceKm(
        yorkLat,
        yorkLng,
        missLat,
        missLng,
      );
      expect(d, closeTo(19.60, 0.05));
      final b = classifyCa(
        eventCityKey: 'mississauga',
        eventCityName: 'Mississauga',
        eventLat: missLat,
        eventLng: missLng,
      );
      expect(b, EventsClassicScopeBucket.surroundings);
      expect(
        EventsScopeClassifier.matchesSelectedScope(
          bucket: b,
          selectedScopeIndex: 2,
        ),
        isFalse,
      );
    });

    test('3 109,99 km → somente Arredores', () {
      final lng = lngAtKm(109.99);
      final b = classifyCa(
        eventCityKey: 'edge99',
        eventCityName: 'Edge99',
        eventLat: yorkLat,
        eventLng: lng,
      );
      expect(b, EventsClassicScopeBucket.surroundings);
    });

    test('4 exatamente 110 km → somente Arredores', () {
      // Aproxima o limiar inclusivo (<= radius).
      final lng = lngAtKm(radius - 0.001);
      final d = EventsBrasilExploreLogic.distanceKm(
        yorkLat,
        yorkLng,
        yorkLat,
        lng,
      );
      expect(d, lessThanOrEqualTo(radius));
      expect(d, greaterThan(radius - 0.05));
      final b = classifyCa(
        eventCityKey: 'edge110',
        eventCityName: 'Edge110',
        eventLat: yorkLat,
        eventLng: lng,
      );
      expect(b, EventsClassicScopeBucket.surroundings);
    });

    test('5 110,01 km → somente País', () {
      final lng = lngAtKm(110.01);
      final d = EventsBrasilExploreLogic.distanceKm(
        yorkLat,
        yorkLng,
        yorkLat,
        lng,
      );
      expect(d, greaterThan(radius));
      final b = classifyCa(
        eventCityKey: 'far01',
        eventCityName: 'Far01',
        eventLat: yorkLat,
        eventLng: lng,
      );
      expect(b, EventsClassicScopeBucket.country);
      expect(
        EventsScopeClassifier.matchesSelectedScope(
          bucket: b,
          selectedScopeIndex: 1,
        ),
        isFalse,
      );
    });

    test('6 Ottawa distante → País / Ontario', () {
      final b = classifyCa(
        eventCityKey: 'ottawa',
        eventCityName: 'Ottawa',
        eventLat: ottawaLat,
        eventLng: ottawaLng,
      );
      expect(b, EventsClassicScopeBucket.country);
      final summaries = EventsBrasilExploreLogic.buildStateSummaries(
        events: [
          BrasilEventRef(
            id: 'ott',
            title: 'Ottawa Night',
            city: 'Ottawa',
            stateName: 'Ontario',
          ),
        ],
        userStateRaw: 'Ontario',
        preferBrazilCatalog: false,
      );
      expect(summaries.single.name, 'Ontario');
    });

    test('7 evento BR para perfil CA → fora', () {
      final b = classifyCa(
        eventCityKey: 'curitiba',
        eventCityName: 'Curitiba',
        eventLat: curitibaLat,
        eventLng: curitibaLng,
        eventCountry: 'br',
      );
      expect(b, EventsClassicScopeBucket.outOfCountry);
      for (final i in [0, 1, 2]) {
        expect(
          EventsScopeClassifier.matchesSelectedScope(
            bucket: b,
            selectedScopeIndex: i,
          ),
          isFalse,
        );
      }
    });

    test('8 evento CA para perfil BR → fora', () {
      final b = EventsScopeClassifier.classify(
        userCountryCode: 'br',
        eventCountryCode: 'ca',
        userCityKey: 'curitiba',
        eventCityKey: 'mississauga',
        userCityName: 'Curitiba',
        eventCityName: 'Mississauga',
        userLat: curitibaLat,
        userLng: curitibaLng,
        eventLat: missLat,
        eventLng: missLng,
      );
      expect(b, EventsClassicScopeBucket.outOfCountry);
    });

    test('9 usuário sem coords → needs location; cidade ainda classifica', () {
      expect(
        EventsScopeClassifier.userNeedsLocationForGeoScopes(
          userLat: null,
          userLng: null,
        ),
        isTrue,
      );
      final city = classifyCa(
        eventCityKey: 'york',
        eventCityName: 'York',
        eventLat: yorkLat,
        eventLng: yorkLng,
        userLat: null,
        userLng: null,
      );
      expect(city, EventsClassicScopeBucket.city);

      final nearby = classifyCa(
        eventCityKey: 'mississauga',
        eventCityName: 'Mississauga',
        eventLat: missLat,
        eventLng: missLng,
        userLat: null,
        userLng: null,
      );
      expect(nearby, EventsClassicScopeBucket.unclassifiable);
    });

    test('10 evento sem coords → não classificado como distante', () {
      final b = classifyCa(
        eventCityKey: 'somewhere',
        eventCityName: 'Somewhere',
        eventLat: null,
        eventLng: null,
        eventScope: 'region',
      );
      expect(b, EventsClassicScopeBucket.unclassifiable);
      expect(
        EventsScopeClassifier.matchesSelectedScope(
          bucket: b,
          selectedScopeIndex: 2,
        ),
        isFalse,
      );
    });

    test('11 scope:country → País (contrato nacional)', () {
      final b = classifyCa(
        eventCityKey: '',
        eventCityName: '',
        eventLat: null,
        eventLng: null,
        eventScope: 'country',
      );
      expect(b, EventsClassicScopeBucket.country);
    });

    test('12 coords inválidas → rejeitadas', () {
      final b = classifyCa(
        eventCityKey: 'bad',
        eventCityName: 'Bad',
        eventLat: 999,
        eventLng: -79.0,
      );
      expect(b, EventsClassicScopeBucket.unclassifiable);
    });

    test('14 dedupe: cada evento um único escopo local', () {
      final samples = <EventsClassicScopeBucket>{
        classifyCa(
          eventCityKey: 'york',
          eventCityName: 'York',
          eventLat: yorkLat,
          eventLng: yorkLng,
        ),
        classifyCa(
          eventCityKey: 'mississauga',
          eventCityName: 'Mississauga',
          eventLat: missLat,
          eventLng: missLng,
        ),
        classifyCa(
          eventCityKey: 'ottawa',
          eventCityName: 'Ottawa',
          eventLat: ottawaLat,
          eventLng: ottawaLng,
        ),
      };
      expect(samples.length, 3);
      expect(samples.contains(EventsClassicScopeBucket.city), isTrue);
      expect(samples.contains(EventsClassicScopeBucket.surroundings), isTrue);
      expect(samples.contains(EventsClassicScopeBucket.country), isTrue);
    });
  });

  group('custo / paginação', () {
    test('15 explore page size ≥ 300 (não limit 50)', () {
      expect(EventsGeoConstants.publicExplorePageSize, greaterThanOrEqualTo(300));
      expect(EventsGeoConstants.publicExplorePageSizeMax, greaterThanOrEqualTo(300));
    });
  });
}
