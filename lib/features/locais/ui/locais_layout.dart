import 'package:flutter/material.dart';

class LocaisColors {
  LocaisColors._();

  static const Color navy = Color(0xFF313A5F);
  static const Color logoBlue = Color(0xFF264E9A);
  static const Color bg = Color(0xFFF6F7FB);
  static const Color text = Color(0xFF111827);
  static const Color muted = Color(0xFF6B7280);
  static const Color border = Color(0xFFE5E7EB);
  static const Color open = Color(0xFF16A34A);
  static const Color card = Colors.white;
}

class LocaisLayout {
  LocaisLayout._();

  static int columnsForWidth(double width) {
    if (width >= 1000) return 3;
    if (width >= 700) return 2;
    return 1;
  }

  /// iPad largo mostra a lista e o mapa ao mesmo tempo.
  static bool splitMap(double width) => width >= 900;
}
