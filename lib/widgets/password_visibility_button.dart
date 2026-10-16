import 'package:flutter/material.dart';

/// Suffix control that shows or hides a password without replacing the field.
class PasswordVisibilityButton extends StatelessWidget {
  const PasswordVisibilityButton({
    super.key,
    required this.obscured,
    required this.onPressed,
    required this.showLabel,
    required this.hideLabel,
  });

  final bool obscured;
  final VoidCallback onPressed;
  final String showLabel;
  final String hideLabel;

  @override
  Widget build(BuildContext context) {
    final label = obscured ? showLabel : hideLabel;
    return IconButton(
      tooltip: label,
      onPressed: onPressed,
      icon: Icon(
        obscured ? Icons.visibility_off : Icons.visibility,
        semanticLabel: label,
      ),
    );
  }
}

/// Toggles obscure text and puts the same text and caret back afterwards.
class PasswordFieldCursor {
  static void toggle({
    required TextEditingController controller,
    required VoidCallback applyToggle,
  }) {
    final value = controller.value;
    applyToggle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final text = value.text;
      var selection = value.selection;
      if (!selection.isValid ||
          selection.start > text.length ||
          selection.end > text.length) {
        selection = TextSelection.collapsed(offset: text.length);
      }
      controller.value = TextEditingValue(
        text: text,
        selection: selection,
      );
    });
  }
}
