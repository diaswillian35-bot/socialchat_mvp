import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/locais_feature_flag.dart';
import 'package:socialchat_mvp/features/locais/ui/locais_detail_page.dart';

import 'locais_test_support.dart';
import 'package:socialchat_mvp/services/admin_access.dart';

void main() {
  // Catálogo demo tem BR, CA e PT: estes testes de lista/filtros rodam
  // como admin (vê todos). O filtro por país tem testes próprios.
  setUp(() => AdminAccess.instance.debugSet(admin: true));
  tearDown(() => AdminAccess.instance.debugSet(admin: false));
  tearDown(LocaisFeatureFlag.resetDebugOverride);

  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('locais_shot')),
      matchesGoldenFile('../../docs/locais_prototype/screenshots/$name.png'),
    );
  }

  Widget frame(Widget child) {
    return RepaintBoundary(key: const Key('locais_shot'), child: child);
  }

  testWidgets('protótipo iPhone: lista, vazio, erro e detalhe', (
    tester,
  ) async {
    await pumpLocais(tester, frame(demoList()), size: const Size(390, 844));
    await shoot(tester, 'iphone_lista');

    await tester.enterText(find.byKey(const Key('locais_search')), 'Antártica');
    await tester.pumpAndSettle();
    await shoot(tester, 'iphone_vazio');

    await pumpLocais(
      tester,
      frame(demoList(failure: StateError('falha'))),
      size: const Size(390, 844),
    );
    await shoot(tester, 'iphone_erro');

    await pumpLocais(
      tester,
      frame(
        LocaisDetailPage(
          placeId: 'casa_do_sabor',
          repository: demoRepository(),
          clock: locaisDemoClock,
        ),
      ),
      size: const Size(390, 844),
    );
    await shoot(tester, 'iphone_detalhe');
  });

  testWidgets('protótipo Android e iPad', (tester) async {
    await pumpLocais(tester, frame(demoList()), size: const Size(412, 915));
    await shoot(tester, 'android_lista');

    await pumpLocais(tester, frame(demoList()), size: const Size(1024, 768));
    await shoot(tester, 'ipad_lista');
  });
}
