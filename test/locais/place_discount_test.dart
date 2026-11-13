import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/models/place_discount.dart';
import 'package:socialchat_mvp/features/locais/models/place_listing.dart';
import 'package:socialchat_mvp/features/locais/ui/place_card.dart';
import 'package:socialchat_mvp/features/locais/ui/place_discount_badge.dart';
import 'package:socialchat_mvp/features/locais/ui/place_discount_editor_page.dart';
import 'package:socialchat_mvp/features/locais/locais_strings.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';

Map<String, dynamic> loadLang(String code) {
  final file = File('lib/l10n/$code.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

Map<String, dynamic> catalogFor(String code) {
  if (code == 'pt-PT') {
    return {...loadLang('pt-BR'), ...loadLang('pt-PT')};
  }
  return loadLang(code);
}

void loadPtBr() {
  AppTexts.loadFromMap(catalogFor('pt-BR'), const Locale('pt', 'BR'));
}

PlaceListing listingWithDiscount(PlaceDiscount? discount) {
  return PlaceListing(
    id: 'p1',
    slug: 'divas',
    name: 'Divas',
    category: PlaceCategory.bar,
    description: 'Bar',
    photos: const [
      PlacePhoto(id: 'c', alt: 'Divas', color: 0xFF3157A4, url: ''),
    ],
    rating: 4.8,
    ratingCount: 32,
    address: const PlaceAddress(
      line1: '',
      district: 'Centro',
      city: 'Campo Mourão',
      region: 'PR',
      countryCode: 'BR',
      postalCode: '',
    ),
    contact: const PlaceContact(),
    hours: const [],
    accessibility: const PlaceAccessibility(
      wheelchairEntrance: false,
      stepFree: false,
      accessibleRestroom: false,
    ),
    reviews: const [],
    upcomingEvents: const [],
    discount: discount,
  );
}

void main() {
  final discountKeys = [
    'place_discount_title',
    'place_discount_show',
    'place_discount_help',
    'place_discount_headline',
    'place_discount_how_body',
    'place_discount_redeem_title',
    'place_discount_admin_title',
    'place_discount_partner',
    'fn_error_discount_date_max',
  ];

  test('cliente não escreve discount direto; só as 4 callables', () {
    final src = File('lib/features/locais/data/place_discount_service.dart')
        .readAsStringSync();
    expect(src.contains('.set('), isFalse);
    expect(src.contains('.update('), isFalse);
    for (final c in [
      'setPlaceDiscount',
      'setPlacePartnershipDiscount',
      'issuePlaceDiscountCode',
      'redeemPlaceDiscount',
    ]) {
      expect(src, contains("'$c'"));
    }
  });

  test('textos do selo nos 5 idiomas e pt-BR exato', () {
    for (final code in ['pt-BR', 'pt-PT', 'en', 'es', 'fr']) {
      final map = catalogFor(code);
      for (final k in discountKeys) {
        expect(map[k], isA<String>(), reason: '$code $k');
        expect((map[k] as String).isNotEmpty, isTrue, reason: '$code $k empty');
      }
    }
    final pt = catalogFor('pt-BR');
    expect(pt['place_discount_title'], 'Selo de desconto');
    expect(pt['place_discount_help'],
        'No máximo 90 dias. Só um selo ativo por local.');
    expect(pt['place_discount_redeem_title'], 'Validar código');
    expect(pt['place_discount_condition_short'], 'mostrando o app Remdy');
    expect(pt['place_discount_partner'], 'Parceria Remdy');
  });

  test('PlaceDiscount: parse, ativo, expirado, percent inválido', () {
    final until = DateTime.now().toUtc().add(const Duration(days: 10));
    final d = PlaceDiscount.tryParse({
      'enabled': true,
      'percent': 10,
      'validUntilIso': until.toIso8601String(),
      'promotionId': 'abc',
      'source': 'partnership',
      'coveredBy': 'shared',
    });
    expect(d, isNotNull);
    expect(d!.percent, 10);
    expect(d.isPartnership, isTrue);
    expect(d.coveredBy, 'shared');
    expect(d.isActiveAt(DateTime.now()), isTrue);
    expect(d.badgeLabel(), '−10%');
    expect(PlaceDiscount.tryParse({'enabled': true, 'percent': 12}), isNull);
    final expired = PlaceDiscount(
      enabled: true,
      percent: 10,
      validUntil: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      promotionId: 'x',
    );
    expect(expired.isActiveAt(DateTime.now()), isFalse);
    final off = PlaceDiscount(
      enabled: false,
      percent: 10,
      validUntil: until,
      promotionId: 'x',
    );
    expect(off.isActiveAt(DateTime.now()), isFalse);
  });

  testWidgets('selo −10% no card e no seletor do dono (90 dias)',
      (tester) async {
    loadPtBr();
    final until = DateTime.utc(2026, 12, 12);
    final d = PlaceDiscount(
      enabled: true,
      percent: 10,
      validUntil: until,
      promotionId: 'p',
    );
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlaceCard(
            place: listingWithDiscount(d),
            strings: LocaisStrings.fromLocale(const Locale('pt', 'BR')),
            open: true,
            onTap: () {},
            onDiscountTap: () => opened = true,
          ),
        ),
      ),
    );
    expect(find.text('−10%'), findsOneWidget);
    await tester.tap(find.byKey(const Key('place_discount_badge')));
    await tester.pump();
    expect(opened, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: PlaceDiscountEditorPage(
          placeId: 'p1',
          placeName: 'Divas',
          placeStatus: 'publicado',
          initial: PlaceDiscount(
            enabled: true,
            percent: 10,
            validUntil: until,
            promotionId: 'p',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Selo de desconto'), findsOneWidget);
    expect(find.text('Mostrar selo'), findsOneWidget);
    expect(find.text('10%'), findsOneWidget);
    expect(find.text('No máximo 90 dias. Só um selo ativo por local.'),
        findsOneWidget);
    expect(find.text('Salvar selo'), findsOneWidget);
  });

  testWidgets('badge sozinho usa a cor do mockup', (tester) async {
    loadPtBr();
    await tester.pumpWidget(
      MaterialApp(
        home: PlaceDiscountBadge(
          discount: PlaceDiscount(
            enabled: true,
            percent: 15,
            validUntil: DateTime.now().toUtc().add(const Duration(days: 1)),
            promotionId: 'x',
          ),
        ),
      ),
    );
    expect(find.text('−15%'), findsOneWidget);
    final box = tester.widget<Container>(find.byType(Container).first);
    final dec = box.decoration as BoxDecoration;
    expect(dec.color, const Color(0xFF15803D));
  });
}
