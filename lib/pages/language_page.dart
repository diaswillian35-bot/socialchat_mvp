import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';


import '../l10n/app_texts.dart';
import '../services/locale_controller.dart';
import '../widget/remdy_app.dart';


class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key});


  @override
  State<LanguagePage> createState() => _LanguagePageState();
}


class _LanguagePageState extends State<LanguagePage> {
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);


  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _logoBlue = Color(0xFF264E9A);


  static const String _prefsKey = 'app_lang';


  final List<_LangItem> _langs = const [
  _LangItem('pt-BR', 'Português (Brasil)'),
  _LangItem('pt-PT', 'Português (Portugal)'),
  _LangItem('en', 'English'),
  _LangItem('es', 'Español'),
  _LangItem('fr', 'Français'),
];




  String _selectedCode = 'en';
  bool _loading = true;


 

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }


 Future<void> _loadSaved() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(_prefsKey) ?? '').trim();


    if (saved.isNotEmpty && _langs.any((e) => e.code == saved)) {
      _selectedCode = saved;
    } else {
      final locale = LocaleController.instance.locale;


      if (locale.languageCode == 'pt' && locale.countryCode == 'PT') {
        _selectedCode = 'pt-PT';
      } else if (locale.languageCode == 'pt') {
        _selectedCode = 'pt-BR';
      } else {
        _selectedCode = locale.languageCode;
      }
    }


    if (_selectedCode == 'pt-PT') {
      await AppTexts.load(const Locale('pt', 'PT'));
    } else if (_selectedCode == 'pt-BR') {
      await AppTexts.load(const Locale('pt', 'BR'));
    } else {
      await AppTexts.load(Locale(_selectedCode));
    }
  } catch (_) {
    await AppTexts.load(const Locale('en'));
    _selectedCode = 'en';
  }


  if (mounted) {
    setState(() => _loading = false);
  }
}


Future<void> _applyLanguage(String code) async {
  setState(() => _selectedCode = code);


  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, code);


    await LocaleController.instance.setLocale(code);


    if (code == 'pt-PT') {
      await AppTexts.load(const Locale('pt', 'PT'));
      RemdyApp.setLocale(context, const Locale('pt', 'PT'));
    } else if (code == 'pt-BR') {
      await AppTexts.load(const Locale('pt', 'BR'));
      RemdyApp.setLocale(context, const Locale('pt', 'BR'));
    } else {
      await AppTexts.load(Locale(code));
      RemdyApp.setLocale(context, Locale(code));
    }


    if (!mounted) return;
    Navigator.popUntil(context, (route) => route.isFirst);
  } catch (_) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppTexts.current.get('language_update_error')),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
      ),
    );
  }
}







  @override
  Widget build(BuildContext context) {
    final current = _langs.firstWhere((e) => e.code == _selectedCode);


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
    appBar: RemdyAppBar(title: AppTexts.current.get('language')),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppTexts.current.get('choose_app_language'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: _text,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        AppTexts.current.get('app_remember_choice'),
                        style: const TextStyle(
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
