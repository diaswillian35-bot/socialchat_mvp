import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/widgets/events/event_detail_action_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child, {Size size = const Size(390, 120), double textScale = 1}) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          textScaler: TextScaler.linear(textScale),
        ),
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Center(child: child),
        ),
      ),
    );
  }

  EventDetailActionBar bar({
    bool favorited = false,
    bool participating = false,
    bool favoriteBusy = false,
    bool participateBusy = false,
    VoidCallback? onFavorite,
    VoidCallback? onParticipate,
  }) {
    return EventDetailActionBar(
      favoriteLabel: 'Favoritar',
      participateLabel: participating ? 'Participando' : 'Participar',
      shareLabel: 'Compartilhar',
      calendarLabel: 'Calendário',
      directionsLabel: 'Como chegar',
      favorited: favorited,
      participating: participating,
      favoriteBusy: favoriteBusy,
      participateBusy: participateBusy,
      shareBusy: false,
      calendarBusy: false,
      directionsEnabled: true,
      onFavorite: onFavorite ?? () {},
      onParticipate: onParticipate ?? () {},
      onShare: () {},
      onCalendar: () {},
      onDirections: () {},
    );
  }

  testWidgets('renders three actions only and highlights Participar',
      (tester) async {
    await tester.pumpWidget(wrap(bar()));
    await tester.pump();

    expect(find.text('Favoritar'), findsOneWidget);
    expect(find.text('Participar'), findsOneWidget);
    expect(find.text('Compartilhar'), findsOneWidget);
    expect(find.text('Calendário'), findsNothing);
    expect(find.text('Como chegar'), findsNothing);
    expect(find.byType(ListView), findsNothing);

    final materials = tester.widgetList<Material>(find.byType(Material)).toList();
    expect(
      materials.any((m) => m.color == EventDetailActionBar.actionBlue),
      isTrue,
    );
  });

  testWidgets('favorite shows filled icon when favorited', (tester) async {
    await tester.pumpWidget(wrap(bar(favorited: true)));
    await tester.pump();
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });

  testWidgets('favoriteBusy blocks double tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      wrap(bar(favoriteBusy: true, onFavorite: () => taps++)),
    );
    await tester.pump();
    await tester.tap(find.text('Favoritar'));
    await tester.pump();
    expect(taps, 0);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('narrow width and text scale no overflow', (tester) async {
    await tester.pumpWidget(
      wrap(bar(), size: const Size(320, 140), textScale: 1.3),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('golden light action bar three actions', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(bar()));
    await tester.pump();
    await expectLater(
      find.byType(EventDetailActionBar),
      matchesGoldenFile('goldens/action_bar_light.png'),
    );
  });

  testWidgets('golden light action bar favorited + participating',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 100));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      wrap(bar(favorited: true, participating: true)),
    );
    await tester.pump();
    await expectLater(
      find.byType(EventDetailActionBar),
      matchesGoldenFile('goldens/action_bar_light_active.png'),
    );
  });
}
