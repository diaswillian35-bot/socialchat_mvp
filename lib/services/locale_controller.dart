import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';


class LocaleController extends ChangeNotifier {
  LocaleController._();
  static final LocaleController instance = LocaleController._();


  static const _kPrefKey = 'app_lang';


  // Idiomas suportados do app (ajuste se quiser)
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pt'),
    Locale('es'),
    Locale('fr'),
  ];


  Locale _locale = const Locale('en'); // ✅ default global


  Locale get locale => _locale;


  /// Carrega o idioma salvo (se existir)
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = (prefs.getString(_kPrefKey) ?? '').trim().toLowerCase();


    final next = _safeLocale(code.isEmpty ? 'en' : code);
    _locale = next;
    notifyListeners();
  }


  /// Define e salva o idioma
  Future<void> setLocale(String code) async {
    final next = _safeLocale(code);


    // evita rebuild desnecessário
    if (_locale.languageCode == next.languageCode) return;


    _locale = next;
    notifyListeners();


    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefKey, next.languageCode);
  }


  /// Reset para inglês
  Future<void> clearSaved() async {
    _locale = const Locale('en');
    notifyListeners();


    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefKey);
  }


  Locale _safeLocale(String code) {
    final c = code.trim().toLowerCase();
    for (final l in supportedLocales) {
      if (l.languageCode == c) return l;
    }
    return const Locale('en');
  }
}
