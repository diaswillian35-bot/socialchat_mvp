import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/models/place_listing.dart';
import 'package:socialchat_mvp/features/locais/ui/place_card.dart';

Widget _host(PlacePhoto photo) => MaterialApp(
      home: Center(
        child: PlaceCover(
          photo: photo,
          category: PlaceCategory.restaurant,
          width: 300,
          height: 160,
        ),
      ),
    );

void main() {
  testWidgets('com URL https: desenha Image.network com cacheWidth', (t) async {
    await t.pumpWidget(_host(const PlacePhoto(
        id: 'c',
        alt: 'x',
        color: 0xFF3157A4,
        url: 'https://cdn.example.com/a.jpg')));
    final img = find.byKey(const Key('place_cover_image'));
    expect(img, findsOneWidget);
    final w = t.widget<Image>(img);
    expect(w.fit, BoxFit.cover);
    expect(w.image, isA<ResizeImage>());
    expect(w.gaplessPlayback, isTrue);
    // Carregando: fundo branco, NUNCA o placeholder azul.
    expect(find.byKey(const Key('place_cover_placeholder')), findsNothing);
    expect(find.byIcon(placeCategoryIcon(PlaceCategory.restaurant)),
        findsNothing);
    expect(t.widget<ColoredBox>(find.byKey(const Key('place_cover_loaded'))).color,
        Colors.white);
  });

  testWidgets('sem URL: só o placeholder', (t) async {
    await t.pumpWidget(
        _host(const PlacePhoto(id: 'c', alt: 'x', color: 0xFF3157A4)));
    expect(find.byKey(const Key('place_cover_image')), findsNothing);
    expect(find.byIcon(placeCategoryIcon(PlaceCategory.restaurant)),
        findsOneWidget);
  });

  testWidgets('URL não https: só o placeholder', (t) async {
    await t.pumpWidget(_host(const PlacePhoto(
        id: 'c', alt: 'x', color: 0xFF3157A4, url: 'http://x.com/a.jpg')));
    expect(find.byKey(const Key('place_cover_image')), findsNothing);
  });

  testWidgets('erro ao carregar: volta ao placeholder, sem exceção', (t) async {
    // No flutter_test toda requisição HTTP responde 400 -> errorBuilder.
    await t.pumpWidget(_host(const PlacePhoto(
        id: 'c',
        alt: 'x',
        color: 0xFF3157A4,
        url: 'https://cdn.example.com/b.jpg')));
    await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await t.pump();
    expect(t.takeException(), isNull);
    expect(find.byIcon(placeCategoryIcon(PlaceCategory.restaurant)),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('place_cover_image')),
            matching: find.byType(RawImage)),
        findsNothing);
  });

  testWidgets('trocar a foto: sem placeholder azul em nenhum frame',
      (t) async {
    const a = PlacePhoto(
        id: 'c', alt: 'x', color: 0xFF3157A4, url: 'https://cdn.example.com/a.jpg');
    const b = PlacePhoto(
        id: 'c', alt: 'x', color: 0xFF3157A4, url: 'https://cdn.example.com/c.jpg');
    await t.pumpWidget(_host(a));
    expect(find.byKey(const Key('place_cover_placeholder')), findsNothing);
    final before = t.element(find.byKey(const Key('place_cover_image')));
    await t.pumpWidget(_host(b));
    // Mesmo elemento Image (gapless: mantém a foto anterior até a nova chegar).
    expect(t.element(find.byKey(const Key('place_cover_image'))), same(before));
    // (no flutter_test o HTTP responde 400, então o errorBuilder pode aparecer aqui)
    expect(t.widget<Image>(find.byKey(const Key('place_cover_image'))).gaplessPlayback,
        isTrue);
  });
}
