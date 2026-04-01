import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/app_texts.dart';
import 'package:flutter/widgets.dart';


class LocaleController extends ChangeNotifier {
  LocaleController._();
  static final LocaleController instance = LocaleController._();


  static const _kPrefKey = 'app_lang';


  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pt', 'BR'),
    Locale('pt', 'PT'),
    Locale('es'),
    Locale('fr'),
  ];


  Locale _locale = const Locale('en');


  Locale get locale => _locale;


  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(_kPrefKey) ?? '').trim();


    if (saved.isNotEmpty) {
      _locale = _safeLocale(saved);
      AppTexts.setLang(_langCode(_locale));
      notifyListeners();
      return;
    }


    final device = WidgetsBinding.instance.platformDispatcher.locale;
    _locale = _safeLocale(_langCode(device));
    AppTexts.setLang(_langCode(_locale));
    notifyListeners();
  }


  Future<void> setLocale(String code) async {
    final next = _safeLocale(code);


    if (_locale.languageCode == next.languageCode &&
        _locale.countryCode == next.countryCode) {
      return;
    }


    _locale = next;
    AppTexts.setLang(_langCode(_locale));
    notifyListeners();


    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefKey, _langCode(next));
  }


  Future<void> clearSaved() async {
    _locale = const Locale('en');
    AppTexts.setLang(_langCode(_locale));
    notifyListeners();


    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefKey);
  }


  Locale _safeLocale(String code) {
    final c = code.trim();


    if (c == 'pt-PT') return const Locale('pt', 'PT');
    if (c == 'pt-BR' || c == 'pt') return const Locale('pt', 'BR');
    if (c == 'es') return const Locale('es');
    if (c == 'fr') return const Locale('fr');
    if (c == 'en') return const Locale('en');


    return const Locale('en');
  }


  String _langCode(Locale locale) {
    final lang = locale.languageCode.toLowerCase();
    final country = (locale.countryCode ?? '').toUpperCase();


    if (lang == 'pt' && country == 'PT') return 'pt-PT';
    if (lang == 'pt') return 'pt-BR';
    return lang;
  }
}
