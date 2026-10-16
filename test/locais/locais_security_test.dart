import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/data/place_repository.dart';
import 'package:socialchat_mvp/features/locais/locais_feature_flag.dart';
import 'package:socialchat_mvp/features/locais/logic/merchant_portal_plan.dart';
import 'package:socialchat_mvp/features/locais/models/place_listing.dart';
import 'package:socialchat_mvp/services/remdy_deep_link_parser.dart';

import 'locais_test_support.dart';

void main() {
  tearDown(LocaisFeatureFlag.resetDebugOverride);

  test('build de produção e o binário Apple nascem com a flag desligada', () {
    expect(LocaisFeatureFlag.defineKey, 'REMDY_LOCAIS_ENABLED');
    expect(LocaisFeatureFlag.compiledEnabled, isFalse);
    LocaisFeatureFlag.resetDebugOverride();
    expect(LocaisFeatureFlag.isEnabled, isFalse);
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('version: 1.0.4+38'), isTrue);
  });

  test('Locais entra apenas no shell e no roteador atrás da flag', () {
    const pages = [
      'lib/pages/home_page.dart',
      'lib/pages/profile_page.dart',
      'lib/pages/messages_page.dart',
      'lib/pages/groups_list_page.dart',
      'lib/pages/events_page_new.dart',
      'lib/pages/menu_page.dart',
      'lib/services/remdy_link_router.dart',
    ];
    for (final path in pages) {
      final source = File(path).readAsStringSync();
      expect(source.contains('features/locais'), isFalse, reason: path);
      expect(source.contains('LocaisListPage'), isFalse, reason: path);
    }
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('LocaisFeatureFlag.isEnabled'));
    final shell = File('lib/pages/main_shell_page.dart').readAsStringSync();
    expect(shell, contains('LocaisFeatureFlag.isEnabled'));
  });

  test('o link público futuro não abre no roteador atual', () {
    final link = RemdyDeepLinkParser.parse(
      Uri.parse('https://remdy.app/l/casa_do_sabor'),
    );
    expect(link.kind, RemdyDeepLinkKind.none);
    expect(link.opensGroupPreview, isFalse);
    expect(
      MerchantPortalPlan.shouldOpenInApp(
        Uri.parse('https://remdy.app/l/casa_do_sabor'),
        featureEnabled: false,
      ),
      isFalse,
    );
    expect(
      MerchantPortalPlan.shouldOpenInApp(
        Uri.parse('https://remdy.app/l/casa_do_sabor'),
        featureEnabled: true,
      ),
      isTrue,
    );
    expect(
      MerchantPortalPlan.parsePlaceId(
        Uri.parse('https://remdy.app/l/../admin'),
      ),
      isNull,
    );
    expect(
      MerchantPortalPlan.portalUri('casa_do_sabor').toString(),
      'https://remdy.app/portal/locais/casa_do_sabor',
    );
    expect(
      () => MerchantPortalPlan.portalUri('../admin'),
      throwsA(isA<PlaceContractException>()),
    );
  });

  test('link público de ficha abre Locais somente com slug seguro', () {
    final link = RemdyDeepLinkParser.parse(
      Uri.parse('https://remdy.app/locais/pr/campo-mourao/cafe-central'),
    );
    expect(link.kind, RemdyDeepLinkKind.place);
    expect(link.placeSlug, 'cafe-central');

    final invalid = RemdyDeepLinkParser.parse(
      Uri.parse('https://remdy.app/locais/pr/campo-mourao/..'),
    );
    expect(invalid.kind, RemdyDeepLinkKind.none);
  });

  test(
    'repositório bloqueado não lê catálogo e a flag escolhe a fonte',
    () async {
      expect(createPlaceRepository, isNotNull);
      LocaisFeatureFlag.debugOverride = false;
      final blocked = createPlaceRepository();
      expect(blocked, isA<BlockedPlaceRepository>());
      await expectLater(
        blocked.fetchCatalog(),
        throwsA(isA<PlaceAccessBlocked>()),
      );
      await expectLater(
        blocked.fetchById('casa_do_sabor'),
        throwsA(isA<PlaceAccessBlocked>()),
      );

      LocaisFeatureFlag.debugOverride = true;
      final live = createPlaceRepository();
      expect(live, isA<FirestorePlaceRepository>());
    },
  );

  test('código de Locais usa somente Firebase configurado e não guarda segredo',
      () {
    final files = Directory('lib/features/locais')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    expect(files, isNotEmpty);
    for (final file in files) {
      final source = file.readAsStringSync();
      expect(source.contains('package:http'), isFalse, reason: file.path);
      expect(source.contains('AIza'), isFalse, reason: file.path);
      expect(source.contains('apiKey'), isFalse, reason: file.path);
      expect(source.contains('dart_defines'), isFalse, reason: file.path);
    }

    final library = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));
    for (final file in library) {
      if (file.path.endsWith('locais_feature_flag.dart')) continue;
      if (file.path.endsWith('locais_strings.dart')) continue;
      final source = file.readAsStringSync();
      expect(source.contains('debugOverride'), isFalse, reason: file.path);
      expect(source.contains('debugLocale'), isFalse, reason: file.path);
    }
  });

  test('consulta pública exige publicado, ativo e não apagado', () {
    final source = File(
      'lib/features/locais/data/place_repository.dart',
    ).readAsStringSync();
    expect(source, contains(".collection('places')"));
    expect(source, contains("'moderationStatus', isEqualTo: 'published'"));
    expect(source, contains("'active', isEqualTo: true"));
    expect(source, contains("'deleted', isEqualTo: false"));
    expect(source, isNot(contains("collection('locais')")));
  });

  testWidgets('tela desligada não chega no catálogo de demonstração', (
    tester,
  ) async {
    LocaisFeatureFlag.debugOverride = false;
    await pumpLocais(tester, demoList(), enabled: false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('locais_disabled')), findsOneWidget);
    expect(find.byKey(const Key('place_card_casa_do_sabor')), findsNothing);
    expect(find.textContaining('remdy.app/l/'), findsNothing);
  });
}
