import 'package:flutter/material.dart';

import '../pages/main_shell_page.dart';

/// Navegação segura para rotas abertas por push/deep link/convite.
///
/// Sempre deixa [MainShell] sob a destino, para o Voltar Android retornar
/// a uma tela do Remdy em vez de fechar o app.
class SafeRemdyNavigation {
  SafeRemdyNavigation._();

  static Future<void> openOverShell({
    required NavigatorState nav,
    required int shellIndex,
    required Widget page,
  }) async {
    final index = shellIndex.clamp(0, 3);
    nav.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => MainShell(initialIndex: index),
      ),
      (route) => false,
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    nav.push(MaterialPageRoute(builder: (_) => page));
  }

  /// Se não há rota para pop, volta ao shell (nunca [SystemNavigator.pop]).
  static void popOrShell(
    BuildContext context, {
    int shellIndex = 0,
  }) {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
      return;
    }
    nav.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => MainShell(initialIndex: shellIndex.clamp(0, 3)),
      ),
      (route) => false,
    );
  }
}
