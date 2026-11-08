import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/data/demo_places.dart';
import 'package:socialchat_mvp/features/locais/locais_feature_flag.dart';
import 'package:socialchat_mvp/features/locais/logic/place_country_access.dart';
import 'package:socialchat_mvp/features/locais/models/place_listing.dart';
import 'package:socialchat_mvp/features/locais/ui/locais_deep_link_page.dart';
import 'package:socialchat_mvp/features/locais/ui/locais_list_page.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';
import 'package:socialchat_mvp/services/admin_access.dart';
import 'package:socialchat_mvp/services/remdy_launch_access.dart';
import 'package:socialchat_mvp/widgets/home_places_section.dart';

import 'locais_test_support.dart';

PlaceListing _first(String cc) =>
    DemoPlaces.all.firstWhere((p) => p.address.countryCode == cc);

void main() {
  final all = DemoPlaces.all;
  final now = DateTime(2026, 11, 7, 12);
  tearDown(() => AdminAccess.instance.debugSet(admin: false));
  tearDown(LocaisFeatureFlag.resetDebugOverride);

  test('conta comum BR só vê locais BR; CA só CA', () {
    final br = filterPlacesByCountry(all, 'br');
    expect(br, isNotEmpty);
    expect(br.every((p) => p.address.countryCode == 'BR'), isTrue);
    final ca = filterPlacesByCountry(all, 'CA');
    expect(ca, isNotEmpty);
    expect(ca.every((p) => p.address.countryCode == 'CA'), isTrue);
    expect(canSeePlaceCountry(_first('CA'), 'br'), isFalse);
    expect(canSeePlaceCountry(_first('BR'), 'ca'), isFalse);
  });

  test('conta sem país não vê locais; local sem país não aparece', () {
    expect(filterPlacesByCountry(all, ''), isEmpty);
    expect(filterPlacesByCountry(all, null), isEmpty);
    // Local sem país (mesma regra usada por canSeePlaceCountry).
    expect(
        RemdyLaunchAccess.canAccessCountryContent(
            userHomeCountryCode: 'br', targetCountryCode: ''),
        isFalse);
  });

  test('admin vê todos os países', () {
    AdminAccess.instance.debugSet(admin: true);
    expect(filterPlacesByCountry(all, '').length, all.length);
    expect(canSeePlaceCountry(_first('CA'), 'br'), isTrue);
  });

  test('Home: conta comum BR sem CA, conta sem país sem locais', () {
    final br = selectHomePlaces(all, countryCode: 'br', now: now);
    expect(br.any((p) => p.address.countryCode == 'CA'), isFalse);
    expect(selectHomePlaces(all, countryCode: '', now: now), isEmpty);
    AdminAccess.instance.debugSet(admin: true);
    expect(selectHomePlaces(all, countryCode: '', now: now), isNotEmpty);
  });

  testWidgets('aba Locais: conta comum BR não vê local do Canadá',
      (tester) async {
    final ca = _first('CA');
    await pumpLocais(
        tester,
        LocaisListPage(
          repository: demoRepository(),
          clock: locaisDemoClock,
          homeCountryLoader: () async => 'br',
        ));
    await tester.pumpAndSettle();
    expect(find.text(ca.name), findsNothing);
    expect(find.text(_first('BR').name), findsWidgets);
  });

  testWidgets('aba Locais: conta comum CA vê o local do Canadá',
      (tester) async {
    final ca = _first('CA');
    await pumpLocais(
        tester,
        LocaisListPage(
          repository: demoRepository(),
          clock: locaisDemoClock,
          homeCountryLoader: () async => 'ca',
        ));
    await tester.pumpAndSettle();
    expect(find.text(ca.name), findsWidgets);
    expect(find.text(_first('BR').name), findsNothing);
  });

  testWidgets('link direto de outro país mostra a mensagem existente',
      (tester) async {
    AppTexts.loadFromMap(
        Map<String, dynamic>.from(jsonDecode(
            File('lib/l10n/pt-BR.json').readAsStringSync()) as Map),
        const Locale('pt', 'BR'));
    final ca = _first('CA');
    await pumpLocais(
        tester,
        LocaisDeepLinkPage(
          placeId: ca.id,
          repository: demoRepository(),
          homeCountryLoader: () async => 'br',
        ));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Este conteúdo não está disponível.'), findsOneWidget);
    expect(find.text(ca.name), findsNothing);
  });
}
