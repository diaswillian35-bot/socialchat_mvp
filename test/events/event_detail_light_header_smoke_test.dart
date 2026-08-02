import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/widgets/events/event_detail_light_header.dart';

void main() {
  testWidgets('light header renders title on white meta', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EventDetailLightHeader(
            title: 'ExpoCampo 2027',
            locationLine: 'Campo Mourão - PR',
            dateLine: '10 a 14 de março de 2027',
            confirmed: true,
            cancelled: false,
            liked: false,
            confirmedLabel: 'EVENTO CONFIRMADO',
            cancelledLabel: 'Cancelado',
            coverChild: const ColoredBox(color: Color(0xFFE8F0FF)),
            onBack: () {},
            onShare: null,
            onLike: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('ExpoCampo 2027'), findsOneWidget);
    expect(find.text('EVENTO CONFIRMADO'), findsOneWidget);
    expect(find.text('Campo Mourão - PR'), findsOneWidget);
    expect(find.byIcon(Icons.ios_share_rounded), findsNothing);
    expect(find.byIcon(Icons.arrow_back_ios_new_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
