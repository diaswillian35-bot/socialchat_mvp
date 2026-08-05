/// Contrato estável de idiomas da Remi (target language).
///
/// Códigos canônicos: `en` | `pt` | `es` | `fr`.
/// Labels de UI são apenas apresentação — nunca viajam como identificador.
class RemiLanguageContract {
  RemiLanguageContract._();

  static const List<String> supportedCodes = <String>['en', 'pt', 'es', 'fr'];

  static const Map<String, String> displayNameByCode = <String, String>{
    'en': 'English',
    'pt': 'Português',
    'es': 'Español',
    'fr': 'Français',
  };

  static const Map<String, String> englishNameByCode = <String, String>{
    'en': 'English',
    'pt': 'Portuguese',
    'es': 'Spanish',
    'fr': 'French',
  };

  static const Map<String, String> ttsLocaleByCode = <String, String>{
    'en': 'en-US',
    'pt': 'pt-BR',
    'es': 'es-ES',
    'fr': 'fr-FR',
  };

  static const Map<String, String> flagByCode = <String, String>{
    'en': '🇺🇸',
    'pt': '🇧🇷',
    'es': '🇪🇸',
    'fr': '🇫🇷',
  };

  static const Map<String, String> practiceSubtitleByCode = <String, String>{
    'en': 'Practice English',
    'pt': 'Praticar português',
    'es': 'Practicar español',
    'fr': 'Pratiquer le français',
  };

  /// Normaliza código ou label legado → código canônico.
  static String normalize(Object? raw, {String fallback = 'en'}) {
    final value = (raw ?? '').toString().trim().toLowerCase();
    if (value.isEmpty) return fallback;
    if (supportedCodes.contains(value)) return value;

    switch (value) {
      case 'english':
      case 'en-us':
      case 'en_us':
        return 'en';
      case 'portuguese':
      case 'português':
      case 'portugues':
      case 'pt-br':
      case 'pt_br':
      case 'pt-pt':
      case 'pt_pt':
        return 'pt';
      case 'spanish':
      case 'español':
      case 'espanol':
      case 'es-es':
      case 'es_es':
        return 'es';
      case 'french':
      case 'français':
      case 'francais':
      case 'fr-fr':
      case 'fr_fr':
        return 'fr';
      default:
        return fallback;
    }
  }

  static String displayName(String code) =>
      displayNameByCode[normalize(code)] ?? 'English';

  static String englishName(String code) =>
      englishNameByCode[normalize(code)] ?? 'English';

  static String ttsLocale(String code) =>
      ttsLocaleByCode[normalize(code)] ?? 'en-US';

  static String flag(String code) => flagByCode[normalize(code)] ?? '🏳️';

  static String practiceSubtitle(String code) =>
      practiceSubtitleByCode[normalize(code)] ?? 'Practice';

  /// Idioma da interface do app → código Remi (para explicações).
  static String uiCodeFromLocale(String languageCode) {
    return normalize(languageCode, fallback: 'en');
  }
}
