/// Normalização de texto para busca de usuários (case e acentos).
class UserSearchNormalize {
  UserSearchNormalize._();

  static const int minQueryLength = 2;

  static const Map<String, String> _diacritics = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'ä': 'a',
    'å': 'a',
    'ā': 'a',
    'ă': 'a',
    'ą': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'ē': 'e',
    'ĕ': 'e',
    'ė': 'e',
    'ę': 'e',
    'ě': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ī': 'i',
    'ĭ': 'i',
    'į': 'i',
    'ı': 'i',
    'ó': 'o',
    'ò': 'o',
    'õ': 'o',
    'ô': 'o',
    'ö': 'o',
    'ō': 'o',
    'ŏ': 'o',
    'ő': 'o',
    'ø': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ū': 'u',
    'ŭ': 'u',
    'ů': 'u',
    'ű': 'u',
    'ų': 'u',
    'ý': 'y',
    'ÿ': 'y',
    'ñ': 'n',
    'ç': 'c',
    'ć': 'c',
    'č': 'c',
    'ď': 'd',
    'đ': 'd',
    'ľ': 'l',
    'ĺ': 'l',
    'ł': 'l',
    'ń': 'n',
    'ň': 'n',
    'ŋ': 'n',
    'ř': 'r',
    'ŕ': 'r',
    'ś': 's',
    'š': 's',
    'ş': 's',
    'ť': 't',
    'ţ': 't',
    'ź': 'z',
    'ž': 'z',
    'ż': 'z',
  };

  /// Lowercase, trim, colapsa espaços e remove diacríticos comuns.
  static String normalize(String input) {
    final value = input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (value.isEmpty) return '';

    final buffer = StringBuffer();
    for (final rune in value.runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(_diacritics[ch] ?? ch);
    }
    return buffer.toString();
  }

  static bool isQueryReady(String rawQuery) {
    return normalize(rawQuery).length >= minQueryLength;
  }
}
