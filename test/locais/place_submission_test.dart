import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/data/place_submission_service.dart';
import 'package:socialchat_mvp/features/locais/ui/place_editor_page.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';

import 'locais_test_support.dart';

void main() {
  setUp(() {
    final map = jsonDecode(File('lib/l10n/pt-BR.json').readAsStringSync())
        as Map<String, dynamic>;
    AppTexts.loadFromMap(map, const Locale('pt', 'BR'));
  });

  testWidgets('aba Locais sem FAB; entrada só pelo card do topo', (tester) async {
    await pumpLocais(tester, demoList());
    await tester.pumpAndSettle();
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byKey(const Key('locais_add_place_card')), findsOneWidget);
  });

  testWidgets('card "Cadastre seu local grátis" abre Adicionar local', (
    tester,
  ) async {
    await pumpLocais(tester, demoList());
    await tester.pumpAndSettle();
    expect(find.text('Tem um negócio? Cadastre seu local grátis'), findsOneWidget);
    await tester.tap(find.byKey(const Key('locais_add_place_card')));
    await tester.pumpAndSettle();
    expect(find.byType(PlaceEditorPage), findsOneWidget);
  });

  test('textos dos cards nos 5 idiomas', () {
    for (final l in ['pt-BR', 'pt-PT', 'en', 'es', 'fr']) {
      final m = jsonDecode(File('lib/l10n/$l.json').readAsStringSync()) as Map;
      for (final k in [
        'place_cta_title',
        'place_cta_subtitle',
        'event_cta_title',
        'event_cta_subtitle',
      ]) {
        expect((m[k] as String?)?.isNotEmpty, isTrue, reason: '$l $k');
      }
    }
  });

  testWidgets('formulário em passos valida nome e cidade', (tester) async {
    await pumpLocais(tester, const PlaceEditorPage());
    await tester.pumpAndSettle();
    expect(find.text('Adicionar local'), findsOneWidget);
    expect(find.text('1/6'), findsOneWidget);
    await tester.tap(find.byKey(const Key('place_next_button')));
    await tester.pump();
    expect(find.text('Informe o nome do local.'), findsOneWidget);
    ScaffoldMessenger.of(tester.element(find.byType(Scaffold).first))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('place_name_field')), 'Bar do Zé');
    await tester.tap(find.byKey(const Key('place_next_button')));
    await tester.pumpAndSettle();
    expect(find.text('2/6'), findsOneWidget);
    await tester.tap(find.byKey(const Key('place_next_button')));
    await tester.pump();
    expect(find.text('Escolha a cidade do local.'), findsOneWidget);
  });

  test('rascunho envia só campos esperados e id hex de 32', () {
    final d = PlaceDraft(name: ' X ', cityName: 'Toronto', latitude: 1, longitude: 2);
    expect(d.hasCity, isTrue);
    expect(d.toFields()['name'], 'X');
    expect(d.toFields().containsKey('ownerId'), isFalse);
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(PlaceSubmissionService.randomHex32()), isTrue);
  });

  test('app não escreve places direto; só callables moderadas', () {
    final src = File('lib/features/locais/data/place_submission_service.dart').readAsStringSync();
    expect(src, isNot(contains("collection('places')")));
    for (final c in ['submitPlace', 'updateMyPlace', 'listPendingPlaces', 'moderatePlace']) {
      expect(src, contains("'$c'"));
    }
  });
}
