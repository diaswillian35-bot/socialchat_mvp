import 'package:flutter/material.dart';

/// Wordmark Remdy — mesmo asset e altura usados em Eventos.
class RemdyLogo extends StatelessWidget {
  const RemdyLogo({
    super.key,
    this.height = 60,
  });

  /// Altura padrão da Home/Eventos (wordmark escrito).
  static const double defaultHeight = 60;

  static const String assetPath = 'assets/remdy_logo.png';

  final double height;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      height: height,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      semanticLabel: 'Remdy',
    );
  }
}
