import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/data/demo_places.dart';
import 'package:socialchat_mvp/features/locais/locais_feature_flag.dart';
import 'package:socialchat_mvp/features/locais/logic/place_query.dart';
import 'package:socialchat_mvp/features/locais/models/place_listing.dart';
import 'package:socialchat_mvp/features/locais/ui/locais_detail_page.dart';

import 'locais_test_support.dart';

void main() {
  tearDown(LocaisFeatureFlag.resetDebugOverride);

  const engine = PlaceQueryEngine();
  final now = locaisDemoClock();

  group('Filtros do contrato local', () {
    test('busca cidade, região e bairro sem acento', () {
      final paulo = engine.apply(
        source: DemoPlaces.all,
        query: const PlaceQuery(search: 'sao paulo'),
        now: now,
      );
      expect(paulo.map((place) => place.id), ['aurora_club', 'cafe_da_se']);

      final ontario = engine.apply(
        source: DemoPlaces.all,
        query: const PlaceQuery(search: 'Ontario'),
        now: now,
      );
      expect(ontario.single.id, 'cafe_atlantico');

      final ponta = engine.apply(
        source: DemoPlaces.all,
        query: const PlaceQuery(search: 'Ponta Negra'),
        now: now,
      );
      expect(ponta.single.id, 'pousada_dunas');
    });

    test('categoria, aberto agora, nota e entrada acessível', () {
      expect(now.weekday, DateTime.wednesday);
      final night = engine.apply(
        source: DemoPlaces.all,
        query: const PlaceQuery(category: PlaceCategory.nightclub),
        now: now,
      );
      expect(night.single.id, 'aurora_club');
      expect(night.single.isOpenAt(now), isFalse);
      expect(night.single.isOpenAt(DateTime(2026, 10, 14, 23)), isTrue);

      final open = engine.apply(
        source: DemoPlaces.all,
        query: const PlaceQuery(openNow: true),
        now: now,
      );
      expect(open.map((place) => place.id), isNot(contains('bar_do_cais')));
      expect(open.map((place) => place.id), isNot(contains('aurora_club')));
      expect(open.map((place) => place.id), contains('casa_do_sabor'));

      final rated = engine.apply(
        source: DemoPlaces.all,
        query: const PlaceQuery(minRating: 4.8),
        now: now,
      );
      expect(rated.map((place) => place.id), [
        'cafe_atlantico',
        'pousada_dunas',
      ]);

      final access = engine.apply(
        source: DemoPlaces.all,
        query: const PlaceQuery(openNow: true, wheelchairEntrance: true),
        now: now,
      );
      expect(
        access.every((place) => place.accessibility.wheelchairEntrance),
        isTrue,
      );
      expect(access.map((place) => place.id), isNot(contains('pousada_dunas')));
    });

    test('busca sem resultado', () {
      final empty = engine.apply(
        source: DemoPlaces.all,
        query: const PlaceQuery(search: 'Antártica'),
        now: now,
      );
      expect(empty, isEmpty);
    });

    test('roundtrip places.v1 e recusa de url insegura', () {
      final place = DemoPlaces.all.first;
      final again = PlaceListing.fromPortalJson(place.toPortalJson());
      expect(again.id, place.id);
      expect(again.category, PlaceCategory.restaurant);
      expect(again.toPortalJson()['contract'], 'places.v1');

      final broken = place.toPortalJson();
      final photos = (broken['photos'] as List).cast<Map<String, dynamic>>();
      photos[0] = {...photos[0], 'url': 'http://inseguro.example/foto.jpg'};
      expect(
        () => PlaceListing.fromPortalJson(broken),
        throwsA(isA<PlaceContractException>()),
      );
    });
  });

  testWidgets('busca, categoria, filtro e estado vazio na lista', (
    tester,
  ) async {
    await pumpLocais(tester, demoList());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('place_card_casa_do_sabor')), findsOneWidget);
    expect(find.byKey(const Key('place_card_bar_do_cais')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('locais_search')), 'Lisboa');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('place_card_bar_do_cais')), findsOneWidget);
    expect(find.byKey(const Key('place_card_casa_do_sabor')), findsNothing);

    await tester.tap(find.byKey(const Key('locais_clear_filters')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const Key('locais_category_nightclub')),
    );
    await tester.tap(find.byKey(const Key('locais_category_nightclub')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('place_card_aurora_club')), findsOneWidget);
    expect(find.byKey(const Key('place_card_casa_do_sabor')), findsNothing);
    expect(find.text('Fechado'), findsOneWidget);

    await tester.tap(find.byKey(const Key('locais_category_all')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('locais_filter_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('locais_filter_open_now')));
    await tester.tap(find.byKey(const Key('locais_filter_rating_45')));
    await tester.tap(find.byKey(const Key('locais_filter_apply')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('place_card_cafe_atlantico')), findsOneWidget);
    expect(find.byKey(const Key('place_card_aurora_club')), findsNothing);
    expect(find.byKey(const Key('place_card_bar_do_cais')), findsNothing);

    await tester.enterText(find.byKey(const Key('locais_search')), 'Antártica');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('locais_empty')), findsOneWidget);
    expect(find.byKey(const Key('place_card_casa_do_sabor')), findsNothing);
  });

  testWidgets('carregando, erro e tentar novamente', (tester) async {
    await pumpLocais(
      tester,
      demoList(
        latency: const Duration(milliseconds: 40),
        failure: StateError('falha'),
      ),
    );
    expect(find.byKey(const Key('locais_loading')), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('locais_error')), findsOneWidget);
    expect(find.byKey(const Key('locais_retry')), findsOneWidget);

    await pumpLocais(
      tester,
      LocaisDetailPage(
        placeId: 'ausente',
        repository: demoRepository(),
        clock: locaisDemoClock,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('locais_empty')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
