import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/widgets/events/event_search_sheet_chrome.dart';

void _bindIphoneProView(
  WidgetTester tester, {
  double topInset = 59,
  double bottomInset = 34,
  double keyboard = 0,
}) {
  const dpr = 3.0;
  tester.view.physicalSize = const Size(393 * dpr, 852 * dpr);
  tester.view.devicePixelRatio = dpr;
  // FlutterView.padding é em pixels físicos.
  tester.view.padding = FakeViewPadding(
    top: topInset * dpr,
    bottom: bottomInset * dpr,
  );
  tester.view.viewPadding = FakeViewPadding(
    top: topInset * dpr,
    bottom: bottomInset * dpr,
  );
  tester.view.viewInsets = keyboard > 0
      ? FakeViewPadding(bottom: keyboard * dpr)
      : FakeViewPadding.zero;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);
  addTearDown(tester.view.resetViewPadding);
  addTearDown(tester.view.resetViewInsets);
}

void main() {
  testWidgets(
    'modal com padding herdado zerado: Voltar/Cancelar abaixo do inset físico e tocáveis',
    (tester) async {
      const topInset = 59.0;
      _bindIphoneProView(tester, topInset: topInset);

      Object? popped = 'sentinel';

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: const Key('open_sheet'),
                    onPressed: () async {
                      popped = await showModalBottomSheet<Object?>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: false,
                        backgroundColor: Colors.white,
                        builder: (sheetContext) {
                          // Simula MediaQuery do modal: padding/viewPadding zerados.
                          final stripped = MediaQuery.of(sheetContext).copyWith(
                            padding: EdgeInsets.zero,
                            viewPadding: EdgeInsets.zero,
                          );
                          return MediaQuery(
                            data: stripped,
                            child: EventSearchSheetChrome(
                              title: 'Nome do local',
                              cancelLabel: 'Cancelar',
                              searchField: const TextField(
                                key: Key('event_place_search'),
                                decoration: InputDecoration(
                                  labelText: 'Nome do local',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                              body: const Center(
                                child: Text('Digite pelo menos 2 letras'),
                              ),
                            ),
                          );
                        },
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open_sheet')));
      await tester.pumpAndSettle();

      // fromView deve ler o inset físico mesmo com MQ herdado zerado.
      expect(
        EventSearchSheetChrome.physicalTopInset(
          tester.element(find.byType(EventSearchSheetChrome)),
        ),
        topInset,
      );

      final backTop = tester
          .getTopLeft(find.byKey(const Key('event_search_sheet_back')))
          .dy;
      final cancelTop = tester
          .getTopLeft(find.byKey(const Key('event_search_sheet_cancel')))
          .dy;

      expect(
        backTop,
        greaterThanOrEqualTo(topInset + EventSearchSheetChrome.topGap - 0.5),
        reason: 'Voltar abaixo do relógio / Dynamic Island',
      );
      expect(
        cancelTop,
        greaterThanOrEqualTo(topInset + EventSearchSheetChrome.topGap - 0.5),
        reason: 'Cancelar abaixo de sinal / bateria',
      );

      final backSize =
          tester.getSize(find.byKey(const Key('event_search_sheet_back')));
      final cancelSize =
          tester.getSize(find.byKey(const Key('event_search_sheet_cancel')));
      expect(backSize.height, greaterThanOrEqualTo(48));
      expect(cancelSize.height, greaterThanOrEqualTo(48));

      // Toque em Voltar fecha a folha.
      await tester.tap(find.byKey(const Key('event_search_sheet_back')));
      await tester.pumpAndSettle();
      expect(find.byType(EventSearchSheetChrome), findsNothing);
      expect(popped, isNull);

      // Reabre e toca Cancelar.
      popped = 'sentinel';
      await tester.tap(find.byKey(const Key('open_sheet')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('event_search_sheet_cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(EventSearchSheetChrome), findsNothing);
      expect(popped, isNull);
    },
  );

  testWidgets(
    'header permanece abaixo do inset físico com teclado aberto',
    (tester) async {
      const topInset = 59.0;
      const keyboard = 336.0;
      _bindIphoneProView(tester, topInset: topInset, keyboard: keyboard);

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(
            size: Size(393, 852),
            padding: EdgeInsets.zero,
            viewPadding: EdgeInsets.zero,
            viewInsets: EdgeInsets.only(bottom: keyboard),
            devicePixelRatio: 3,
          ),
          child: MaterialApp(
            home: Scaffold(
              body: EventSearchSheetChrome(
                title: 'Cidade',
                searchField: const TextField(
                  key: Key('event_city_search'),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(),
                  ),
                ),
                body: const Center(child: Text('Digite pelo menos 2 letras')),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final backTop = tester
          .getTopLeft(find.byKey(const Key('event_search_sheet_back')))
          .dy;
      expect(backTop, greaterThanOrEqualTo(topInset));
      expect(
        tester.getRect(find.byKey(const Key('event_search_sheet_back'))).bottom,
        lessThanOrEqualTo(852 - keyboard + 0.5),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Cancel with focused keyboard closes sheet and returns null',
    (tester) async {
      _bindIphoneProView(tester);
      Object? popped = 'sentinel';
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: const Key('open_sheet'),
                    onPressed: () async {
                      popped = await showModalBottomSheet<Object?>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: false,
                        builder: (_) => EventSearchSheetChrome(
                          title: 'Nome do local',
                          cancelLabel: 'Cancelar',
                          searchField: const TextField(
                            key: Key('event_place_search'),
                            autofocus: true,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(),
                            ),
                          ),
                          body: const Center(child: Text('resultados')),
                        ),
                      );
                    },
                    child: const Text('open'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('open_sheet')));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      await tester.pump();

      await tester.tap(find.byKey(const Key('event_search_sheet_cancel')));
      await tester.pumpAndSettle();
      expect(popped, isNull);
    },
  );
}
