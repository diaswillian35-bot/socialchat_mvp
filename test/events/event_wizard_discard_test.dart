import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';
import 'package:socialchat_mvp/models/event_editorial_draft.dart';
import 'package:socialchat_mvp/widgets/events/event_editorial_wizard.dart';

void main() {
  setUpAll(() async {
    await AppTexts.load(const Locale('pt', 'BR'));
  });

  testWidgets(
    'Descartar alterações limpa dirty e fecha o editor (não fica preso)',
    (tester) async {
      var cancelled = false;
      const initial = EventEditorialDraft(
        countryCode: 'br',
        countryName: 'Brasil',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: EventEditorialWizard(
            initial: initial,
            isEdit: true,
            onSubmit: (_) async {},
            onCancel: () {
              cancelled = true;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final titleField = find.byType(TextField).first;
      await tester.enterText(titleField, 'Evento de teste');
      await tester.pump();

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('Descartar alterações?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('event_wizard_discard_confirm')));
      await tester.pumpAndSettle();

      expect(cancelled, isTrue);
      expect(find.text('Descartar alterações?'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sistema voltar + Descartar também fecha sem ficar preso no PopScope',
    (tester) async {
      var cancelled = false;
      const initial = EventEditorialDraft(
        countryCode: 'br',
        countryName: 'Brasil',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    key: const Key('open_editor'),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => EventEditorialWizard(
                            initial: initial,
                            isEdit: true,
                            onSubmit: (_) async {},
                            onCancel: () {
                              cancelled = true;
                              Navigator.of(context).pop();
                            },
                          ),
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
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('open_editor')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Mudança');
      await tester.pump();

      // canPop=false → didPop=false → diálogo de discard.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Descartar alterações?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('event_wizard_discard_confirm')));
      await tester.pumpAndSettle();

      expect(cancelled, isTrue);
      expect(find.text('Descartar alterações?'), findsNothing);
      expect(find.byKey(const Key('open_editor')), findsOneWidget);
    },
  );
}
