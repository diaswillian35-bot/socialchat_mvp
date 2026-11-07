import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';
import 'package:socialchat_mvp/features/locais/data/place_description_translation_service.dart';
import 'package:socialchat_mvp/features/locais/locais_feature_flag.dart';
import 'package:socialchat_mvp/features/locais/ui/place_description.dart';
import 'package:socialchat_mvp/features/locais/ui/locais_detail_page.dart';
import 'package:socialchat_mvp/features/locais/ui/locais_layout.dart';
import 'package:socialchat_mvp/features/locais/data/demo_places.dart';
import 'locais_test_support.dart';

Map<String, dynamic> translated(Map<String, dynamic> data,
        [String text = 'Translated description']) =>
    {
      'translated': true,
      'text': text,
      'sourceHash': data['sourceHash'],
      'targetLanguage': data['language'],
    };
void main() {
  setUp(() {
    LocaisFeatureFlag.debugOverride = true;
  });
  tearDown(LocaisFeatureFlag.resetDebugOverride);
  const locales = {
    'pt-BR': Locale('pt', 'BR'),
    'pt-PT': Locale('pt', 'PT'),
    'en': Locale('en'),
    'es': Locale('es'),
    'fr': Locale('fr')
  };
  for (final entry in locales.entries) {
    testWidgets('toggle, style and no retranslating in ${entry.key}',
        (tester) async {
      final catalog =
          jsonDecode(File('lib/l10n/${entry.key}.json').readAsStringSync())
              as Map<String, dynamic>;
      AppTexts.loadFromMap(catalog, entry.value);
      var calls = 0;
      final service = PlaceDescriptionTranslationService(call: (data) async {
        calls++;
        return translated(data);
      });
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PlaceDescription(
                  placeId: 'JohnID',
                  original: 'Original description',
                  locale: entry.value,
                  service: service))));
      await tester.pumpAndSettle();
      expect(find.text('Translated description'), findsOneWidget);
      expect(find.text(catalog['place_view_original']), findsOneWidget);
      final text =
          tester.widget<Text>(find.byKey(const Key('place_description_text')));
      expect(
          text.style, const TextStyle(color: LocaisColors.text, height: 1.4));
      await tester.tap(find.byKey(const Key('place_description_toggle')));
      await tester.pump();
      expect(find.text('Original description'), findsOneWidget);
      expect(find.text(catalog['place_view_translation']), findsOneWidget);
      await tester.tap(find.byKey(const Key('place_description_toggle')));
      await tester.pump();
      expect(find.text('Translated description'), findsOneWidget);
      expect(calls, 1);
    });
  }
  test(
      'service coalesces, caches by source hash and shares Portuguese variants',
      () async {
    var calls = 0;
    final service = PlaceDescriptionTranslationService(call: (d) async {
      calls++;
      return translated(d);
    });
    await Future.wait(List.generate(
        10, (_) => service.load('JohnID', 'Original', const Locale('en'))));
    expect(calls, 1);
    await service.load('JohnID', 'Changed', const Locale('en'));
    expect(calls, 2);
    await service.load('JohnID', 'Changed', const Locale('pt', 'BR'));
    await service.load('JohnID', 'Changed', const Locale('pt', 'PT'));
    expect(calls, 3);
  });
  for (final mode in [
    'same_language',
    'disabled',
    'quota',
    'offline',
    'stale'
  ]) {
    testWidgets('$mode displays original without toggle', (tester) async {
      final service = PlaceDescriptionTranslationService(call: (d) async {
        if (mode == 'offline') throw Exception('offline');
        if (mode == 'stale') return {...translated(d), 'sourceHash': 'old'};
        return {'translated': false, 'reason': mode};
      });
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PlaceDescription(
                  placeId: 'JohnID',
                  original: 'Original',
                  locale: const Locale('fr'),
                  service: service))));
      await tester.pumpAndSettle();
      expect(find.text('Original'), findsOneWidget);
      expect(find.byKey(const Key('place_description_toggle')), findsNothing);
    });
  }
  testWidgets('late translation cannot replace changed source or locale',
      (tester) async {
    final first = Completer<Map<String, dynamic>>();
    Map<String, dynamic>? firstData;
    final service = PlaceDescriptionTranslationService(call: (d) async {
      if (d['language'] == 'en') {
        firstData = d;
        return first.future;
      }
      return translated(d, 'Nouvelle traduction');
    });
    Widget page(String text, Locale locale) => MaterialApp(
        home: Scaffold(
            body: PlaceDescription(
                placeId: 'JohnID',
                original: text,
                locale: locale,
                service: service)));
    await tester.pumpWidget(page('First', const Locale('en')));
    await tester.pumpWidget(page('New', const Locale('fr')));
    await tester.pumpAndSettle();
    first.complete(translated(firstData!, 'Obsolete'));
    await tester.pumpAndSettle();
    expect(find.text('Nouvelle traduction'), findsOneWidget);
    expect(find.text('Obsolete'), findsNothing);
  });
  test('disabled Locais and over-limit text never call server', () async {
    var calls = 0;
    final service = PlaceDescriptionTranslationService(call: (d) async {
      calls++;
      return translated(d);
    });
    LocaisFeatureFlag.debugOverride = false;
    expect(await service.load('JohnID', 'Text', const Locale('en')), null);
    LocaisFeatureFlag.debugOverride = true;
    expect(await service.load('JohnID', 'a' * 5001, const Locale('en')), null);
    expect(calls, 0);
  });
  testWidgets(
      'detail loads repository description and mocked callable result end to end',
      (tester) async {
    AppTexts.loadFromMap({
      'place_view_original': 'View original',
      'place_view_translation': 'View translation'
    });
    final place = DemoPlaces.all.first;
    final service = PlaceDescriptionTranslationService(call: (d) async {
      expect(d['placeId'], place.id);
      expect(d['sourceHash'],
          PlaceDescriptionTranslationService.sourceHash(place.description));
      return translated(d);
    });
    await pumpLocais(
        tester,
        LocaisDetailPage(
            placeId: place.id,
            repository: demoRepository(),
            translationService: service));
    await tester.pumpAndSettle();
    expect(find.text('Translated description'), findsOneWidget);
    await tester
        .ensureVisible(find.byKey(const Key('place_description_toggle')));
    await tester.tap(find.byKey(const Key('place_description_toggle')));
    await tester.pump();
    expect(find.text(place.description), findsOneWidget);
  });
  testWidgets(
      'phone language change updates translation without reopening page',
      (tester) async {
    tester.platformDispatcher.localeTestValue = const Locale('en');
    addTearDown(tester.platformDispatcher.clearLocaleTestValue);
    final service = PlaceDescriptionTranslationService(
        call: (d) async => translated(d, 'result-${d['language']}'));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PlaceDescription(
                placeId: 'JohnID', original: 'Original', service: service))));
    await tester.pumpAndSettle();
    expect(find.text('result-en'), findsOneWidget);
    tester.platformDispatcher.localeTestValue = const Locale('fr');
    await tester.pumpAndSettle();
    expect(find.text('result-fr'), findsOneWidget);
  });
}
