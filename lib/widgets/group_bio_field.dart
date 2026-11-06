import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/group_create_flow.dart';
import 'remdy_keyboard_caps.dart';

/// Bio limits and counters use UTF-16, just like Dart/JavaScript String.length.
/// TextField's default maxLength counts grapheme clusters instead.
class GroupBioLengthFormatter extends TextInputFormatter {
  const GroupBioLengthFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length <= GroupCreateFlow.bioMaxLength ||
        newValue.text.length < oldValue.text.length) {
      return newValue;
    }
    // Reject the edit rather than cutting a surrogate pair or an emoji sequence.
    return oldValue;
  }
}

class GroupBioField extends StatelessWidget {
  const GroupBioField({
    super.key,
    required this.controller,
    required this.decoration,
  });

  final TextEditingController controller;
  final InputDecoration decoration;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        textCapitalization: RemdyKeyboardCaps.sentences,
        maxLines: 4,
        maxLength: GroupCreateFlow.bioMaxLength,
        maxLengthEnforcement: MaxLengthEnforcement.none,
        inputFormatters: const [GroupBioLengthFormatter()],
        buildCounter: (context,
                {required currentLength,
                required isFocused,
                required maxLength}) =>
            Text('${controller.text.length}/$maxLength'),
        decoration: decoration,
      );
}
