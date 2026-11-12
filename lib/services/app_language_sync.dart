import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Grava `users/{uid}.appLanguageCode` no formato do servidor
/// (`pt-BR`, `pt-PT`, `en`, `es`, `fr`).
///
/// Sem escrita se o valor no doc já for o canónico. Falhas são
/// só registadas — não bloqueiam a UI.
class AppLanguageSync {
  static const field = 'appLanguageCode';

  static const Set<String> allowed = {
    'pt-BR',
    'pt-PT',
    'en',
    'es',
    'fr',
  };

  /// Alinha com `normalizeLang` de `functions/i18n/serverTexts.js`
  /// e com `LocaleController._safeLocale`. Código desconhecido → `en`.
  static String normalize(String? raw) {
    final t = (raw ?? '').trim().toLowerCase().replaceAll('_', '-');
    if (t.isEmpty) return 'en';
    if (t == 'pt-pt' || t.startsWith('pt-pt-')) return 'pt-PT';
    if (t == 'pt' ||
        t == 'pt-br' ||
        t.startsWith('pt-br') ||
        t.startsWith('pt-')) {
      return 'pt-BR';
    }
    final two = t.split('-').first;
    if (two == 'en' || two == 'es' || two == 'fr') return two;
    return 'en';
  }

  /// `true` se o valor gravado for diferente do canónico desejado.
  static bool needsWrite(Object? stored, String desired) {
    return stored != normalize(desired);
  }

  static Future<void> sync(String code) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final lang = normalize(code);
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      final snap = await ref.get();
      final stored = snap.data()?[field];
      if (!needsWrite(stored, lang)) return;
      await ref.set({field: lang}, SetOptions(merge: true));
    } catch (e, st) {
      debugPrint('AppLanguageSync: falha ao gravar $field: $e\n$st');
    }
  }
}
