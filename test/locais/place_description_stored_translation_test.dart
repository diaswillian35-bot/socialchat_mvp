import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/data/firestore_place_mapper.dart';
import 'package:socialchat_mvp/features/locais/data/place_description_translation_service.dart';
import 'package:socialchat_mvp/features/locais/locais_feature_flag.dart';
import 'package:socialchat_mvp/features/locais/models/place_description_translations.dart';
import 'package:socialchat_mvp/features/locais/ui/place_description.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';

import 'firestore_place_mapper_test.dart' show approvedPlace;

/// Build 44: tradução única gravada na aprovação (`descriptionI18n`).
void main() {
  setUp(() => LocaisFeatureFlag.debugOverride = true);
  tearDown(LocaisFeatureFlag.resetDebugOverride);

  const original = 'Hambúrguer artesanal feito com amor';
  final hash = PlaceDescriptionTranslations.hashOf(original);
  Map<String, dynamic> i18n({
    String source = 'pt',
    Map<String, String>? texts,
    String? sourceHash,
  }) =>
      {
        'version': 1,
        'status': 'ready',
        'sourceHash': sourceHash ?? hash,
        'sourceLanguage': source,
        'texts':
            texts ?? {'en': 'Stored EN', 'es': 'Stored ES', 'fr': 'Stored FR'},
      };

  const locales = {
    'pt-BR': Locale('pt', 'BR'),
    'pt-PT': Locale('pt', 'PT'),
    'en': Locale('en'),
    'es': Locale('es'),
    'fr': Locale('fr'),
  };

  Future<int> pump(
      WidgetTester tester, Locale locale, PlaceDescriptionTranslations? stored,
      {String text = original}) async {
    var calls = 0;
    final service = PlaceDescriptionTranslationService(call: (data) async {
      calls++;
      return {
        'translated': true,
        'text': 'Callable ${data['language']}',
        'sourceHash': data['sourceHash'],
        'targetLanguage': data['language'],
      };
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PlaceDescription(
                placeId: 'P1',
                original: text,
                stored: stored,
                locale: locale,
                service: service))));
    await tester.pumpAndSettle();
    return calls;
  }

  for (final entry in locales.entries) {
    testWidgets('stored translation, no network call, in ${entry.key}',
        (tester) async {
      final catalog =
          jsonDecode(File('lib/l10n/${entry.key}.json').readAsStringSync())
              as Map<String, dynamic>;
      AppTexts.loadFromMap(catalog, entry.value);
      final stored =
          PlaceDescriptionTranslations.tryParse(i18n(source: 'en', texts: {
        'pt-BR': 'Guardado BR',
        'pt-PT': 'Guardado PT',
        'es': 'Stored ES',
        'fr': 'Stored FR',
      }));
      final calls = await pump(tester, entry.value, stored);
      expect(calls, 0);
      final expected = {
        'pt-BR': 'Guardado BR',
        'pt-PT': 'Guardado PT',
        'en': original, // origem em inglês: mostra o original
        'es': 'Stored ES',
        'fr': 'Stored FR',
      }[entry.key]!;
      expect(find.text(expected), findsOneWidget);
      if (entry.key == 'en') {
        expect(find.byKey(const Key('place_description_toggle')), findsNothing);
        return;
      }
      expect(find.text(catalog['place_view_original']), findsOneWidget);
      await tester.tap(find.byKey(const Key('place_description_toggle')));
      await tester.pump();
      expect(find.text(original), findsOneWidget);
      expect(find.text(catalog['place_view_translation']), findsOneWidget);
    });
  }

  testWidgets('Portuguese source on pt devices: original, no call, no link',
      (tester) async {
    final stored = PlaceDescriptionTranslations.tryParse(i18n());
    for (final locale in [const Locale('pt', 'BR'), const Locale('pt', 'PT')]) {
      expect(await pump(tester, locale, stored), 0);
      expect(find.text(original), findsOneWidget);
      expect(find.byKey(const Key('place_description_toggle')), findsNothing);
    }
  });

  testWidgets('stale hash (description edited) falls back to the callable',
      (tester) async {
    final stored =
        PlaceDescriptionTranslations.tryParse(i18n(sourceHash: 'a' * 64));
    expect(await pump(tester, const Locale('en'), stored), 1);
    expect(find.text('Callable en'), findsOneWidget);
  });

  testWidgets('no stored translations (old places) keep the callable fallback',
      (tester) async {
    expect(await pump(tester, const Locale('fr'), null), 1);
    expect(find.text('Callable fr'), findsOneWidget);
  });

  testWidgets('partial result without this language falls back once',
      (tester) async {
    final stored =
        PlaceDescriptionTranslations.tryParse(i18n(texts: {'en': 'Stored EN'}));
    expect(await pump(tester, const Locale('es'), stored), 1);
  });

  test('pt-PT uses pt-BR text when only pt-BR was stored', () {
    final stored = PlaceDescriptionTranslations.tryParse(
        i18n(source: 'en', texts: {'pt-BR': 'Guardado BR'}))!;
    final r = stored.resolve(original, const Locale('pt', 'PT'));
    expect(r.use, StoredTranslationUse.translated);
    expect(r.text, 'Guardado BR');
  });

  test('mapper reads descriptionI18n and ignores malformed data', () {
    final ok = FirestorePlaceMapper.tryParse('p1', {
      ...approvedPlace(),
      'description': original,
      'descriptionI18n': i18n()
    });
    expect(ok!.descriptionTranslations!.texts['en'], 'Stored EN');
    expect(ok.descriptionTranslations!.sourceLanguage, 'pt');
    final bad = FirestorePlaceMapper.tryParse('p2', {
      ...approvedPlace(),
      'descriptionI18n': {'sourceHash': 'nope'}
    });
    expect(bad!.descriptionTranslations, isNull);
    final none = FirestorePlaceMapper.tryParse('p3', approvedPlace());
    expect(none!.descriptionTranslations, isNull);
  });

  test('keyFor maps device locales to the 5 app languages', () {
    expect(
        PlaceDescriptionTranslations.keyFor(const Locale('pt', 'BR')), 'pt-BR');
    expect(PlaceDescriptionTranslations.keyFor(const Locale('pt')), 'pt-BR');
    expect(
        PlaceDescriptionTranslations.keyFor(const Locale('pt', 'PT')), 'pt-PT');
    expect(PlaceDescriptionTranslations.keyFor(const Locale('de')), 'en');
  });
}
