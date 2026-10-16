import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/locais_feature_flag.dart';
import 'package:socialchat_mvp/features/locais/shell_pages.dart';
import 'package:socialchat_mvp/features/locais/ui/locais_detail_page.dart';
import 'package:socialchat_mvp/features/locais/ui/locais_list_page.dart';
import 'package:socialchat_mvp/pages/main_shell_page.dart';

import 'locais_test_support.dart';

void main() {
  tearDown(LocaisFeatureFlag.resetDebugOverride);

  group('Navegação do shell', () {
    test('flag desligada mantém as quatro abas e os índices atuais', () {
      final pages = buildMainShellPages(
        locaisEnabled: false,
        home: const Text('home'),
        messages: const Text('messages'),
        groups: const Text('groups'),
        events: const Text('events'),
        locais: const LocaisListPage(),
      );
      expect(pages, hasLength(4));
      expect(pages.whereType<LocaisListPage>(), isEmpty);
      expect(MainShell.homeTabIndex, 0);
      expect(MainShell.eventsTabIndex, 3);
      expect(MainShell.locaisTabIndex, 4);
      expect(MainShellDestinations.tabCount(locaisEnabled: false), 4);
      expect(MainShellDestinations.initialIndex(4, locaisEnabled: false), 0);
      expect(MainShellDestinations.initialIndex(3, locaisEnabled: false), 3);
      expect(MainShellDestinations.canSelect(4, locaisEnabled: false), isFalse);
      expect(MainShellDestinations.canSelect(2, locaisEnabled: false), isTrue);
    });

    test('flag ligada acrescenta Locais sem tirar as abas existentes', () {
      final pages = buildMainShellPages(
        locaisEnabled: true,
        home: const Text('home'),
        messages: const Text('messages'),
        groups: const Text('groups'),
        events: const Text('events'),
        locais: const LocaisListPage(),
      );
      expect(pages, hasLength(5));
      expect(pages.last, isA<LocaisListPage>());
      expect(MainShellDestinations.tabCount(locaisEnabled: true), 5);
      expect(MainShellDestinations.canSelect(4, locaisEnabled: true), isTrue);
      expect(MainShellDestinations.initialIndex(4, locaisEnabled: true), 4);
      expect(MainShellDestinations.initialIndex(9, locaisEnabled: true), 0);
    });

    test('o shell só monta Locais dentro da flag', () {
      final shell = File('lib/pages/main_shell_page.dart').readAsStringSync();
      expect(shell.contains('const EventsPage()'), isTrue);
      expect(shell.contains('const MessagesPage()'), isTrue);
      expect(shell.contains('GroupsListPage('), isTrue);
      expect(shell.contains('HomePage('), isTrue);
      expect(shell.contains('IndexedStack('), isTrue);
      expect(shell.contains('onTap: _selectTab'), isTrue);
      expect(shell.contains('if (locaisEnabled)'), isTrue);
      expect(shell.contains('buildMainShellPages('), isTrue);
      expect(shell.contains('LocaisFeatureFlag.isEnabled'), isTrue);
    });
  });

  testWidgets('flag desligada não desenha Locais', (tester) async {
    await pumpLocais(tester, const LocaisListPage(), enabled: false);
    expect(find.byKey(const Key('locais_disabled')), findsOneWidget);
    expect(find.text('Locais'), findsNothing);
    expect(find.text('Casa do Sabor'), findsNothing);
    expect(find.byType(BottomNavigationBar), findsNothing);
  });

  testWidgets('lista abre o detalhe e volta', (tester) async {
    await pumpLocais(tester, demoList());
    await tester.pumpAndSettle();

    expect(find.text('Locais'), findsOneWidget);
    expect(find.text('Casa do Sabor'), findsOneWidget);
    expect(find.text('Aberto'), findsWidgets);
    expect(find.text('4,6 · 128'), findsOneWidget);

    await tester.tap(find.byKey(const Key('place_card_casa_do_sabor')));
    await tester.pumpAndSettle();

    expect(find.byType(LocaisDetailPage), findsOneWidget);
    Future<void> see(Key key) async {
      final target = find.byKey(key);
      for (var attempt = 0;
          attempt < 8 && target.evaluate().isEmpty;
          attempt++) {
        await tester.drag(
          find.byKey(const Key('locais_detail_scroll')),
          const Offset(0, -320),
        );
        await tester.pumpAndSettle();
      }
      expect(target, findsOneWidget);
    }

    await see(const Key('locais_detail_photos'));
    await see(const Key('locais_detail_description'));
    await see(const Key('locais_detail_map'));
    await see(const Key('locais_detail_address'));
    expect(
      find.text('Rua das Flores, 120, Centro, Florianópolis, Santa Catarina'),
      findsOneWidget,
    );
    await see(const Key('locais_detail_contact'));
    await see(const Key('locais_detail_hours'));
    await see(const Key('locais_detail_accessibility'));
    await see(const Key('locais_detail_reviews'));
    expect(find.textContaining('Ana Lima'), findsOneWidget);
    await see(const Key('locais_detail_events'));
    expect(find.textContaining('Noite de jazz'), findsOneWidget);

    await see(const Key('merchant_portal_plan'));
    expect(
      find.textContaining('https://remdy.app/portal/locais/casa_do_sabor'),
      findsOneWidget,
    );
    expect(
      find.textContaining('https://remdy.app/l/casa_do_sabor'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(LocaisDetailPage),
        matching: find.byType(TextField),
      ),
      findsNothing,
    );

    await tester.ensureVisible(find.byKey(const Key('merchant_portal_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merchant_portal_button')));
    await tester.pumpAndSettle();
    expect(find.text('Reivindicar este local'), findsWidgets);
    expect(find.byType(TextField), findsNWidgets(2));
    await tester.tap(find.text('Cancelar').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(LocaisDetailPage), findsNothing);
    expect(find.byKey(const Key('place_card_casa_do_sabor')), findsOneWidget);
  });
}
