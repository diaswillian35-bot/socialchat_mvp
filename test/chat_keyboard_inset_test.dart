import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/widgets/chat_keyboard_inset.dart';

void main() {
  Future<void> setPhoneSurface(WidgetTester tester, {double keyboard = 0}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = const FakeViewPadding(bottom: 34);
    tester.view.viewInsets = keyboard > 0
        ? FakeViewPadding(bottom: keyboard)
        : FakeViewPadding.zero;
    addTearDown(tester.view.reset);
  }

  testWidgets('ChatComposerAboveKeyboard pads by viewInsets.bottom',
      (tester) async {
    await setPhoneSurface(tester, keyboard: 320);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Column(
            children: [
              Expanded(child: ColoredBox(color: Colors.grey)),
              ChatComposerAboveKeyboard(
                child: SizedBox(
                  key: Key('composer'),
                  height: 56,
                  child: ColoredBox(color: Colors.blue),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final composer = tester.getRect(find.byKey(const Key('composer')));
    expect(composer.bottom, closeTo(844 - 320, 1));
    expect(composer.height, 56);
  });

  testWidgets('closing keyboard restores composer above home indicator',
      (tester) async {
    await setPhoneSurface(tester, keyboard: 300);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          resizeToAvoidBottomInset: false,
          body: Column(
            children: [
              Expanded(child: SizedBox.expand()),
              ChatComposerAboveKeyboard(
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    key: Key('composer'),
                    height: 48,
                    child: ColoredBox(color: Colors.green),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Keyboard open: padding typically collapses; composer sits on keyboard.
    expect(
      tester.getRect(find.byKey(const Key('composer'))).bottom,
      closeTo(844 - 300, 2),
    );

    tester.view.viewInsets = FakeViewPadding.zero;
    // Real devices restore padding.bottom from viewPadding when keyboard closes.
    tester.view.padding = const FakeViewPadding(bottom: 34);
    await tester.pumpAndSettle();

    expect(
      tester.getRect(find.byKey(const Key('composer'))).bottom,
      closeTo(844 - 34, 2),
    );
  });

  testWidgets('ChatKeyboardScope blocks pop while keyboard open', (tester) async {
    await setPhoneSurface(tester, keyboard: 280);

    await tester.pumpWidget(
      const MaterialApp(
        home: ChatKeyboardScope(
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            body: TextField(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scope = tester.widget<PopScope<dynamic>>(
      find.byKey(const ValueKey('chat_keyboard_scope')),
    );
    expect(scope.canPop, isFalse);

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pumpAndSettle();
    final scopeClosed = tester.widget<PopScope<dynamic>>(
      find.byKey(const ValueKey('chat_keyboard_scope')),
    );
    expect(scopeClosed.canPop, isTrue);
  });

  test('MainShell does not resize for keyboard (source contract)', () {
    final src = File('lib/pages/main_shell_page.dart').readAsStringSync();
    expect(src.contains('resizeToAvoidBottomInset: false'), isTrue);
  });

  test('DM and group chat use manual composer keyboard inset', () {
    final dm = File('lib/pages/chat_page.dart').readAsStringSync();
    final group = File('lib/pages/group_chat_page.dart').readAsStringSync();
    for (final src in [dm, group]) {
      expect(src.contains('ChatComposerAboveKeyboard'), isTrue);
      expect(src.contains('ChatKeyboardScope'), isTrue);
      expect(src.contains('resizeToAvoidBottomInset: false'), isTrue);
    }
  });
}
