import 'dart:ui';


import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';


class LocaleController extends ChangeNotifier {
  LocaleController._();
  static final LocaleController instance = LocaleController._();


  static const _kPrefKey = 'appLang'; // 'pt', 'en', 'es', 'fr'


  Locale _locale = const Locale('pt');
  Locale get locale => _locale;


  /// Carrega idioma salvo; se não tiver, usa idioma do celular.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(_kPrefKey) ?? '').trim().toLowerCase();


    if (saved.isNotEmpty) {
      _locale = Locale(saved);
      notifyListeners();
      return;
    }


    // ✅ Primeiro acesso: usa idioma do celular
    final device = PlatformDispatcher.instance.locale;
    final code = (device.languageCode).toLowerCase();


    // limita aos idiomas que você suporta (evita ficar "quebrado")
    const supported = {'pt', 'en', 'es', 'fr'};
    _locale = Locale(supported.contains(code) ? code : 'en');
    notifyListeners();
  }


  Future<void> setLocale(Locale locale) async {
    final code = locale.languageCode.toLowerCase();


    // mantém só os suportados
    const supported = {'pt', 'en', 'es', 'fr'};
    final safeCode = supported.contains(code) ? code : 'en';


    _locale = Locale(safeCode);
    notifyListeners();


    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefKey, safeCode);
  }


  Future<void> clearSaved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefKey);
  }
}
