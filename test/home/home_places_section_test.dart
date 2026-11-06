import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/data/demo_places.dart';
import 'package:socialchat_mvp/features/locais/data/place_repository.dart';
import 'package:socialchat_mvp/features/locais/locais_feature_flag.dart';
import 'package:socialchat_mvp/features/locais/locais_strings.dart';
import 'package:socialchat_mvp/features/locais/ui/locais_detail_page.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';
import 'package:socialchat_mvp/widgets/home_places_section.dart';

DateTime _clock() => DateTime(2026, 10, 14, 15);

Future<void> _pump(WidgetTester tester, Widget child, {bool enabled = true}) async {
  tester.view.physicalSize = const Size(390, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  LocaisFeatureFlag.debugOverride = enabled;
  LocaisStrings.debugLocale = const Locale('pt', 'BR');
  addTearDown(LocaisFeatureFlag.resetDebugOverride);
  addTearDown(LocaisStrings.resetDebugLocale);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
  await tester.pump();
}

void main() {
  setUp(() {
    final map = Map<String, dynamic>.from(
        jsonDecode(File('lib/l10n/pt-BR.json').readAsStringSync()) as Map);
    AppTexts.loadFromMap(map, const Locale('pt', 'BR'));
  });

  test('l10n: home_places_near_you nos 5 idiomas', () {
    const expected = {
      'pt-BR': 'Locais perto de você',
      'pt-PT': 'Locais perto de si',
      'en': 'Places near you',
      'es': 'Lugares cerca de ti',
      'fr': 'Lieux près de chez vous',
    };
    expected.forEach((lang, value) {
      final m = jsonDecode(File('lib/l10n/$lang.json').readAsStringSync()) as Map;
      expect(m['home_places_near_you'], value, reason: lang);
    });
  });

  test('selectHomePlaces: país, cidade primeiro, abertos, máximo', () {
    final all = DemoPlaces.all;
    final br = selectHomePlaces(all, countryCode: 'br', now: _clock());
    expect(br, isNotEmpty);
    expect(br.every((p) => p.address.countryCode == 'BR'), isTrue);
    final rio = selectHomePlaces(all,
        countryCode: 'BR', city: 'rio de janeiro', now: _clock());
    expect(rio.first.address.city, 'Rio de Janeiro');
    final one = selectHomePlaces(all, countryCode: 'BR', now: _clock(), limit: 1);
    expect(one.length, 1);
    expect(selectHomePlaces(all, countryCode: 'ZZ', now: _clock()), isEmpty);
    // Sem cidade: abertos agora vêm antes dos fechados.
    var seenClosed = false;
    for (final p in br) {
      final open = p.isOpenAt(_clock());
      if (!open) seenClosed = true;
      if (open) expect(seenClosed, isFalse);
    }
  });

  testWidgets('mostra cabeçalho, cards, Ver todos e abre a ficha', (tester) async {
    var openedTab = 0;
    await _pump(
      tester,
      HomePlacesSection(
        countryCode: 'CA',
        city: 'Toronto',
        repository: DemoPlaceRepository(),
        clock: _clock,
        onOpenLocaisTab: () => openedTab++,
      ),
    );
    expect(find.text('Locais perto de você'), findsOneWidget);
    expect(find.byKey(const Key('place_card_cafe_atlantico')), findsOneWidget);
    await tester.tap(find.text('Ver todos'));
    expect(openedTab, 1);
    await tester.tap(find.byKey(const Key('place_card_cafe_atlantico')));
    await tester.pumpAndSettle();
    expect(find.byType(LocaisDetailPage), findsOneWidget);
  });

  testWidgets('some com 0 locais', (tester) async {
    await _pump(
      tester,
      HomePlacesSection(
        countryCode: 'ZZ',
        repository: DemoPlaceRepository(),
        clock: _clock,
      ),
    );
    expect(find.byKey(const Key('home_places_section')), findsNothing);
    expect(find.text('Locais perto de você'), findsNothing);
  });

  testWidgets('some com Locais desligado (sem leitura)', (tester) async {
    await _pump(
      tester,
      HomePlacesSection(
        countryCode: 'CA',
        repository: DemoPlaceRepository(failure: StateError('não deveria ler')),
        clock: _clock,
      ),
      enabled: false,
    );
    expect(find.byKey(const Key('home_places_section')), findsNothing);
  });

  testWidgets('erro de leitura esconde a seção', (tester) async {
    await _pump(
      tester,
      HomePlacesSection(
        countryCode: 'CA',
        repository: DemoPlaceRepository(failure: const PlaceAccessBlocked()),
        clock: _clock,
      ),
    );
    expect(find.byKey(const Key('home_places_section')), findsNothing);
  });
}
