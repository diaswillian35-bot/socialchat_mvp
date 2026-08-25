import 'package:flutter/material.dart';

import 'keyboard_dismiss.dart';

/// Lifts chat composer above the soft keyboard without relying on a parent
/// [Scaffold.resizeToAvoidBottomInset] (nested shell often breaks that).
///
/// Uses [MediaQuery.viewInsets] only — no artificial delay.
class ChatComposerAboveKeyboard extends StatelessWidget {
  const ChatComposerAboveKeyboard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: child,
    );
  }
}

/// Chat route shell: dismiss keyboard on outside tap / Android back before pop.
class ChatKeyboardScope extends StatelessWidget {
  const ChatKeyboardScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0.5;
    return PopScope(
      key: const ValueKey('chat_keyboard_scope'),
      canPop: !keyboardOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        dismissAppKeyboard();
      },
      child: KeyboardDismissOnTap(child: child),
    );
  }
}
