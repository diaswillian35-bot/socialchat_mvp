import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/brazil_states.dart';
import 'package:socialchat_mvp/services/events_brasil_explore_logic.dart';
import 'package:socialchat_mvp/services/events_geo_constants.dart';

void main() {
  group('EVENTS_SURROUNDINGS_RADIUS_KM', () {
    test('é 110 km', () {
      expect(EventsGeoConstants.EVENTS_SURROUNDINGS_RADIUS_KM, 110);
      expect(EventsGeoConstants.eventsSurroundingsRadiusKm, 110);
    });
  });

  group('Arredores (Campo Mourão)', () {
    // Aprox. centros urbanos
    const cmLat = -24.046;
    const cmLng = -52.378;
    const maringaLat = -23.421;
    const maringaLng = -51.933;
    const umuaramaLat = -23.766;
    const umuaramaLng = -53.325;

    test('Maringá (~83 km) entra em Arredores', () {
      final d = EventsBrasilExploreLogic.distanceKm(
        cmLat,
        cmLng,
        maringaLat,
        maringaLng,
      );
      expect(d, lessThanOrEqualTo(110));
      expect(d, greaterThan(50));
      expect(
        EventsBrasilExploreLogic.passesSurroundings(
          userCity: 'Campo Mourão',
          eventCity: 'Maringá',
          userLat: cmLat,
          userLng: cmLng,
          eventLat: maringaLat,
          eventLng: maringaLng,
        ),
        isTrue,
      );
    });

    test('Umuarama (~101 km) entra em Arredores com raio 110', () {
      final d = EventsBrasilExploreLogic.distanceKm(
        cmLat,
        cmLng,
        umuaramaLat,
        umuaramaLng,
      );
      expect(d, greaterThan(100));
      expect(d, lessThanOrEqualTo(110));
      expect(
        EventsBrasilExploreLogic.passesSurroundings(
          userCity: 'Campo Mourão',
          eventCity: 'Umuarama',
          userLat: cmLat,
          userLng: cmLng,
          eventLat: umuaramaLat,
          eventLng: umuaramaLng,
        ),
        isTrue,
      );
    });

    test('exclui mesma cidade mesmo dentro do raio', () {
      expect(
        EventsBrasilExploreLogic.passesSurroundings(
          userCity: 'Campo Mourão',
          eventCity: 'Campo Mourão',
          userLat: cmLat,
          userLng: cmLng,
          eventLat: cmLat,
          eventLng: cmLng,
        ),
        isFalse,
      );
    });

    test('exige lat/lng do usuário e do evento', () {
      expect(
        EventsBrasilExploreLogic.passesSurroundings(
          userCity: 'Campo Mourão',
          eventCity: 'Maringá',
          userLat: null,
          userLng: cmLng,
          eventLat: maringaLat,
          eventLng: maringaLng,
        ),
        isFalse,
      );
      expect(
        EventsBrasilExploreLogic.passesSurroundings(
          userCity: 'Campo Mourão',
          eventCity: 'Maringá',
          userLat: cmLat,
          userLng: cmLng,
          eventLat: null,
          eventLng: maringaLng,
        ),
        isFalse,
      );
    });
  });

  group('Brasil por estado', () {
    BrasilEventRef ev({
      required String id,
      required String state,
      String city = '',
      String title = '',
      DateTime? start,
      bool sponsored = false,
    }) {
      return BrasilEventRef(
        id: id,
        title: title.isEmpty ? id : title,
        city: city,
        stateName: state,
        startAt: start,
        sponsored: sponsored,
      );
    }

    test('lista estados com contagem; usuário primeiro; sem vazios', () {
      final events = [
        ev(id: '1', state: 'São Paulo', city: 'Campinas'),
        ev(id: '2', state: 'SP', city: 'Santos'), // mesmo estado
        ev(id: '3', state: 'Paraná', city: 'Maringá'),
        ev(id: '4', state: 'Paraná', city: 'Curitiba'),
        ev(id: '5', state: 'Santa Catarina', city: 'Joinville'),
        ev(id: 'dup', state: 'Paraná', city: 'Londrina'), // será duplicado
        ev(id: 'dup', state: 'Paraná', city: 'Londrina'),
        ev(id: 'bad', state: '', city: 'SemEstado'),
      ];

      final summaries = EventsBrasilExploreLogic.buildStateSummaries(
        events: events,
        userStateRaw: 'PR',
        preferBrazilCatalog: true,
      );

      expect(summaries.map((s) => s.uf).toList(), ['PR', 'SC', 'SP']);
      expect(summaries.first.name, 'Paraná');
      expect(summaries.first.isUserState, isTrue);
      expect(summaries.first.eventCount, 3); // dup contado 1x
      expect(
        summaries.firstWhere((s) => s.uf == 'SP').eventCount,
        2,
      );
      expect(summaries.any((s) => s.eventCount == 0), isFalse);
    });

    test('eventos do Paraná incluem cidade do usuário', () {
      final events = [
        ev(id: 'cm', state: 'Paraná', city: 'Campo Mourão'),
        ev(id: 'ma', state: 'Paraná', city: 'Maringá'),
        ev(id: 'sp', state: 'São Paulo', city: 'São Paulo'),
      ];
      final pr = EventsBrasilExploreLogic.eventsForState(
        events: events,
        stateKey: 'PR',
      );
      expect(pr.map((e) => e.id), containsAll(['cm', 'ma']));
      expect(pr.map((e) => e.id), isNot(contains('sp')));
    });

    test('busca por cidade e por título', () {
      expect(
        EventsBrasilExploreLogic.matchesCityOrTitle(
          query: 'maringá',
          title: 'Show Sertanejo',
          city: 'Maringá',
        ),
        isTrue,
      );
      expect(
        EventsBrasilExploreLogic.matchesCityOrTitle(
          query: 'sertanejo',
          title: 'Show Sertanejo Night',
          city: 'Curitiba',
        ),
        isTrue,
      );
      expect(
        EventsBrasilExploreLogic.matchesCityOrTitle(
          query: 'xyz',
          title: 'Show',
          city: 'Curitiba',
        ),
        isFalse,
      );
    });

    test('ordenação patrocinado depois data', () {
      final a = DateTime(2026, 8, 10);
      final b = DateTime(2026, 8, 5);
      expect(
        EventsBrasilExploreLogic.compareSponsoredThenStart(
          aSponsored: false,
          bSponsored: true,
          aStart: a,
          bStart: b,
        ),
        greaterThan(0),
      );
      expect(
        EventsBrasilExploreLogic.compareSponsoredThenStart(
          aSponsored: false,
          bSponsored: false,
          aStart: a,
          bStart: b,
        ),
        greaterThan(0),
      );
    });

    test('dedupe por id', () {
      final list = EventsBrasilExploreLogic.dedupeById<BrasilEventRef>(
        [
          ev(id: 'a', state: 'PR'),
          ev(id: 'a', state: 'PR'),
          ev(id: 'b', state: 'PR'),
        ],
        (e) => e.id,
      );
      expect(list.map((e) => e.id).toList(), ['a', 'b']);
    });
  });

  group('BrazilStates', () {
    test('resolve nome e UF', () {
      expect(BrazilStates.resolve('paraná')?.uf, 'PR');
      expect(BrazilStates.resolve('PR')?.name, 'Paraná');
      expect(BrazilStates.resolve('') , isNull);
      expect(BrazilStates.resolve(null), isNull);
    });
  });
}
