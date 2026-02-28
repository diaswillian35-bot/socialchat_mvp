import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';


import '../widget/remdy_app.dart';
import '../services/locale_controller.dart';


class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key});


  @override
  State<LanguagePage> createState() => _LanguagePageState();
}


class _LanguagePageState extends State<LanguagePage> {
  // Remdy style
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);


  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _logoBlue = Color(0xFF264E9A);


  // ✅ agora usa a mesma key do LocaleController
  static const String _prefsKey = 'app_lang';


  final List<_LangItem> _langs = const [
    _LangItem('pt', 'Português'),
    _LangItem('en', 'English'),
    _LangItem('es', 'Español'),
    _LangItem('fr', 'Français'),
  ];


  String _selectedCode = 'en'; // ✅ default global
  bool _loading = true;


  @override
  void initState() {
    super.initState();
    _loadSaved();
  }


  Future<void> _loadSaved() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = (prefs.getString(_prefsKey) ?? '').trim().toLowerCase();


      if (saved.isNotEmpty && _langs.any((e) => e.code == saved)) {
        _selectedCode = saved;
      } else {
        // ✅ se não tiver salvo, pega do controller (default en)
        _selectedCode = LocaleController.instance.locale.languageCode;
      }
    } catch (_) {
      _selectedCode = LocaleController.instance.locale.languageCode;
    }


    if (mounted) setState(() => _loading = false);
  }


  Future<void> _applyLanguage(String code) async {
    setState(() => _selectedCode = code);


    // 1) salva no celular (mantém — mas agora com a key correta)
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, code);
    } catch (_) {}


    // 2) ✅ aplica de verdade no app (controller que liga no MaterialApp.locale)
    try {
      await LocaleController.instance.setLocale(code);


      // opcional: se você ainda usa RemdyApp.setLocale em algum lugar, não atrapalha.
      // (mantém o comportamento antigo sem depender dele)
      try {
        RemdyApp.setLocale(context, LocaleController.instance.locale);
      } catch (_) {}


      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Idioma atualizado ✅'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(12),
          duration: Duration(seconds: 1),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Idioma salvo ✅ (se não aplicar agora, reinicie o app)'),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(12),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    final current = _langs.firstWhere((e) => e.code == _selectedCode);


    // ✅ THEME LOCAL (remove rosa de vez)
    final fixedTheme = Theme.of(context).copyWith(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: const Color(0xFFF1F5F9),


      colorScheme: Theme.of(context).colorScheme.copyWith(
            primary: _remdyBlue,
            secondary: _remdyBlue,
          ),


      canvasColor: Colors.white,
    );


    return Scaffold(
      backgroundColor: _bg,
      appBar: const RemdyAppBar(title: 'Idioma'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _border),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Escolha o idioma do app',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: _text,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'O app vai lembrar sua escolha.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Theme(
                  data: fixedTheme,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _border),
                    ),
                    child: DropdownButtonFormField<String>(
                      value: current.code,
                      isExpanded: true,
                      dropdownColor: Colors.white,
                      iconEnabledColor: _muted,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: _border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: _logoBlue),
                        ),
                      ),
                      items: _langs
                          .map(
                            (e) => DropdownMenuItem<String>(
                              value: e.code,
                              child: Text(
                                e.label,
                                style: const TextStyle(
                                  color: _text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        _applyLanguage(v);
                      },
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}


class _LangItem {
  final String code;
  final String label;
  const _LangItem(this.code, this.label);
}
