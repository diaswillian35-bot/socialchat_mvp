import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';


class AppLocale {
  static const _key = 'appLang';


  static Locale? _locale;
  static Locale? get locale => _locale;


  static Future<void> load() async {
    final sp = await SharedPreferences.getInstance();
    final code = sp.getString(_key);
    if (code == null || code.isEmpty) {
      _locale = null; // ✅ usa idioma do celular
    } else {
      _locale = Locale(code);
    }
  }


  static Future<void> set(String code) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, code);
    _locale = Locale(code);
  }


  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
    _locale = null;
  }
}
