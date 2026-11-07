import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/data/place_repository.dart';
import 'package:socialchat_mvp/features/locais/locais_feature_flag.dart';
import 'package:socialchat_mvp/features/locais/locais_strings.dart';
import 'package:socialchat_mvp/features/locais/models/place_listing.dart';
import 'package:socialchat_mvp/features/locais/ui/place_card.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';
import 'package:socialchat_mvp/widgets/home_discover_section.dart';
import 'package:socialchat_mvp/widgets/home_paged_carousel.dart';
import 'package:socialchat_mvp/widgets/home_places_section.dart';

class _Item {
  const _Item(this.id, this.owner, {this.featured = false});
  final String id;
  final String owner;
  final bool featured;
}

class _FeaturedRepo extends DemoPlaceRepository {
  _FeaturedRepo(this.featuredId);
  final String featuredId;
  @override
  Future<List<PlaceListing>> fetchCatalog() async => [
        for (final p in await super.fetchCatalog())
          p.id == featuredId ? p.copyWith(promotionScore: 200) : p,
      ];
}

DateTime _clock() => DateTime(2026, 10, 14, 15);

void main() {
  setUp(() {
    final map = Map<String, dynamic>.from(
        jsonDecode(File('lib/l10n/pt-BR.json').readAsStringSync()) as Map);
    AppTexts.loadFromMap(map, const Locale('pt', 'BR'));
  });

  test('l10n: home_featured_badge nos 5 idiomas', () {
    const expected = {
      'pt-BR': 'Destaque',
      'pt-PT': 'Destaque',
      'en': 'Featured',
      'es': 'Destacado',
      'fr': 'À la une',
    };
    expected.forEach((lang, value) {
      final m =
          jsonDecode(File('lib/l10n/$lang.json').readAsStringSync()) as Map;
      expect(m['home_featured_badge'], value, reason: lang);
    });
  });

  test('ordem: destaques na frente, sem repetidos, donos diferentes por página',
      () {
    const items = [
      _Item('a', 'x'),
      _Item('b', 'x'),
      _Item('a', 'x'), // repetido
      _Item('c', 'y'),
      _Item('d', 'z', featured: true),
      _Item('e', 'w'),
    ];
    final out = homeCarouselOrder<_Item>(
      items,
      idOf: (i) => i.id,
      ownerOf: (i) => i.owner,
      isFeatured: (i) => i.featured,
    );
    expect(out.map((i) => i.id), ['d', 'a', 'c', 'b', 'e']);
    // 1ª página (d, a, c): 3 donos diferentes.
    expect(out.take(3).map((i) => i.owner).toSet().length, 3);
  });

  test('score de destaque dos eventos', () {
    expect(homeEventPromotionScore({'sponsored': true}), 300);
    expect(homeEventPromotionScore({'featured': true}), 200);
    expect(homeEventPromotionScore({'promotionPriority': 5}), 105);
    expect(homeEventPromotionScore({'sponsored': false, 'featured': false}), 0);
    expect(homeEventOwnerKey({'createdBy': 'u1'}), 'u1');
  });

  test('capa: logo quadrada/retrato em capa larga não corta (contain)', () {
    expect(placeCoverFit(imageAspect: 1, boxAspect: 220 / 112), BoxFit.contain);
    expect(placeCoverFit(imageAspect: 1, boxAspect: 130 / 112), BoxFit.contain);
    expect(placeCoverFit(imageAspect: 0.8, boxAspect: 1.2), BoxFit.contain);
    expect(placeCoverFit(imageAspect: 1.5, boxAspect: 220 / 112), BoxFit.cover);
    expect(
        placeCoverFit(imageAspect: 16 / 9, boxAspect: 130 / 112), BoxFit.cover);
    expect(placeCoverFit(imageAspect: 1, boxAspect: 104 / 112), BoxFit.cover);
  });

  Future<void> pumpCarousel(WidgetTester tester, int count) async {
    tester.view.physicalSize = const Size(440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: HomePagedCarousel(
            itemCount: count,
            height: 200,
            itemBuilder: (_, i) => Container(
              key: Key('item_$i'),
              color: Colors.white,
            ),
          ),
        ),
      ),
    ));
  }

  testWidgets('3 cards por vez e passa de 3 em 3', (tester) async {
    await pumpCarousel(tester, 7);
    expect(HomePagedCarousel.pageCountFor(7, 3), 3);
    for (var i = 0; i < 3; i++) {
      expect(find.byKey(Key('item_$i')), findsOneWidget);
    }
    expect(find.byKey(const Key('item_3')), findsNothing);
    // Mesma largura nos 3 (iPhone 16 Pro Max: 440 - 32 de margem).
    final w0 = tester.getSize(find.byKey(const Key('item_0'))).width;
    expect(w0, closeTo((408 - 16) / 3, 0.5));
    expect(find.byKey(const Key('home_paged_carousel_dots')), findsOneWidget);

    await tester.fling(find.byKey(const Key('home_paged_carousel')),
        const Offset(-300, 0), 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item_0')), findsNothing);
    for (var i = 3; i < 6; i++) {
      expect(find.byKey(Key('item_$i')), findsOneWidget);
    }

    await tester.fling(find.byKey(const Key('home_paged_carousel')),
        const Offset(-300, 0), 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('item_6')), findsOneWidget);
    // Última página incompleta: card do mesmo tamanho, não esticado.
    expect(tester.getSize(find.byKey(const Key('item_6'))).width,
        closeTo(w0, 0.5));
  });

  testWidgets('até 3 itens: sem pontos', (tester) async {
    await pumpCarousel(tester, 2);
    expect(find.byKey(const Key('home_paged_carousel_dots')), findsNothing);
    expect(find.byKey(const Key('item_1')), findsOneWidget);
  });

  testWidgets('Locais: destaque na frente com selo Destaque', (tester) async {
    tester.view.physicalSize = const Size(440, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    LocaisFeatureFlag.debugOverride = true;
    LocaisStrings.debugLocale = const Locale('pt', 'BR');
    addTearDown(LocaisFeatureFlag.resetDebugOverride);
    addTearDown(LocaisStrings.resetDebugLocale);
    final catalog = await DemoPlaceRepository().fetchCatalog();
    final normal = selectHomePlaces(catalog, countryCode: 'BR', now: _clock());
    expect(normal.length, greaterThan(1));
    final target = normal.last.id;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: HomePlacesSection(
            countryCode: 'BR',
            repository: _FeaturedRepo(target),
            clock: _clock,
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byKey(Key('place_card_$target')), findsOneWidget);
    expect(find.text('Destaque'), findsOneWidget);
    expect(find.byKey(const Key('home_places_carousel')), findsOneWidget);
  });
}
