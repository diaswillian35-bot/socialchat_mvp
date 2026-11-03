import 'package:flutter/foundation.dart';

import '../utils/user_search_normalize.dart';

/// Client-side gate that blocks clearly objectionable UGC text before post.
///
/// The build 38 phrase list and regexes stay. Adult terms, links and
/// leetspeak only extend that filter.
class ContentFilterDecision {
  const ContentFilterDecision(this.reason);

  /// `csam`, `link_adult` or `text_adult`.
  final String reason;
}

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

  static const _csamPhrases = {
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
  };

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

  static const defaultBlockedDomains = <String>[
    'onlyfans.com',
    'pornhub.com',
    'xvideos.com',
    'xvideos2.com',
    'xnxx.com',
    'xhamster.com',
    'redtube.com',
    'youporn.com',
    'fansly.com',
    'fanvue.com',
    'privacy.com.br',
    'chaturbate.com',
    'stripchat.com',
    'bongacams.com',
    'livejasmin.com',
    'erome.com',
    'spankbang.com',
    'rule34.xxx',
    'sex.com',
    'justfor.fans',
    'manyvids.com',
  ];

  static const _extraCsam = <String>[
    'porno infantil',
    'sexo com crianca',
    'sexo com criancas',
    'nudez infantil',
    'conteudo sexual infantil',
    'child pornography',
    'pornographie infantile',
  ];

  static const _adultPhrases = <String>[
    'sexo explicito',
    'conteudo adulto',
    'contenido adulto',
    'contenu adulte',
    'explicit sex',
    'pack de nudes',
    'vendo nudes',
    'venda de nudes',
    'manda nude',
    'mande nude',
    'send nude',
    'envia nude',
  ];

  static const _adultWords = <String>[
    'porn',
    'porno',
    'pornografia',
    'pornography',
    'pornographie',
    'xvideos',
    'pornhub',
    'xhamster',
    'onlyfans',
    'fansly',
    'boquete',
    'punheta',
    'buceta',
    'piroca',
    'blowjob',
    'handjob',
    'camgirl',
    'nudes',
  ];

  static List<String>? _configuredDomains;

  static void setBlockedDomains(List<String> domains) {
    final next = <String>[];
    for (final raw in domains) {
      final host = raw
          .trim()
          .toLowerCase()
          .replaceFirst(RegExp(r'^https?://'), '')
          .replaceFirst(RegExp(r'^www\.'), '')
          .split('/')
          .first;
      if (host.contains('.')) next.add(host);
    }
    _configuredDomains = next.isEmpty ? null : next;
  }

  @visibleForTesting
  static void resetDomainsForTest() {
    _configuredDomains = null;
  }

  /// Returns null when allowed; otherwise [blockedErrorKey].
  static String? rejectReason(String? raw) {
    final decision = evaluate(raw);
    if (decision == null) return null;
    return blockedErrorKey;
  }

  static bool allows(String? raw) => rejectReason(raw) == null;

  static ContentFilterDecision? evaluate(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final direct = _baseDecision(trimmed);
    if (direct?.reason == 'csam') return direct;
    final evaded = _baseDecision(_evasionRaw(trimmed));
    if (evaded?.reason == 'csam') return evaded;
    final extra = _extensionDecision(trimmed);
    if (extra?.reason == 'csam') return extra;
    return _worse(_worse(direct, evaded), extra);
  }

  static ContentFilterDecision? _baseDecision(String trimmed) {
    final normalized = _normalize(trimmed);
    if (normalized.isEmpty) return null;

    for (final phrase in blockedPhrases) {
      final p = _normalize(phrase);
      if (p.isEmpty) continue;
      if (normalized.contains(p)) {
        return ContentFilterDecision(
          _csamPhrases.contains(p) ? 'csam' : 'text_adult',
        );
      }
    }

    if (_blockedRegexes[2].hasMatch(trimmed) ||
        _blockedRegexes[2].hasMatch(normalized)) {
      return const ContentFilterDecision('csam');
    }
    for (var i = 0; i < _blockedRegexes.length; i++) {
      if (i == 2) continue;
      final re = _blockedRegexes[i];
      if (re.hasMatch(trimmed) || re.hasMatch(normalized)) {
        return const ContentFilterDecision('text_adult');
      }
    }
    return null;
  }

  static ContentFilterDecision? _extensionDecision(String raw) {
    final prepared = _evasionRaw(raw);
    if (prepared.isEmpty) return null;
    final words = _normalize(prepared);
    final domains = _configuredDomains ?? defaultBlockedDomains;
    final glued = _glueSpacedDomains(prepared, domains);
    for (final phrase in _extraCsam) {
      if (_hasToken(words, phrase)) return const ContentFilterDecision('csam');
    }
    for (final host in _extractHosts(glued)) {
      if (_hostBlocked(host, domains)) {
        return const ContentFilterDecision('link_adult');
      }
    }
    for (final phrase in _adultPhrases) {
      if (_hasToken(words, phrase)) {
        return const ContentFilterDecision('text_adult');
      }
    }
    for (final word in _adultWords) {
      if (_hasToken(words, word)) {
        return const ContentFilterDecision('text_adult');
      }
    }
    return null;
  }

  static ContentFilterDecision? _worse(
    ContentFilterDecision? a,
    ContentFilterDecision? b,
  ) {
    if (a == null) return b;
    if (b == null) return a;
    const rank = {'csam': 3, 'link_adult': 2, 'text_adult': 1};
    return (rank[a.reason] ?? 0) >= (rank[b.reason] ?? 0) ? a : b;
  }

  static String _normalize(String input) {
    var s = UserSearchNormalize.normalize(input);
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static String _evasionRaw(String raw) {
    var s = UserSearchNormalize.normalize(raw);
    s = s.replaceAll('0', 'o').replaceAll('1', 'i').replaceAll('3', 'e');
    s = s.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
    s = s.replaceAllMapped(
      RegExp(r'\s*(?:ponto|dot|punto|point)\s+(com|net|org|xxx)\b'),
      (m) => '.${m[1]}',
    );
    s = s.replaceAll(RegExp(r'\s*\.\s*'), '.');
    s = s.replaceAllMapped(
      RegExp(r'\b(?:[a-z]\s+){3,}[a-z]\b'),
      (m) => (m[0] ?? '').replaceAll(RegExp(r'\s+'), ''),
    );
    return s;
  }

  static String _glueSpacedDomains(String s, List<String> domains) {
    var cur = s;
    final re = RegExp(
      r'\b([a-z0-9-]{2,})\s+((?:[a-z0-9-]+\.)+[a-z]{2,})\b',
    );
    for (var i = 0; i < 4; i++) {
      final next = cur.replaceAllMapped(re, (m) {
        final left = m[1] ?? '';
        final host = m[2] ?? '';
        final joined = '$left$host';
        if (_hostBlocked(host, domains)) return m[0]!;
        if (_hostBlocked(joined, domains)) return joined;
        return m[0]!;
      });
      if (next == cur) break;
      cur = next;
    }
    return cur;
  }

  static bool _hasToken(String text, String token) {
    return RegExp('(?:^|[^a-z0-9])${RegExp.escape(token)}(?:[^a-z0-9]|\$)')
        .hasMatch(text);
  }

  static List<String> _extractHosts(String text) {
    final re = RegExp(
      r'(?:https?:\/\/)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:\/[^\s]*)?',
    );
    final hosts = <String>[];
    for (final match in re.allMatches(text)) {
      var token = match.group(0)!.replaceFirst(RegExp(r'^https?:\/\/'), '');
      token = token.split('/').first.split(':').first;
      if (token.isNotEmpty) hosts.add(token);
    }
    return hosts;
  }

  static bool _hostBlocked(String host, List<String> domains) {
    final h = host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    if (h.isEmpty) return false;
    if (h == 'xxx' || h.endsWith('.xxx')) return true;
    for (final domain in domains) {
      if (h == domain || h.endsWith('.$domain')) return true;
    }
    return false;
  }
}
