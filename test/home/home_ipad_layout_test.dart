import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/widgets/home_body_scroll_layout.dart';

void main() {
  String readHome() => File('lib/pages/home_page.dart').readAsStringSync();

  test('Home usa layout scroll/SafeArea sem mudar ordem BR/CA/PT', () {
    final home = readHome();
    expect(home, contains('HomeBodyScrollLayout'));
    expect(home, contains('SafeArea('));
    expect(home, contains("code: 'BR'"));
    expect(home, contains("code: 'CA'"));
    expect(home, contains("code: 'PT'"));
    expect(home, contains('HomeDiscoverSection('));
    expect(home, contains('HomeNearbyUsersSection('));
    expect(home, contains('top: false'));
    expect(home, contains('bottom: false'));
  });

  test('grelha: retrato quadrado, paisagem mais baixa, 3 colunas', () {
    expect(
      HomeBodyScrollLayout.countryGridChildAspectRatio(
        HomeBodyScrollLayout.ipadAir11Portrait,
      ),
      HomeBodyScrollLayout.portraitCountryAspect,
    );
    expect(
      HomeBodyScrollLayout.countryGridChildAspectRatio(
        HomeBodyScrollLayout.ipadAir11Landscape,
      ),
      HomeBodyScrollLayout.landscapeCountryAspect,
    );
    expect(HomeBodyScrollLayout.countryCrossAxisCount, 3);
    expect(
      HomeBodyScrollLayout.landscapeCountryAspect,
      greaterThan(HomeBodyScrollLayout.portraitCountryAspect),
    );
  });

  testWidgets(
    'iPad Air 11 retrato: Discover e último bloco acima da tab bar',
    (tester) async {
      await _pumpIpadHomeHarness(
        tester,
        HomeBodyScrollLayout.ipadAir11Portrait,
      );
      await _expectDiscoverAndTailAboveTabBar(tester);
    },
  );

  testWidgets(
    'iPad Air 11 paisagem: Discover visível acima da tab bar; scroll não esconde o fim',
    (tester) async {
      await _pumpIpadHomeHarness(
        tester,
        HomeBodyScrollLayout.ipadAir11Landscape,
      );
      await _expectDiscoverFullyAboveTabBar(tester);

      await tester.drag(find.byType(ListView), const Offset(0, -2400));
      await tester.pumpAndSettle();
      await _expectTailFullyAboveTabBar(tester);
    },
  );
}

Future<void> _pumpIpadHomeHarness(WidgetTester tester, Size logical) async {
  final dpr = tester.view.devicePixelRatio;
  tester.view.physicalSize = logical * dpr;
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: logical,
          devicePixelRatio: dpr,
        ),
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: 88,
            title: const Text('Home'),
          ),
          body: SafeArea(
            top: false,
            bottom: false,
            child: ListView(
              padding: HomeBodyScrollLayout.listPadding(),
              children: [
                const Text('Hello, Ana Ribeiro'),
                const SizedBox(height: 8),
                Container(
                  height: 88,
                  alignment: Alignment.centerLeft,
                  child: const Text('Live now'),
                ),
                const SizedBox(height: 12),
                const Text('Meet People'),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 3,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: HomeBodyScrollLayout.countryCrossAxisCount,
                    mainAxisSpacing: HomeBodyScrollLayout.countryGridSpacing,
                    crossAxisSpacing: HomeBodyScrollLayout.countryGridSpacing,
                    childAspectRatio:
                        HomeBodyScrollLayout.countryGridChildAspectRatio(
                      logical,
                    ),
                  ),
                  itemBuilder: (_, i) => Container(
                    key: ValueKey('country-$i'),
                    color: const Color(0xFFF8FAFC),
                    alignment: Alignment.center,
                    child: Text(['Brazil', 'Canada', 'Portugal'][i]),
                  ),
                ),
                const SizedBox(height: 16),
                const KeyedSubtree(
                  key: ValueKey('discover-header'),
                  child: Text('Discover'),
                ),
                const SizedBox(height: 8),
                Container(
                  key: const ValueKey('discover-card'),
                  height: 210,
                  color: const Color(0xFFE2E8F0),
                  alignment: Alignment.bottomLeft,
                  child: const Text('Evento Demonstrativo Remdy'),
                ),
                const SizedBox(height: 16),
                Container(
                  key: const ValueKey('nearby-tail'),
                  height: 96,
                  alignment: Alignment.bottomLeft,
                  child: const Text('New users in your city'),
                ),
              ],
            ),
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: 0,
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_rounded),
                label: 'Home',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.chat_bubble_rounded),
                label: 'Messages',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.groups_rounded),
                label: 'Groups',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.event_rounded),
                label: 'Events',
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expectDiscoverFullyAboveTabBar(WidgetTester tester) async {
  final tabTop = tester.getTopLeft(find.byType(BottomNavigationBar)).dy;
  final card = tester.getRect(find.byKey(const ValueKey('discover-card')));
  expect(card.bottom, lessThanOrEqualTo(tabTop + 0.5),
      reason: 'cartão Discover encoberto pela tab bar (bottom=${card.bottom} tabTop=$tabTop)');
  expect(tester.takeException(), isNull);
}

Future<void> _expectDiscoverAndTailAboveTabBar(WidgetTester tester) async {
  await _expectDiscoverFullyAboveTabBar(tester);
  final tabTop = tester.getTopLeft(find.byType(BottomNavigationBar)).dy;
  final nearby = tester.getRect(find.byKey(const ValueKey('nearby-tail')));
  if (nearby.bottom > tabTop + 0.5) {
    await tester.drag(find.byType(ListView), const Offset(0, -2400));
    await tester.pumpAndSettle();
  }
  await _expectTailFullyAboveTabBar(tester);
}

Future<void> _expectTailFullyAboveTabBar(WidgetTester tester) async {
  final tabTop = tester.getTopLeft(find.byType(BottomNavigationBar)).dy;
  final nearby = tester.getRect(find.byKey(const ValueKey('nearby-tail')));
  expect(nearby.bottom, lessThanOrEqualTo(tabTop + 0.5),
      reason: 'fim da Home oculto pela tab bar (bottom=${nearby.bottom} tabTop=$tabTop)');
  expect(tester.takeException(), isNull);
}
