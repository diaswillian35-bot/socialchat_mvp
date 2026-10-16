import 'package:flutter/widgets.dart';

/// Montagem das páginas do [MainShell] com Locais opcional.
///
/// Com a flag desligada o retorno tem exatamente as quatro abas atuais,
/// na mesma ordem: Home, Mensagens, Grupos, Eventos.
List<Widget> buildMainShellPages({
  required bool locaisEnabled,
  required Widget home,
  required Widget messages,
  required Widget groups,
  required Widget events,
  Widget? locais,
}) {
  return <Widget>[
    home,
    messages,
    groups,
    events,
    if (locaisEnabled && locais != null) locais,
  ];
}

/// Índices do menu inferior. Eventos permanece em 3 para não deslocar
/// deep links, o atalho da Home e o Voltar do Android.
class MainShellDestinations {
  MainShellDestinations._();

  static const int homeTabIndex = 0;
  static const int eventsTabIndex = 3;
  static const int locaisTabIndex = 4;

  static int maxIndex({required bool locaisEnabled}) =>
      locaisEnabled ? locaisTabIndex : eventsTabIndex;

  static int tabCount({required bool locaisEnabled}) => locaisEnabled ? 5 : 4;

  /// Índice inicial inválido volta para a Home, como o shell já fazia.
  static int initialIndex(int index, {required bool locaisEnabled}) {
    if (index < 0 || index > maxIndex(locaisEnabled: locaisEnabled)) {
      return homeTabIndex;
    }
    return index;
  }

  /// Toque fora do intervalo é ignorado, sem trocar de aba.
  static bool canSelect(int index, {required bool locaisEnabled}) {
    return index >= 0 && index <= maxIndex(locaisEnabled: locaisEnabled);
  }
}
