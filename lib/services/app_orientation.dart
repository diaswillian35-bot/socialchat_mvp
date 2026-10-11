import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Orientação do Remdy.
///
/// iPhone fica só em retrato pelo Info.plist. O iPad usa as quatro orientações
/// de `UISupportedInterfaceOrientations~ipad`. Android permanece só em retrato.
///
/// Não aplicar a máscara de celular no processo inteiro: no iOS o
/// `FlutterViewController` devolve essa máscara e o UIKit cruza com o plist
/// de cada aparelho. Uma máscara só com `portraitUp` impede a paisagem do iPad.
class AppOrientation {
  AppOrientation._();

  /// iPhone e Android. Sem `portraitDown`, para não girar câmera e fotos.
  static const List<DeviceOrientation> phonePreferred = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ];

  /// Igual a `UISupportedInterfaceOrientations~ipad`.
  static const List<DeviceOrientation> iosPreferred = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  /// Política de celular. Testes e chamadas antigas leem esta lista.
  static const List<DeviceOrientation> preferred = phonePreferred;

  static List<DeviceOrientation> preferredFor({required bool ios}) {
    if (ios) return iosPreferred;
    return phonePreferred;
  }

  static bool get _isIos {
    if (kIsWeb) return false;
    try {
      return Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  /// Depois do Firebase e antes de [runApp].
  static Future<void> apply() {
    return SystemChrome.setPreferredOrientations(
      preferredFor(ios: _isIos),
    );
  }
}
