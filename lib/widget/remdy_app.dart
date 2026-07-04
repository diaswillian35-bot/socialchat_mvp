import 'package:flutter/material.dart';


class RemdyApp extends StatefulWidget {
  final Widget child;
  const RemdyApp({super.key, required this.child});


  // ✅ chama de qualquer página: RemdyApp.setLocale(context, Locale('en'));
  static void setLocale(BuildContext context, Locale locale) {
    final state = context.findAncestorStateOfType<_RemdyAppState>();
    state?._setLocale(locale);
  }


  // ✅ pega locale atual (usado no main.dart)
  static Locale? localeOf(BuildContext context) {
    final state = context.findAncestorStateOfType<_RemdyAppState>();
    return state?._locale;
  }


  @override
  State<RemdyApp> createState() => _RemdyAppState();
}


class _RemdyAppState extends State<RemdyApp> {
  Locale? _locale;


  void _setLocale(Locale locale) {
    setState(() => _locale = locale);
  }


  @override
  Widget build(BuildContext context) {
    // Só fornece a "ponte" de locale pro MaterialApp.
    return _RemdyLocaleScope(
      locale: _locale,
      child: widget.child,
    );
  }
}


class _RemdyLocaleScope extends InheritedWidget {
  final Locale? locale;
  const _RemdyLocaleScope({required this.locale, required super.child});


  @override
  bool updateShouldNotify(_RemdyLocaleScope oldWidget) => oldWidget.locale != locale;
}


// =======================================
// ✅ AppBar padrão Remdy (mata o rosa)
// =======================================
class RemdyAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool centerTitle;
  final List<Widget>? actions;


  const RemdyAppBar({
    super.key,
    required this.title,
    this.centerTitle = true,
    this.actions,
  });


  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);


  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);


  @override
  Widget build(BuildContext context) {
    return AppBar(
      // ✅ isso evita a barra rosa quando rola (Material 3)
      backgroundColor: _bg,
      surfaceTintColor: _bg,
      scrolledUnderElevation: 0,
      elevation: 0,


      foregroundColor: _text,
      iconTheme: const IconThemeData(color: _muted),


      centerTitle: centerTitle,
      title: Text(
        title,
        style: const TextStyle(
          color: _text,
          fontWeight: FontWeight.w900,
          fontSize: 16,
        ),
      ),
      actions: actions,
    );
  }
}
