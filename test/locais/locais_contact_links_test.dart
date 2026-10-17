import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/locais_feature_flag.dart';
import 'package:socialchat_mvp/features/locais/ui/locais_detail_page.dart';
import 'package:url_launcher/url_launcher.dart';

import 'locais_test_support.dart';

void main() {
  tearDown(LocaisFeatureFlag.resetDebugOverride);

  Future<List<_Call>> pumpDetail(
    WidgetTester tester, {
    bool result = true,
  }) async {
    final calls = <_Call>[];
    await pumpLocais(
      tester,
      LocaisDetailPage(
        placeId: 'cafe_atlantico',
        repository: demoRepository(),
        clock: locaisDemoClock,
        launcher: (uri, mode) async {
          calls.add(_Call(uri, mode));
          return result;
        },
      ),
    );
    await tester.pumpAndSettle();
    return calls;
  }

  Future<void> tapRow(WidgetTester tester, String key) async {
    final finder = find.byKey(Key(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('site e Instagram abrem fora do app', (tester) async {
    final calls = await pumpDetail(tester);

    await tapRow(tester, 'locais_contact_website');
    expect(calls.last.uri, Uri.parse('https://remdy.app'));
    expect(calls.last.mode, LaunchMode.externalApplication);

    await tapRow(tester, 'locais_contact_instagram');
    expect(
      calls.last.uri,
      Uri.parse('https://www.instagram.com/cafeatlantico.demo/'),
    );
    expect(calls.last.mode, LaunchMode.externalApplication);
    expect(find.text('@cafeatlantico.demo'), findsOneWidget);
  });

  testWidgets('Como chegar abre direções externas', (tester) async {
    final calls = await pumpDetail(tester);
    await tapRow(tester, 'locais_route_button');
    expect(calls.last.uri.host, 'www.google.com');
    expect(calls.last.uri.path, '/maps/dir/');
  });

  testWidgets('link que não abre tenta o navegador e avisa', (tester) async {
    final calls = await pumpDetail(tester, result: false);
    await tapRow(tester, 'locais_contact_website');
    expect(calls.map((c) => c.mode), [
      LaunchMode.externalApplication,
      LaunchMode.platformDefault,
    ]);
    expect(find.text('Não foi possível abrir o link'), findsOneWidget);
  });
}

class _Call {
  _Call(this.uri, this.mode);
  final Uri uri;
  final LaunchMode mode;
}
