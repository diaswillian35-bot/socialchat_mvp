import 'package:flutter/material.dart';

/// Âncora do popover de compartilhamento.
///
/// O retângulo do botão vem do [RenderBox]. Se ele não tiver tamanho, estiver
/// fora da tela ou o contexto não tiver view, usa um ponto no centro da view.
/// O iOS pode usar popover também no iPhone: passe sempre um retângulo
/// não vazio dentro da tela quando houver uma view.
class EventShareOrigin {
  EventShareOrigin._();

  static Rect? fromContext(BuildContext context) {
    if (!context.mounted) return null;
    Rect? button;
    final object = context.findRenderObject();
    if (object is RenderBox && object.attached && object.hasSize) {
      final topLeft = object.localToGlobal(Offset.zero);
      button = topLeft & object.size;
    }
    return resolve(
      button: button,
      viewSize: MediaQuery.maybeSizeOf(context),
    );
  }

  static Rect? resolve({Rect? button, Size? viewSize}) {
    final view = _viewRect(viewSize);
    if (button != null && _usable(button)) {
      if (view == null) return button;
      final visible = button.intersect(view);
      if (_usable(visible)) return visible;
    }
    return _centerAnchor(view);
  }

  static Rect? _viewRect(Size? size) {
    if (size == null) return null;
    if (!size.width.isFinite || !size.height.isFinite) return null;
    if (size.width <= 0 || size.height <= 0) return null;
    return Offset.zero & size;
  }

  static Rect? _centerAnchor(Rect? view) {
    if (view == null) return null;
    const side = 2.0;
    return Rect.fromCenter(center: view.center, width: side, height: side);
  }

  static bool _usable(Rect rect) {
    return rect.width > 0 &&
        rect.height > 0 &&
        rect.left.isFinite &&
        rect.top.isFinite &&
        rect.width.isFinite &&
        rect.height.isFinite;
  }
}
