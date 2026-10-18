import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/models/place_listing.dart';
import 'package:socialchat_mvp/features/locais/ui/place_card.dart';

const _photo = PlacePhoto(
  id: 'cover',
  alt: 'Capa acessível do Café Remdy',
  color: 0xFF3157A4,
  url: 'https://cdn.example.com/place.jpg',
);

void main() {
  testWidgets('URL HTTPS cria imagem real com descrição acessível',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(
      home: PlaceCover(photo: _photo, category: PlaceCategory.cafe),
    ));
    expect(find.byType(Image), findsOneWidget);
    expect(
        find.bySemanticsLabel('Capa acessível do Café Remdy'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('falha da imagem usa fallback Remdy seguro', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: PlaceCover(photo: _photo, category: PlaceCategory.cafe),
    ));
    final image = tester.widget<Image>(find.byType(Image));
    final fallback = image.errorBuilder!(
      tester.element(find.byType(Image)),
      Exception('network'),
      StackTrace.empty,
    );
    await tester.pumpWidget(MaterialApp(home: fallback));
    expect(find.byKey(const Key('place_photo_fallback_cover')), findsOneWidget);
    expect(find.byIcon(Icons.coffee_rounded), findsOneWidget);
  });

  testWidgets('URL insegura nunca cria requisição de imagem', (tester) async {
    const unsafe = PlacePhoto(
      id: 'unsafe',
      alt: 'Foto indisponível',
      color: 0xFF3157A4,
      url: 'http://example.com/place.jpg',
    );
    await tester.pumpWidget(const MaterialApp(
      home: PlaceCover(photo: unsafe, category: PlaceCategory.restaurant),
    ));
    expect(find.byType(Image), findsNothing);
    expect(
        find.byKey(const Key('place_photo_fallback_unsafe')), findsOneWidget);
  });
}
