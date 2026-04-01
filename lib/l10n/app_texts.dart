import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';


class AppTexts {
  AppTexts._(this.locale, this._map);


  final Locale locale;
  final Map<String, dynamic> _map;


  static AppTexts? _current;


  static AppTexts get current {
    if (_current == null) {
      throw Exception('AppTexts não carregado.');
    }
    return _current!;
  }


  static Future<void> load(Locale locale) async {
  final lang = locale.languageCode.toLowerCase();
  final country = (locale.countryCode ?? '').toUpperCase();


  Map<String, dynamic> map = {};


 Future<Map<String, dynamic>> _read(String file) async {
  try {
    final raw = await rootBundle.loadString('lib/l10n/$file.json');
    return jsonDecode(raw) as Map<String, dynamic>;
  } catch (e) {
    debugPrint('ERRO carregando $file.json: $e');
    return {};
  }
}



  // 🇵🇹 Portugal = Brasil + override
  if (lang == 'pt' && country == 'PT') {
    final base = await _read('pt-BR');
    final override = await _read('pt-PT');
    map = {...base, ...override};
  }
  // 🇧🇷 Brasil
  else if (lang == 'pt') {
    map = await _read('pt-BR');
  }
  // 🇪🇸 Espanhol
  else if (lang == 'es') {
    map = await _read('es');
  }
  // 🇫🇷 Francês
  else if (lang == 'fr') {
    map = await _read('fr');
  }
  // 🌍 fallback
  else {
    map = await _read('en');
  }


  _current = AppTexts._(locale, map);
}



  static List<String> _fileCodes(Locale locale) {
    final lang = locale.languageCode.toLowerCase();
    final country = (locale.countryCode ?? '').toUpperCase();


    if (lang == 'pt' && country == 'PT') {
      return ['pt-PT', 'pt_PT', 'pt-BR', 'pt_BR', 'en'];
    }


    if (lang == 'pt') {
      return ['pt-BR', 'pt_BR', 'pt-PT', 'pt_PT', 'en'];
    }


    if (lang == 'es') return ['es', 'en'];
    if (lang == 'fr') return ['fr', 'en'];


    return ['en'];
  }


  String get(String key) {
    final value = _map[key];
    if (value == null) return key;
    return value.toString();
  }


  static String t(String key) {
    final currentMap = _current?._map;
    if (currentMap == null) return key;
    final value = currentMap[key];
    if (value == null) return key;
    return value.toString();
  }
}
