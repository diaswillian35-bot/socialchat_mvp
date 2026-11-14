import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/data/place_submission_service.dart';
import 'package:socialchat_mvp/features/locais/logic/pending_my_places.dart';
import 'package:socialchat_mvp/features/locais/locais_strings.dart';
import 'package:socialchat_mvp/features/locais/ui/locais_list_page.dart';
import 'package:socialchat_mvp/features/locais/ui/place_editor_page.dart';
import 'package:socialchat_mvp/features/locais/ui/place_submissions_page.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';

import 'locais_test_support.dart';

void main() {
  setUp(() {
    final map = jsonDecode(File('lib/l10n/pt-BR.json').readAsStringSync())
        as Map<String, dynamic>;
    AppTexts.loadFromMap(map, const Locale('pt', 'BR'));
    PendingMyPlaces.openAfterLogin = false;
  });

  testWidgets('aba Locais sem FAB; entrada só pelo card do topo',
      (tester) async {
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
    expect(
        find.text('Tem um negócio? Cadastre seu local grátis'), findsOneWidget);
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
    await tester.enterText(
        find.byKey(const Key('place_name_field')), 'Bar do Zé');
    await tester.tap(find.byKey(const Key('place_next_button')));
    await tester.pumpAndSettle();
    expect(find.text('2/6'), findsOneWidget);
    await tester.tap(find.byKey(const Key('place_next_button')));
    await tester.pump();
    expect(find.text('Escolha a cidade do local.'), findsOneWidget);
  });

  test('rascunho envia só campos esperados e id hex de 32', () {
    final d =
        PlaceDraft(name: ' X ', cityName: 'Toronto', latitude: 1, longitude: 2);
    expect(d.hasCity, isTrue);
    expect(d.toFields()['name'], 'X');
    expect(d.toFields().containsKey('ownerId'), isFalse);
    expect(
        RegExp(r'^[0-9a-f]{32}$')
            .hasMatch(PlaceSubmissionService.randomHex32()),
        isTrue);
  });

  test('app não escreve places direto; só callables moderadas', () {
    final src = File('lib/features/locais/data/place_submission_service.dart')
        .readAsStringSync();
    expect(src, isNot(contains("collection('places')")));
    for (final c in [
      'submitPlace',
      'updateMyPlace',
      'listPendingPlaces',
      'moderatePlace',
      'deletePlace',
    ]) {
      expect(src, contains("'$c'"));
    }
  });

  test('textos de excluir local nos 5 idiomas', () {
    for (final l in ['pt-BR', 'pt-PT', 'en', 'es', 'fr']) {
      final m = jsonDecode(File('lib/l10n/$l.json').readAsStringSync()) as Map;
      for (final k in [
        'place_delete',
        'place_delete_action',
        'place_delete_confirm',
        'place_deleted_snack',
      ]) {
        expect((m[k] as String?)?.isNotEmpty, isTrue, reason: '$l $k');
      }
    }
    final br =
        jsonDecode(File('lib/l10n/pt-BR.json').readAsStringSync()) as Map;
    expect(br['place_delete'], 'Excluir local');
    expect(br['place_delete_action'], 'Excluir');
  });

  testWidgets('folha do admin oferece Excluir com confirmação', (tester) async {
    await pumpLocais(
      tester,
      PlaceSubmissionsPage(
        adminPending: true,
        loader: () async => [
          PlaceDraft(
            id: 'p1',
            name: 'Bar do Zé',
            cityDisplay: 'Toronto',
            status: 'pending',
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bar do Zé'), findsOneWidget);
    await tester.tap(find.text('Bar do Zé'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('place_delete')), findsOneWidget);
    expect(find.text('Excluir'), findsOneWidget);
    await tester.tap(find.byKey(const Key('place_delete')));
    await tester.pumpAndSettle();
    expect(find.text('Excluir local'), findsOneWidget);
    expect(
      find.text(
        'Tem certeza de que deseja excluir este local? Ele deixará de aparecer em Locais.',
      ),
      findsOneWidget,
    );
    expect(find.text('Cancelar'), findsOneWidget);
  });

  test('texto do botão Gerenciar meus locais nos 5 idiomas', () {
    const expected = {
      'pt-BR': 'Gerenciar meus locais',
      'pt-PT': 'Gerir os meus locais',
      'en': 'Manage my places',
      'es': 'Gestionar mis lugares',
      'fr': 'Gérer mes lieux',
    };
    for (final entry in expected.entries) {
      final code = entry.key;
      final m =
          jsonDecode(File('lib/l10n/$code.json').readAsStringSync()) as Map;
      expect(
        (m['place_cta_manage_title'] as String?)?.isNotEmpty,
        isTrue,
        reason: '$code place_cta_manage_title',
      );
      expect(m['place_cta_manage_title'], entry.value);
    }
    final br =
        jsonDecode(File('lib/l10n/pt-BR.json').readAsStringSync()) as Map;
    expect(br['place_cta_title'], 'Tem um negócio? Cadastre seu local grátis');
  });

  LocaisListPage manageDemo({
    bool signedIn = true,
    WidgetBuilder? loginPageBuilder,
  }) {
    return LocaisListPage(
      repository: demoRepository(),
      clock: locaisDemoClock,
      homeCountryLoader: () async => 'br',
      isSignedIn: () => signedIn,
      loginPageBuilder: loginPageBuilder,
      myPlacesBuilder: (_) => PlaceSubmissionsPage(
        adminPending: false,
        loader: () async => [],
      ),
    );
  }

  testWidgets(
      'botão Gerenciar meus locais no título abre Meus locais; card do topo intacto',
      (tester) async {
    await pumpLocais(tester, manageDemo());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('locais_manage_places')), findsOneWidget);
    expect(find.text('Gerenciar meus locais'), findsOneWidget);
    expect(find.byType(TextButton), findsWidgets);
    expect(find.byIcon(Icons.storefront_rounded), findsOneWidget);
    expect(find.byKey(const Key('locais_add_place_card')), findsOneWidget);
    expect(
      find.text('Tem um negócio? Cadastre seu local grátis'),
      findsOneWidget,
    );
    expect(
      find.text('Restaurante, bar, café ou hospedagem'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('locais_manage_places')));
    await tester.pumpAndSettle();
    expect(find.byType(PlaceSubmissionsPage), findsOneWidget);
    expect(find.text('Meus locais'), findsOneWidget);
  });

  testWidgets('sem login o botão vai para o login e não abre Meus locais',
      (tester) async {
    await pumpLocais(
      tester,
      manageDemo(
        signedIn: false,
        loginPageBuilder: (_) => Scaffold(
          key: const Key('fake_login'),
          appBar: AppBar(title: const Text('Login fake')),
          body: const Text('Login fake'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('locais_manage_places')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fake_login')), findsOneWidget);
    expect(find.byType(PlaceSubmissionsPage), findsNothing);
    expect(PendingMyPlaces.openAfterLogin, isTrue);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(PendingMyPlaces.openAfterLogin, isFalse);
    expect(find.byType(PlaceSubmissionsPage), findsNothing);
  });

  testWidgets('Meus locais vazio mostra Adicionar local e abre o cadastro',
      (tester) async {
    await pumpLocais(
      tester,
      PlaceSubmissionsPage(
        adminPending: false,
        loader: () async => [],
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Você ainda não cadastrou nenhum local.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('place_mine_add')), findsOneWidget);
    expect(find.text('Adicionar local'), findsOneWidget);
    await tester.tap(find.byKey(const Key('place_mine_add')));
    await tester.pumpAndSettle();
    expect(find.byType(PlaceEditorPage), findsOneWidget);
  });

  testWidgets('lista em análise vazia não mostra Adicionar local',
      (tester) async {
    await pumpLocais(
      tester,
      PlaceSubmissionsPage(
        adminPending: true,
        loader: () async => [],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('place_mine_add')), findsNothing);
  });

  testWidgets(
      'rótulo longo do Gerenciar não estourou o layout em 390px nos 5 idiomas',
      (tester) async {
    const locales = <String, Locale>{
      'pt-BR': Locale('pt', 'BR'),
      'pt-PT': Locale('pt', 'PT'),
      'en': Locale('en'),
      'es': Locale('es'),
      'fr': Locale('fr'),
    };
    Map<String, dynamic> loadLang(String code) {
      return jsonDecode(File('lib/l10n/$code.json').readAsStringSync())
          as Map<String, dynamic>;
    }

    for (final entry in locales.entries) {
      final code = entry.key;
      final locale = entry.value;
      final map = code == 'pt-PT'
          ? <String, dynamic>{...loadLang('pt-BR'), ...loadLang('pt-PT')}
          : loadLang(code);
      AppTexts.loadFromMap(map, locale);
      LocaisStrings.debugLocale = locale;
      await pumpLocais(tester, manageDemo(), size: const Size(390, 844));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('locais_manage_places')), findsOneWidget);
      expect(find.byType(TextButton), findsWidgets);
      final overflow = tester.takeException();
      expect(overflow, isNull, reason: 'overflow $code');
    }
    LocaisStrings.resetDebugLocale();
    AppTexts.loadFromMap(
      jsonDecode(File('lib/l10n/pt-BR.json').readAsStringSync())
          as Map<String, dynamic>,
      const Locale('pt', 'BR'),
    );
  });
}
