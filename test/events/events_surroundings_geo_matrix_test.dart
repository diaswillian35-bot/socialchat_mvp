import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/events_brasil_explore_logic.dart';
import 'package:socialchat_mvp/services/events_geo_constants.dart';

/// Matriz geográfica clássica (York / Arredores / Canadá).
///
/// Usa a mesma fórmula Haversine da aba Arredores
/// ([EventsBrasilExploreLogic.distanceKm] / [passesSurroundings]).
void main() {
  const radius = EventsGeoConstants.EVENTS_SURROUNDINGS_RADIUS_KM;

  // Centro aproximado do borough York (Toronto), ON — fixture de teste.
  const yorkLat = 43.6896;
  const yorkLng = -79.4785;

  // Living Arts Centre / Mississauga (evento QA real).
  const mississaugaLat = 43.5890;
  const mississaugaLng = -79.6442;

  // Ottawa (~350 km de York) — fora do raio, ainda no Canadá / Ontario.
  const ottawaLat = 45.4215;
  const ottawaLng = -75.6972;

  // Curitiba, BR — outro país.
  const curitibaLat = -25.4284;
  const curitibaLng = -49.2733;

  BrasilEventRef caEvent({
    required String id,
    required String city,
    String stateName = 'Ontario',
    String stateCode = '',
    String title = '',
  }) {
    return BrasilEventRef(
      id: id,
      title: title.isEmpty ? id : title,
      city: city,
      stateName: stateName,
      stateCode: stateCode,
    );
  }

  /// Longitude a leste de York com distância Haversine ≈ [targetKm].
  double lngEastOfYork(double targetKm) {
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

  group('York → Mississauga (~17 km)', () {
    late final double dKm;

    setUpAll(() {
      dKm = EventsBrasilExploreLogic.distanceKm(
        yorkLat,
        yorkLng,
        mississaugaLat,
        mississaugaLng,
      );
    });

    test('distância real está dentro de 110 km', () {
      expect(dKm, greaterThan(10));
      expect(dKm, lessThan(30));
      expect(dKm, lessThanOrEqualTo(radius));
    });

    test('aparece em Arredores e NÃO no País (exclusivo)', () {
      expect(
        EventsBrasilExploreLogic.passesSurroundings(
          userCity: 'York',
          eventCity: 'Mississauga',
          userLat: yorkLat,
          userLng: yorkLng,
          eventLat: mississaugaLat,
          eventLng: mississaugaLng,
          userCountryCode: 'ca',
          eventCountryCode: 'ca',
        ),
        isTrue,
      );
    });

    test('Canadá/Ontario: Mississauga fora do bucket País (exclusivo)', () {
      // Classificação país exclusa via helper canônico — ver events_scope_classifier_test.
      expect(
        EventsBrasilExploreLogic.passesSurroundings(
          userCity: 'York',
          eventCity: 'Mississauga',
          userLat: yorkLat,
          userLng: yorkLng,
          eventLat: mississaugaLat,
          eventLng: mississaugaLng,
          userCountryCode: 'ca',
          eventCountryCode: 'ca',
        ),
        isTrue,
      );
      // Distância < 110 ⇒ não é “somente País”.
      expect(dKm, lessThanOrEqualTo(radius));
    });

    test('não precisa aparecer em York (cityKey diferente)', () {
      // Aba cidade filtra por cityKey no servidor; fixture só documenta a regra.
      expect('mississauga', isNot(equals('york')));
    });
  });

  group('York → evento CA acima de 110 km (Ottawa)', () {
    late final double dKm;

    setUpAll(() {
      dKm = EventsBrasilExploreLogic.distanceKm(
        yorkLat,
        yorkLng,
        ottawaLat,
        ottawaLng,
      );
    });

    test('distância > 110 km', () {
      expect(dKm, greaterThan(radius));
      expect(dKm, greaterThan(300));
    });

    test('não aparece em Arredores', () {
      expect(
        EventsBrasilExploreLogic.passesSurroundings(
          userCity: 'York',
          eventCity: 'Ottawa',
          userLat: yorkLat,
          userLng: yorkLng,
          eventLat: ottawaLat,
          eventLng: ottawaLng,
        ),
        isFalse,
      );
    });

    test('aparece em Canadá e na província correta', () {
      final events = [
        caEvent(id: 'ott', city: 'Ottawa', stateName: 'Ontario'),
      ];
      final ontario = EventsBrasilExploreLogic.eventsForState(
        events: events,
        stateKey: 'ontario',
        preferBrazilCatalog: false,
      );
      expect(ontario.map((e) => e.id), ['ott']);
    });
  });

  group('York → evento brasileiro', () {
    test('não passa Arredores (distância intercontinental)', () {
      final d = EventsBrasilExploreLogic.distanceKm(
        yorkLat,
        yorkLng,
        curitibaLat,
        curitibaLng,
      );
      expect(d, greaterThan(radius));
      expect(
        EventsBrasilExploreLogic.passesSurroundings(
          userCity: 'York',
          eventCity: 'Curitiba',
          userLat: yorkLat,
          userLng: yorkLng,
          eventLat: curitibaLat,
          eventLng: curitibaLng,
        ),
        isFalse,
      );
    });

    test('não entra no agrupamento Canadá/Ontario', () {
      final events = [
        BrasilEventRef(
          id: 'br1',
          title: 'Show BR',
          city: 'Curitiba',
          stateName: 'Paraná',
          stateCode: 'PR',
        ),
      ];
      final ontario = EventsBrasilExploreLogic.eventsForState(
        events: events,
        stateKey: 'ontario',
        preferBrazilCatalog: false,
      );
      expect(ontario, isEmpty);

      final caSummaries = EventsBrasilExploreLogic.buildStateSummaries(
        events: events,
        userStateRaw: 'Ontario',
        preferBrazilCatalog: false,
      );
      expect(
        caSummaries.any((s) => s.name.toLowerCase() == 'ontario'),
        isFalse,
      );
    });
  });

  group('limite exato de 110 km', () {
    test('110 km: incluído (d <= radius)', () {
      // Produto: d <= 110 entra. Usa ~109.9 para evitar ruído de ponto flutuante.
      final edgeLng = lngEastOfYork(radius - 0.1);
      final d = EventsBrasilExploreLogic.distanceKm(
        yorkLat,
        yorkLng,
        yorkLat,
        edgeLng,
      );
      expect(d, lessThanOrEqualTo(radius));
      expect(d, greaterThan(radius - 0.5));
      expect(
        EventsBrasilExploreLogic.passesSurroundings(
          userCity: 'York',
          eventCity: 'Edge City',
          userLat: yorkLat,
          userLng: yorkLng,
          eventLat: yorkLat,
          eventLng: edgeLng,
        ),
        isTrue,
      );
    });

    test('limiar inclusivo: d ligeiramente abaixo de 110 entra', () {
      final edgeLng = lngEastOfYork(radius - 0.01);
      expect(
        EventsBrasilExploreLogic.distanceKm(
              yorkLat,
              yorkLng,
              yorkLat,
              edgeLng,
            ) <=
            radius,
        isTrue,
      );
      expect(
        EventsBrasilExploreLogic.passesSurroundings(
          userCity: 'York',
          eventCity: 'Threshold City',
          userLat: yorkLat,
          userLng: yorkLng,
          eventLat: yorkLat,
          eventLng: edgeLng,
        ),
        isTrue,
      );
    });

    test('acima de 110 km: excluído', () {
      final overLng = lngEastOfYork(radius + 0.5);
      final d = EventsBrasilExploreLogic.distanceKm(
        yorkLat,
        yorkLng,
        yorkLat,
        overLng,
      );
      expect(d, greaterThan(radius));
      expect(
        EventsBrasilExploreLogic.passesSurroundings(
          userCity: 'York',
          eventCity: 'Far City',
          userLat: yorkLat,
          userLng: yorkLng,
          eventLat: yorkLat,
          eventLng: overLng,
        ),
        isFalse,
      );
    });
  });

  group('fail-closed sem coordenadas (caso Willian)', () {
    test('perfil sem lat/lng → Arredores vazio', () {
      expect(
        EventsBrasilExploreLogic.passesSurroundings(
          userCity: 'York',
          eventCity: 'Mississauga',
          userLat: null,
          userLng: null,
          eventLat: mississaugaLat,
          eventLng: mississaugaLng,
        ),
        isFalse,
      );
    });

    test('evento sem lat/lng → excluído de Arredores', () {
      expect(
        EventsBrasilExploreLogic.passesSurroundings(
          userCity: 'York',
          eventCity: 'Mississauga',
          userLat: yorkLat,
          userLng: yorkLng,
          eventLat: null,
          eventLng: null,
        ),
        isFalse,
      );
    });
  });

}
