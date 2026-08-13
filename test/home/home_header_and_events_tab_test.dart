import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/pages/main_shell_page.dart';
import 'package:socialchat_mvp/services/android_back_navigation.dart';
import 'package:socialchat_mvp/widgets/home_section_header.dart';
import 'package:socialchat_mvp/widgets/remdy_logo.dart';

class _RouteRecorder extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

void main() {
  String readHome() => File('lib/pages/home_page.dart').readAsStringSync();
  String readShell() => File('lib/pages/main_shell_page.dart').readAsStringSync();
  String readDiscover() =>
      File('lib/widgets/home_discover_section.dart').readAsStringSync();
  String readNearby() =>
      File('lib/widgets/home_nearby_users_section.dart').readAsStringSync();

  group('Home header sem Remi', () {
    test('atalho Remi ausente; menu, logo e avatar permanecem', () {
      final home = readHome();
      expect(home.contains('RemiEntryPage'), isFalse);
      expect(home.contains("'Remi'"), isFalse);
      expect(home.contains("import 'remi_entry_page.dart'"), isFalse);
      expect(home.contains('Icons.menu_rounded'), isTrue);
      expect(home.contains('RemdyLogo()'), isTrue);
      expect(home.contains('CircleAvatar('), isTrue);
      expect(home.contains('_openProfile'), isTrue);
      expect(home.contains('MenuPage('), isTrue);
    });

    test('páginas da Remi continuam no projeto', () {
      expect(File('lib/pages/remi_entry_page.dart').existsSync(), isTrue);
      expect(File('lib/pages/remi_chat_page.dart').existsSync(), isTrue);
      expect(File('lib/pages/remi_intro_page.dart').existsSync(), isTrue);
    });
  });

  group('Descubra → Ver todos seleciona aba Eventos', () {
    test('índice canônico da aba Eventos é 3', () {
      expect(MainShell.eventsTabIndex, 3);
      expect(MainShell.homeTabIndex, 0);
      expect(AndroidBackNavigation.homeTabIndex, MainShell.homeTabIndex);
    });

    test('shell troca aba pelo mesmo _selectTab do menu inferior', () {
      final shell = readShell();
      expect(shell.contains('IndexedStack('), isTrue);
      expect(shell.contains('const EventsPage()'), isTrue);
      expect(shell.contains('_selectTab(MainShell.eventsTabIndex)'), isTrue);
      expect(shell.contains('onTap: _selectTab'), isTrue);
      expect(shell.contains('EventsDiscoverPage'), isFalse);
    });

    test('Home Descubra não faz Navigator.push de página de eventos', () {
      final discover = readDiscover();
      expect(discover.contains('EventsDiscoverPage'), isFalse);
      expect(discover.contains('EventsPage('), isFalse);
      expect(discover.contains('onOpenEventsTab'), isTrue);
      expect(discover.contains('EventDetailPage('), isTrue);
    });

    test('HomePage encaminha onOpenEventsTab para Descubra', () {
      final home = readHome();
      expect(home.contains('onOpenEventsTab: widget.onOpenEventsTab'), isTrue);
      expect(home.contains('onOpenEventsTab'), isTrue);
    });

    test('demais CTAs da Home permanecem', () {
      final home = readHome();
      final nearby = readNearby();
      expect(home.contains('MenuPage('), isTrue);
      expect(home.contains('_openProfile'), isTrue);
      expect(home.contains('_openCountry'), isTrue);
      expect(nearby.contains('NearbyUsersPage('), isTrue);
      expect(nearby.contains('Navigator.push'), isTrue);
    });
  });

  testWidgets('menu, logo e avatar cabem no AppBar da Home', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            toolbarHeight: 88,
            centerTitle: true,
            leading: const Icon(Icons.menu_rounded),
            title: const RemdyLogo(),
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: 14),
                child: CircleAvatar(radius: 18),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.menu_rounded), findsOneWidget);
    expect(find.byType(RemdyLogo), findsOneWidget);
    expect(find.byType(CircleAvatar), findsOneWidget);
    expect(find.text('Remi'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Ver todos seleciona aba Eventos sem empilhar rota',
      (tester) async {
    final observer = _RouteRecorder();
    var index = 0;
    const eventsKey = ValueKey('events-tab');
    const homeKey = ValueKey('home-tab');

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: StatefulBuilder(
          builder: (context, setState) {
            return Scaffold(
              body: IndexedStack(
                index: index,
                children: [
                  KeyedSubtree(
                    key: homeKey,
                    child: Column(
                      children: [
                        const Text('Home'),
                        HomeSectionHeader(
                          title: 'Descubra',
                          seeAllLabel: 'Ver todos',
                          onSeeAll: () =>
                              setState(() => index = MainShell.eventsTabIndex),
                        ),
                      ],
                    ),
                  ),
                  const Text('Messages'),
                  const Text('Groups'),
                  const KeyedSubtree(
                    key: eventsKey,
                    child: Text('Events'),
                  ),
                ],
              ),
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: index,
                onTap: (i) => setState(() => index = i),
                type: BottomNavigationBarType.fixed,
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.chat_bubble_rounded),
                    label: 'Mensagem',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.groups_rounded),
                    label: 'Grupos',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.event_rounded),
                    label: 'Eventos',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

    final routesBefore = observer.pushed.length;
    expect(find.byKey(homeKey), findsOneWidget);
    expect(
      find.byKey(eventsKey, skipOffstage: false),
      findsOneWidget,
    );

    await tester.tap(find.text('Ver todos'));
    await tester.pump();

    expect(observer.pushed.length, routesBefore);
    expect(find.byKey(eventsKey), findsOneWidget);
    expect(
      find.byKey(eventsKey, skipOffstage: false),
      findsOneWidget,
    );
    final bar = tester.widget<BottomNavigationBar>(
      find.byType(BottomNavigationBar),
    );
    expect(bar.currentIndex, MainShell.eventsTabIndex);

    await tester.tap(find.byIcon(Icons.home_rounded));
    await tester.pump();
    expect(
      tester
          .widget<BottomNavigationBar>(find.byType(BottomNavigationBar))
          .currentIndex,
      MainShell.homeTabIndex,
    );
    expect(find.byKey(homeKey), findsOneWidget);
    expect(
      find.byKey(eventsKey, skipOffstage: false),
      findsOneWidget,
    );
  });

  test('voltar da aba Eventos volta para Home, sem rota extra', () {
    final fromEvents = AndroidBackNavigation.decide(
      keyboardOpen: false,
      currentTabIndex: MainShell.eventsTabIndex,
      lastExitPromptAt: null,
      now: DateTime(2026, 8, 12),
    );
    expect(fromEvents, AndroidBackDecision.goHomeTab);

    final fromHome = AndroidBackNavigation.decide(
      keyboardOpen: false,
      currentTabIndex: MainShell.homeTabIndex,
      lastExitPromptAt: null,
      now: DateTime(2026, 8, 12),
    );
    expect(fromHome, AndroidBackDecision.showExitHint);
  });
}
