import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:crypto/crypto.dart';

/// Resultado de usar as traduções gravadas pelo servidor na aprovação.
enum StoredTranslationUse {
  /// Sem tradução gravada para este texto/idioma: usa o fallback antigo.
  unavailable,

  /// O aparelho está no idioma original: mostra o original, sem chamada.
  original,

  /// Há tradução gravada para o idioma do aparelho.
  translated,
}

class StoredTranslationResult {
  const StoredTranslationResult(this.use, [this.text]);
  final StoredTranslationUse use;
  final String? text;
}

/// `places/{id}.descriptionI18n`: escrito só pelo servidor (gatilho na
/// aprovação). O original continua em `description`; só vale para o texto
/// cujo hash bate com [sourceHash].
class PlaceDescriptionTranslations {
  const PlaceDescriptionTranslations({
    required this.sourceHash,
    required this.sourceLanguage,
    required this.status,
    required this.texts,
  });

  static const languages = ['pt-BR', 'pt-PT', 'en', 'es', 'fr'];

  final String sourceHash;
  final String sourceLanguage;
  final String status;
  final Map<String, String> texts;

  static PlaceDescriptionTranslations? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final hash = raw['sourceHash'];
    if (hash is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      return null;
    }
    final texts = <String, String>{};
    final rawTexts = raw['texts'];
    if (rawTexts is Map) {
      for (final lang in languages) {
        final value = rawTexts[lang];
        if (value is String && value.isNotEmpty && value.length <= 20000) {
          texts[lang] = value;
        }
      }
    }
    final source = raw['sourceLanguage'];
    final status = raw['status'];
    return PlaceDescriptionTranslations(
      sourceHash: hash,
      sourceLanguage: source is String ? source.toLowerCase() : '',
      status: status is String ? status : '',
      texts: texts,
    );
  }

  static String hashOf(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  /// Chave de idioma do app: pt-PT só para Portugal; outros pt = pt-BR;
  /// idiomas fora dos 5 caem em inglês (igual ao callable antigo).
  static String keyFor(Locale locale) {
    final code = locale.languageCode.toLowerCase();
    if (code == 'pt') {
      return (locale.countryCode ?? '').toUpperCase() == 'PT'
          ? 'pt-PT'
          : 'pt-BR';
    }
    return const ['en', 'es', 'fr'].contains(code) ? code : 'en';
  }

  static String _family(String tag) =>
      tag.toLowerCase().split(RegExp('[-_]')).first;

  /// Decide sem rede: tradução gravada, original, ou indisponível (fallback).
  StoredTranslationResult resolve(String original, Locale locale) {
    if (original.isEmpty || hashOf(original) != sourceHash) {
      return const StoredTranslationResult(StoredTranslationUse.unavailable);
    }
    final key = keyFor(locale);
    if (sourceLanguage.isNotEmpty && _family(sourceLanguage) == _family(key)) {
      return const StoredTranslationResult(StoredTranslationUse.original);
    }
    final text = texts[key] ?? (key == 'pt-PT' ? texts['pt-BR'] : null);
    if (text != null && text != original) {
      return StoredTranslationResult(StoredTranslationUse.translated, text);
    }
    return const StoredTranslationResult(StoredTranslationUse.unavailable);
  }
}
