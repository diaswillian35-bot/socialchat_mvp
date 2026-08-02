/// Decisões puras do botão/gesto Voltar do Android (Parte 4A).
///
/// Não altera a seta interna do AppBar. Não toca em presença RTDB.
enum AndroidBackDecision {
  /// Teclado visível: fechar primeiro.
  dismissKeyboard,

  /// Aba principal ≠ Home: voltar para a Home.
  goHomeTab,

  /// Na Home: primeiro toque → mensagem “toque novamente”.
  showExitHint,

  /// Segundo toque dentro da janela → permitir sair.
  allowExit,
}

class AndroidBackNavigation {
  AndroidBackNavigation._();

  /// Janela para o segundo toque confirmar saída.
  static const Duration exitConfirmWindow = Duration(seconds: 2);

  /// Índice da aba Home no [MainShell].
  static const int homeTabIndex = 0;

  static bool isKeyboardOpen(double viewInsetsBottom) =>
      viewInsetsBottom > 0.5;

  /// Navegação interna (voltar entre páginas/abas) NÃO deve afetar presença.
  static bool shouldAffectPresenceOnInternalBack() => false;

  static AndroidBackDecision decide({
    required bool keyboardOpen,
    required int currentTabIndex,
    required DateTime? lastExitPromptAt,
    required DateTime now,
  }) {
    if (keyboardOpen) return AndroidBackDecision.dismissKeyboard;
    if (currentTabIndex != homeTabIndex) {
      return AndroidBackDecision.goHomeTab;
    }
    if (lastExitPromptAt != null &&
        now.difference(lastExitPromptAt) <= exitConfirmWindow) {
      return AndroidBackDecision.allowExit;
    }
    return AndroidBackDecision.showExitHint;
  }

  /// Destino seguro após push/deep link: sempre há MainShell sob a rota.
  static bool isSafeBackStack({
    required bool shellUnderDestination,
  }) =>
      shellUnderDestination;
}
