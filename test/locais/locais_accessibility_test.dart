import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/locais_feature_flag.dart';
import 'package:socialchat_mvp/features/locais/ui/locais_layout.dart';

import 'locais_test_support.dart';

void main() {
  tearDown(LocaisFeatureFlag.resetDebugOverride);

  test('colunas e mapa lado a lado seguem a largura', () {
    expect(LocaisLayout.columnsForWidth(390), 1);
    expect(LocaisLayout.columnsForWidth(412), 1);
    expect(LocaisLayout.columnsForWidth(800), 2);
    expect(LocaisLayout.columnsForWidth(1100), 3);
    expect(LocaisLayout.splitMap(844), isFalse);
    expect(LocaisLayout.splitMap(1024), isTrue);
  });

  testWidgets('rótulos de acessibilidade e alvo de toque', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpLocais(tester, demoList(), textScale: 1.3);
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(RegExp('Casa do Sabor')), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('Buscar cidade ou região')),
      findsWidgets,
    );
    expect(
      tester.getSize(find.byKey(const Key('place_card_casa_do_sabor'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('locais_view_map')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('locais_map')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Mapa com')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('place_pin_casa_do_sabor'))).height,
      greaterThanOrEqualTo(48),
    );
    handle.dispose();
  });

  testWidgets('iPhone, Android e iPad cabem sem overflow', (tester) async {
    const sizes = <Size>[
      Size(390, 844),
      Size(412, 915),
      Size(1024, 768),
      Size(768, 1024),
    ];
    for (final size in sizes) {
      await pumpLocais(tester, demoList(), size: size, textScale: 1.15);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size');
      expect(find.text('Locais'), findsWidgets);
      if (LocaisLayout.splitMap(size.width)) {
        expect(find.byKey(const Key('locais_split_map')), findsOneWidget);
      } else {
        expect(find.byKey(const Key('locais_split_map')), findsNothing);
        expect(
          find.byKey(const Key('place_card_casa_do_sabor')),
          findsOneWidget,
        );
      }
    }
  });

  testWidgets('botão de tentar novamente tem alvo mínimo', (tester) async {
    await pumpLocais(tester, demoList(failure: StateError('falha')));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byKey(const Key('locais_retry'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });
}
