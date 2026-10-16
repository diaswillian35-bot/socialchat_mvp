/// Locais fica fora dos builds de produção e do binário enviado à Apple.
///
/// Só liga com `--dart-define=REMDY_LOCAIS_ENABLED=true` em builds de
/// desenvolvimento. O valor compilado padrão é falso. [debugOverride] existe
/// para testes e começa nulo; nenhum outro arquivo de `lib/` deve atribuí-lo.
class LocaisFeatureFlag {
  LocaisFeatureFlag._();

  static const String defineKey = 'REMDY_LOCAIS_ENABLED';

  static const bool compiledEnabled = bool.fromEnvironment(
    defineKey,
    defaultValue: false,
  );

  static bool? debugOverride;

  static bool get isEnabled => debugOverride ?? compiledEnabled;

  static void resetDebugOverride() {
    debugOverride = null;
  }
}
