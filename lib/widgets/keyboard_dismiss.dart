import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Fecha o teclado / remove o foco atual.
void dismissAppKeyboard() {
  FocusManager.instance.primaryFocus?.unfocus();
}

bool get _isIos =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Toque fora de campos fecha o teclado, sem engolir botões/scroll.
class KeyboardDismissOnTap extends StatelessWidget {
  const KeyboardDismissOnTap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: dismissAppKeyboard,
      behavior: HitTestBehavior.translucent,
      child: child,
    );
  }
}

bool _isNumericKeyboardType(TextInputType? type) {
  if (type == null) return false;
  if (type == TextInputType.phone || type == TextInputType.datetime) {
    return true;
  }
  // number / numberWithOptions(*)
  return type.decimal != null || type.signed != null || type == TextInputType.number;
}

TextInputType? _keyboardTypeOfFocus(FocusNode? focus) {
  if (focus == null || !focus.hasFocus) return null;
  final ctx = focus.context;
  if (ctx == null) return null;
  final editable = ctx.findAncestorStateOfType<EditableTextState>();
  return editable?.widget.keyboardType;
}

double _keyboardBottomInset() {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return 0;
  final view = views.first;
  return view.viewInsets.bottom / view.devicePixelRatio;
}

/// Barra "Concluído" acima do teclado numérico no iOS (sem Done nativo).
class IosNumericKeyboardDoneBar extends StatefulWidget {
  const IosNumericKeyboardDoneBar({super.key, required this.child});

  final Widget child;

  @override
  State<IosNumericKeyboardDoneBar> createState() =>
      _IosNumericKeyboardDoneBarState();
}

class _IosNumericKeyboardDoneBarState extends State<IosNumericKeyboardDoneBar>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_rebuild);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_rebuild);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _rebuild();

  void _rebuild() {
    if (mounted) setState(() {});
  }

  bool get _showBar {
    if (!_isIos) return false;
    final bottom = _keyboardBottomInset();
    if (bottom <= 0) return false;
    final type = _keyboardTypeOfFocus(FocusManager.instance.primaryFocus);
    return _isNumericKeyboardType(type);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = _keyboardBottomInset();
    final show = _showBar;

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (show)
          Positioned(
            left: 0,
            right: 0,
            bottom: bottom,
            child: Material(
              elevation: 0,
              color: const Color(0xFFD6D8DD),
              child: SizedBox(
                height: 44,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: dismissAppKeyboard,
                    child: Text(
                      _doneLabel(context),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF264E9A),
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _doneLabel(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode.toLowerCase();
    switch (code) {
      case 'pt':
        return 'Concluído';
      case 'es':
        return 'Listo';
      case 'fr':
        return 'OK';
      default:
        return 'Done';
    }
  }
}

/// Remove foco ao voltar do background (restauração de teclado no iOS).
class KeyboardLifecycleGuard extends StatefulWidget {
  const KeyboardLifecycleGuard({super.key, required this.child});

  final Widget child;

  @override
  State<KeyboardLifecycleGuard> createState() => _KeyboardLifecycleGuardState();
}

class _KeyboardLifecycleGuardState extends State<KeyboardLifecycleGuard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Evita restauração do teclado “preso” ao voltar ao app no iOS.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      dismissAppKeyboard();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
