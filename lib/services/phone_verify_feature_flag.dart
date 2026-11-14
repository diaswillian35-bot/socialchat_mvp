/// Verificação por telefone (selo SMS) fica desligada nos builds até
/// o provedor Phone ser ligado no Firebase.
///
/// Só liga com `--dart-define=REMDY_PHONE_VERIFY_ENABLED=true`.
/// O valor compilado padrão é falso. [debugOverride] existe para testes
/// e começa nulo; nenhum outro arquivo de `lib/` deve atribuí-lo.
class PhoneVerifyFeatureFlag {
  PhoneVerifyFeatureFlag._();

  static const String defineKey = 'REMDY_PHONE_VERIFY_ENABLED';

  static const bool compiledEnabled = bool.fromEnvironment(
    defineKey,
    defaultValue: false,
  );

  static bool? debugOverride;

  static bool get isEnabled => debugOverride ?? compiledEnabled;

  static void resetDebugOverride() {
    debugOverride = null;
  }

  /// Mostra a entrada do menu: começar a verificação se a flag estiver
  /// ligada, ou abrir a tela para desvincular se a conta já for
  /// verificada (`publicUsers.verified`).
  static bool showMenuEntry({required bool alreadyVerified}) =>
      isEnabled || alreadyVerified;
}
