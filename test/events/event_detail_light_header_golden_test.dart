import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/widgets/events/event_detail_light_header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpHeader(WidgetTester tester, {Widget? cover}) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: EventDetailLightHeader(
            title: 'ExpoCampo 2027',
            locationLine: 'Campo Mourão - PR',
            dateLine: '10 a 14 de março de 2027',
            confirmed: true,
            cancelled: false,
            liked: false,
            confirmedLabel: 'EVENTO CONFIRMADO',
            cancelledLabel: 'Cancelado',
            coverChild: cover,
            onBack: () {},
            onShare: () {},
            onLike: () {},
            heroHeight: 260,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('golden bright cover to white', (tester) async {
    await pumpHeader(tester, cover: const ColoredBox(color: Color(0xFFE8F0FF)));
    await expectLater(
      find.byType(EventDetailLightHeader),
      matchesGoldenFile('goldens/hero_light_bright.png'),
    );
  });

  testWidgets('golden dark cover to white', (tester) async {
    await pumpHeader(tester, cover: const ColoredBox(color: Color(0xFF1A2038)));
    await expectLater(
      find.byType(EventDetailLightHeader),
      matchesGoldenFile('goldens/hero_light_dark.png'),
    );
  });

  testWidgets('golden vertical-ish cover', (tester) async {
    await pumpHeader(tester, cover: const ColoredBox(color: Color(0xFF88AADD)));
    await expectLater(
      find.byType(EventDetailLightHeader),
      matchesGoldenFile('goldens/hero_light_vertical.png'),
    );
  });

  testWidgets('golden square-ish cover', (tester) async {
    await pumpHeader(tester, cover: const ColoredBox(color: Color(0xFFAACCAA)));
    await expectLater(
      find.byType(EventDetailLightHeader),
      matchesGoldenFile('goldens/hero_light_square.png'),
    );
  });

  testWidgets('golden no cover fallback', (tester) async {
    await pumpHeader(tester);
    await expectLater(
      find.byType(EventDetailLightHeader),
      matchesGoldenFile('goldens/hero_light_no_cover.png'),
    );
  });

  testWidgets('long title readable no exception', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventDetailLightHeader(
            title:
                'Festival Internacional de Cultura e Gastronomia da Comunidade Remdy 2027',
            locationLine: 'São Paulo - SP',
            dateLine: '10 a 14 de março de 2027 • 20:00',
            confirmed: true,
            cancelled: false,
            liked: true,
            confirmedLabel: 'EVENTO CONFIRMADO',
            cancelledLabel: 'Cancelado',
            coverChild: const ColoredBox(color: Color(0xFFCCDDEE)),
            onBack: () {},
            onShare: () {},
            onLike: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Festival Internacional'), findsOneWidget);
  });
}
