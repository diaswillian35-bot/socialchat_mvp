import 'package:flutter/foundation.dart';

/// Visibilidade do botão Enviar vs microfone no composer.
/// Espaços isolados não contam como mensagem enviável.
@immutable
class ChatComposerText {
  const ChatComposerText._();

  static bool hasSendableText(String value) => value.trim().isNotEmpty;
}
