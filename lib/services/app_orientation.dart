import 'package:flutter/services.dart';

/// Orientação oficial do Remdy nesta versão: somente vertical em celulares.
///
/// Usamos apenas [DeviceOrientation.portraitUp] (não `portraitDown`) para
/// evitar comportamento estranho em câmera, seletor de fotos e pré-visualização
/// de mídia. Android/iOS nativos devem espelhar esta política.
class AppOrientation {
  AppOrientation._();

  static const List<DeviceOrientation> preferred = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ];

  /// Deve ser chamado após [WidgetsFlutterBinding.ensureInitialized] e a
  /// inicialização do Firebase, e **antes** de [runApp].
  static Future<void> lockToPortraitUp() {
    return SystemChrome.setPreferredOrientations(preferred);
  }
}
