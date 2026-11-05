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
    // Placeholder continua por baixo (carregando / erro).
    expect(find.byIcon(placeCategoryIcon(PlaceCategory.restaurant)),
        findsOneWidget);
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
}
