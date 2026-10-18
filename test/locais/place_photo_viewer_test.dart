import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/locais_feature_flag.dart';
import 'package:socialchat_mvp/features/locais/ui/locais_detail_page.dart';
import 'package:socialchat_mvp/features/locais/ui/place_photo_viewer.dart';

import 'locais_test_support.dart';

void main() {
  const photos = [
    PlaceViewerPhoto(url: null, label: 'Prato 1'),
    PlaceViewerPhoto(url: null, label: 'Prato 2'),
    PlaceViewerPhoto(url: null, label: 'Prato 3'),
  ];

  Future<void> open(WidgetTester tester, {int initial = 1}) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              key: const Key('open'),
              onPressed: () => showPlacePhotoViewer(context,
                  photos: photos, initialIndex: initial, closeLabel: 'Fechar'),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  testWidgets('abre na foto tocada, desliza entre fotos e fecha no X',
      (tester) async {
    await open(tester);
    expect(find.byKey(const Key('place_photo_viewer')), findsOneWidget);
    expect(find.text('2 / 3'), findsOneWidget);

    await tester.fling(find.byKey(const Key('place_photo_viewer_pages')),
        const Offset(-400, 0), 1500);
    await tester.pumpAndSettle();
    expect(find.text('3 / 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('place_photo_viewer_close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('place_photo_viewer')), findsNothing);
  });

  testWidgets('arrastar para baixo fecha; arrasto curto não fecha',
      (tester) async {
    await open(tester, initial: 0);
    final center =
        tester.getCenter(find.byKey(const Key('place_photo_viewer')));

    var g = await tester.startGesture(center);
    await g.moveBy(const Offset(0, 30));
    await g.moveBy(const Offset(0, 30));
    await g.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('place_photo_viewer')), findsOneWidget);

    g = await tester.startGesture(center);
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, 25));
      await tester.pump();
    }
    await g.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('place_photo_viewer')), findsNothing);
  });

  test('só aceita URL https sem credenciais', () {
    expect(placeSafeImageUrl('https://cdn.example.com/a.jpg'),
        'https://cdn.example.com/a.jpg');
    expect(placeSafeImageUrl('http://cdn.example.com/a.jpg'), isNull);
    expect(placeSafeImageUrl('https://u:p@cdn.example.com/a.jpg'), isNull);
    expect(placeSafeImageUrl(null), isNull);
  });

  testWidgets('tocar na foto do local abre o visualizador', (tester) async {
    addTearDown(LocaisFeatureFlag.resetDebugOverride);
    await pumpLocais(
      tester,
      LocaisDetailPage(
        placeId: 'cafe_atlantico',
        repository: demoRepository(),
        clock: locaisDemoClock,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('locais_detail_photo_tap_0')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('place_photo_viewer')), findsOneWidget);
    await tester.tap(find.byKey(const Key('place_photo_viewer_close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('place_photo_viewer')), findsNothing);
  });
}
