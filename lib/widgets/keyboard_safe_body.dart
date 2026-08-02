import 'package:flutter/material.dart';

/// Corpo de formulário que sobe/rola com o teclado (iOS e Android).
///
/// Use dentro de um [Scaffold] com `resizeToAvoidBottomInset: true` (padrão).
/// Evita o padrão quebrado `Center > SingleChildScrollView`, que no iOS
/// frequentemente deixa campos cobertos pelo teclado.
class KeyboardSafeFormBody extends StatelessWidget {
  const KeyboardSafeFormBody({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 18, 18, 24),
    this.maxWidth = 420,
    this.centerWhenShort = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double? maxWidth;
  final bool centerWhenShort;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final padded = Padding(
          padding: padding,
          child: maxWidth == null
              ? child
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth!),
                    child: child,
                  ),
                ),
        );

        final content = centerWhenShort
            ? ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Align(
                  alignment: Alignment.center,
                  child: padded,
                ),
              )
            : padded;

        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          physics: const AlwaysScrollableScrollPhysics(),
          child: content,
        );
      },
    );
  }
}

/// Padding inferior extra para listas/formulários longos, sem duplicar
/// o inset do teclado (o Scaffold já reduz a altura do body).
EdgeInsets keyboardSafeListPadding({
  double left = 16,
  double top = 16,
  double right = 16,
  double bottom = 24,
}) {
  return EdgeInsets.fromLTRB(left, top, right, bottom);
}
