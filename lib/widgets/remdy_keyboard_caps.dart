import 'package:flutter/services.dart';

/// Keyboard capitalization hints only. Never mutates typed or stored text.
class RemdyKeyboardCaps {
  RemdyKeyboardCaps._();

  static const sentences = TextCapitalization.sentences;
  static const words = TextCapitalization.words;
  static const none = TextCapitalization.none;
}
