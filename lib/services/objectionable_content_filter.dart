import '../utils/user_search_normalize.dart';

/// Client-side gate that blocks clearly objectionable UGC text before post.
///
/// Complements report/block and server moderation — does not replace them.
/// Pure Dart; safe to unit-test without Firebase.
class ObjectionableContentFilter {
  ObjectionableContentFilter._();

  static const String blockedErrorKey = 'content_filter_blocked';

  /// Phrases / tokens that must not be posted (normalized match).
  /// Kept deliberately narrow to reduce false positives while satisfying
  /// Apple 1.2 “filter objectionable material from being posted”.
  static const List<String> blockedPhrases = [
    'child porn',
    'childporn',
    'cp for sale',
    'venda de cp',
    'onlyfans minors',
    'nudes de menor',
    'nude de menor',
    'sexo com menor',
    'pornografia infantil',
    'csam',
    'i will kill you',
    'vou te matar',
    'te mato',
    'kill yourself',
    'se mate',
    'kys ',
    'morte aos',
    'death to all',
  ];

  static final List<RegExp> _blockedRegexes = [
    RegExp(r'\b(rape|estupr[ao]|estuprar)\b', caseSensitive: false),
    RegExp(
      r'\b(nazi|hitler)\s+(rules|power|forever)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(send|mande|envia)\b.{0,24}\b(nudes?|pack)\b.{0,24}\b(minor|menor|under\s*age|crianca|criança)\b',
      caseSensitive: false,
    ),
    // "vou matar" / equivalents. Not a blockedPhrases substring: that would
    // also match idioms like "vou matar a fome".
    RegExp(
      r'\b(?:eu\s+)?vou(?:\s+(?:te|lhe|vos|voce|voces|ele|ela|eles|elas))?\s+matar\b(?!\s+(?:a\s+fome|saudades?|(?:o\s+)?tempo|(?:a\s+)?aula))',
      caseSensitive: false,
    ),
    RegExp(
      r'\bvamos(?:\s+(?:te|vos|voce|voces))?\s+matar\b(?!\s+(?:a\s+fome|saudades?|(?:o\s+)?tempo))',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(?:te\s+)?voy\s+a\s+matar(?:te|lo|la|los|las)?\b(?!\s+(?:el\s+hambre|el\s+tiempo))',
      caseSensitive: false,
    ),
    RegExp(
      r'\bje\s+vais(?:\s+(?:te|vous|le|la|les))?\s+tuer\b(?!\s+le\s+temps)',
      caseSensitive: false,
    ),
    RegExp(
      r"(?:\bi(?:\s+am|\s*'?m)?\s+(?:going\s+to|gonna)|\bi(?:'?ll|\s+will)|\bgonna)\s+kill(?:\s+(?:you|u|him|her|them|ya))?\b(?!\s+(?:time|it)\b)",
      caseSensitive: false,
    ),
  ];

  /// Returns null when allowed; otherwise [blockedErrorKey].
  static String? rejectReason(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final normalized = _normalize(trimmed);
    if (normalized.isEmpty) return null;

    for (final phrase in blockedPhrases) {
      final p = _normalize(phrase);
      if (p.isEmpty) continue;
      if (normalized.contains(p)) return blockedErrorKey;
    }

    for (final re in _blockedRegexes) {
      if (re.hasMatch(trimmed) || re.hasMatch(normalized)) {
        return blockedErrorKey;
      }
    }
    return null;
  }

  static bool allows(String? raw) => rejectReason(raw) == null;

  static String _normalize(String input) {
    var s = UserSearchNormalize.normalize(input);
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }
}
