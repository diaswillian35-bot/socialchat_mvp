import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/widgets/password_visibility_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('show and hide keeps the password text and cursor',
      (tester) async {
    final handle = tester.ensureSemantics();
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    try {
      await tester.pumpWidget(_PasswordHost(controller: controller));
      controller.value = const TextEditingValue(
        text: 'segredo',
        selection: TextSelection.collapsed(offset: 3),
      );
      await tester.pump();

      expect(
          tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
      expect(find.byTooltip('Mostrar senha'), findsOneWidget);
      expect(
        tester.getSemantics(find.byType(IconButton)),
        matchesSemantics(
          label: 'Mostrar senha',
          tooltip: 'Mostrar senha',
          isButton: true,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
          hasFocusAction: true,
          isFocusable: true,
        ),
      );

      await tester.tap(find.byTooltip('Mostrar senha'));
      await tester.pump();

      expect(controller.text, 'segredo');
      expect(controller.selection, const TextSelection.collapsed(offset: 3));
      expect(tester.widget<TextField>(find.byType(TextField)).obscureText,
          isFalse);
      expect(find.byTooltip('Ocultar senha'), findsOneWidget);

      await tester.tap(find.byTooltip('Ocultar senha'));
      await tester.pump();

      expect(controller.text, 'segredo');
      expect(controller.selection, const TextSelection.collapsed(offset: 3));
      expect(
          tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
      expect(find.byTooltip('Mostrar senha'), findsOneWidget);
    } finally {
      handle.dispose();
    }
  });
}

class _PasswordHost extends StatefulWidget {
  const _PasswordHost({required this.controller});

  final TextEditingController controller;

  @override
  State<_PasswordHost> createState() => _PasswordHostState();
}

class _PasswordHostState extends State<_PasswordHost> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: TextField(
          controller: widget.controller,
          obscureText: _hidden,
          decoration: InputDecoration(
            suffixIcon: PasswordVisibilityButton(
              obscured: _hidden,
              showLabel: 'Mostrar senha',
              hideLabel: 'Ocultar senha',
              onPressed: () {
                PasswordFieldCursor.toggle(
                  controller: widget.controller,
                  applyToggle: () => setState(() => _hidden = !_hidden),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
