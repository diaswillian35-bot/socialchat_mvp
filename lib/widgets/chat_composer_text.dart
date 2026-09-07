import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/message_link_utils.dart';

/// Visibilidade do botão Enviar vs microfone no composer.
/// Espaços isolados não contam como mensagem enviável.
///
/// Capitalização: a app garante maiúscula na primeira letra alfabética
/// (Unicode), além de [keyboardCapitalization] no teclado.
@immutable
class ChatComposerText {
  const ChatComposerText._();

  /// Auxílio do teclado; não é garantia (depende do aparelho).
  static const TextCapitalization keyboardCapitalization =
      TextCapitalization.sentences;

  /// Formatter para digitação e colagem no composer.
  static final TextInputFormatter leadingAlphaCapitalizationFormatter =
      _LeadingAlphaCapitalizationFormatter();

  static bool hasSendableText(String value) => value.trim().isNotEmpty;

  /// Capitaliza a primeira letra alfabética sem remover prefixos
  /// (espaços, emojis). Não altera links, menções (`@`), nem o restante.
  static String capitalizeLeadingAlpha(String input) {
    if (input.isEmpty) return input;

    final match = _letterPattern.firstMatch(input);
    if (match == null) return input;

    final start = match.start;
    final end = match.end;

    // Menção: não alterar o handle após @.
    if (start > 0 && input.codeUnitAt(start - 1) == 0x40 /* @ */) {
      return input;
    }

    // Não alterar letra que faz parte de um link detectado.
    for (final link in MessageLinkUtils.extractLinks(input)) {
      if (start >= link.start && start < link.end) {
        return input;
      }
    }

    final letter = input.substring(start, end);
    final upper = letter.toUpperCase();
    if (letter == upper) return input;

    return '${input.substring(0, start)}$upper${input.substring(end)}';
  }

  /// Texto pronto para envio: trim + capitalização garantida.
  static String prepareOutgoingText(String raw) {
    return capitalizeLeadingAlpha(raw.trim());
  }

  static final RegExp _letterPattern = RegExp(r'\p{L}', unicode: true);
}

class _LeadingAlphaCapitalizationFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final capped = ChatComposerText.capitalizeLeadingAlpha(newValue.text);
    if (capped == newValue.text) {
      return newValue;
    }

    final delta = capped.length - newValue.text.length;
    TextSelection selection = newValue.selection;
    if (selection.isValid) {
      final base = (selection.baseOffset + delta).clamp(0, capped.length);
      final extent = (selection.extentOffset + delta).clamp(0, capped.length);
      selection = TextSelection(
        baseOffset: base,
        extentOffset: extent,
        affinity: selection.affinity,
        isDirectional: selection.isDirectional,
      );
    }

    return TextEditingValue(
      text: capped,
      selection: selection,
      composing: TextRange.empty,
    );
  }
}
