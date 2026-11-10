import 'chat_rules_lists.g.dart';

/// b44: espelho do servidor (functions/moderation/profanity.js e group_bot.js).
/// Insulto/ofensa dirigida: sempre bloqueado. Palavrão solto: só nos grupos
/// em que o dono ligou o filtro. Links e telefones: bot do grupo.
/// O servidor decide de verdade; aqui é só para avisar antes de enviar (sem ponto).
/// Paridade testada em test/chat_rules_filter_test.dart.
class ChatRulesFilter {
  ChatRulesFilter._();

  static const String botSenderId = 'remdy_bot';
  static const int rulesMax = 600;

  /// Padrão recomendado quando o grupo não tem `modBot`.
  static const Map<String, bool> defaults = {
    'welcomeEnabled': true,
    'blockLinks': true,
    'blockPhones': true,
    'blockProfanity': false,
  };

  static bool botFlag(Map<String, dynamic>? group, String key) {
    final raw = group?['modBot'];
    if (raw is Map && raw[key] is bool) return raw[key] as bool;
    return defaults[key] ?? false;
  }

  static String botRules(Map<String, dynamic>? group) {
    final raw = group?['modBot'];
    if (raw is Map && raw['rules'] is String) return (raw['rules'] as String).trim();
    return '';
  }

  static const Map<String, String> _accents = {
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a',
    'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ñ': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y',
  };
  static const Map<String, String> _leet = {
    '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '@': 'a', r'$': 's',
  };

  static String _basic(String raw) {
    final lower = raw.toLowerCase().replaceAll(RegExp('[\u200B-\u200D\uFEFF]'), '');
    final b = StringBuffer();
    for (final ch in lower.split('')) {
      b.write(_accents[ch] ?? ch);
    }
    // marcas combinantes soltas (texto já decomposto)
    return b.toString().replaceAll(RegExp('[\u0300-\u036f]'), '');
  }

  /// Mesmo prepare() do servidor.
  static String prepare(String? raw) {
    var s = _basic(raw ?? '');
    s = s.replaceAllMapped(RegExp(r'[a-z0-9@$]+'), (m) {
      final w = m[0]!;
      if (!RegExp('[a-z]').hasMatch(w)) return w;
      return w.replaceAllMapped(RegExp(r'[013457@$]'), (c) => _leet[c[0]!] ?? c[0]!);
    });
    s = s.replaceAllMapped(RegExp(r'\b(?:[a-z][.\-_*]){2,}[a-z]\b'),
        (m) => m[0]!.replaceAll(RegExp(r'[.\-_*]'), ''));
    s = s.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
    s = s.replaceAllMapped(RegExp(r'\b(?:[a-z]\s+){2,}[a-z]\b'),
        (m) => m[0]!.replaceAll(RegExp(r'\s+'), ''));
    s = s.replaceAllMapped(RegExp(r'([a-z])\1{2,}'), (m) => m[1]!);
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _hasToken(String text, String token) {
    return RegExp('(?:^|[^a-z0-9])${RegExp.escape(token)}(?:[^a-z0-9]|\$)').hasMatch(text);
  }

  /// 'insult' | 'profanity' | null
  static String? profanity(String? raw, {bool loose = false}) {
    final text = prepare(raw);
    if (text.isEmpty) return null;
    for (final t in chatRulesInsults) {
      if (_hasToken(text, t)) return 'insult';
    }
    if (loose) {
      for (final t in chatRulesLoose) {
        if (_hasToken(text, t)) return 'profanity';
      }
    }
    return null;
  }

  static bool isInsult(String? raw) => profanity(raw) == 'insult';

  // ---------- links ----------
  static const List<String> _allowedHosts = ['remdy.app'];
  static const List<String> _tlds = [
    'com', 'net', 'org', 'info', 'biz', 'io', 'app', 'dev', 'me', 'ly', 'gg', 'co', 'tv',
    'xyz', 'link', 'site', 'online', 'store', 'shop', 'club', 'live', 'top', 'vip', 'fun',
    'br', 'pt', 'ca', 'us', 'uk', 'fr', 'es', 'de', 'it', 'mx', 'ar', 'cl', 'eu', 'be', 'ch',
    'to', 'cc', 'ws', 'click', 'page', 'xxx', 'porn', 'sex', 'cam',
  ];
  static const List<String> _ambiguousTlds = [
    'de', 'es', 'it', 'me', 'to', 'co', 'us', 'ca', 'pt', 'be', 'ch', 'cc', 'ws', 'ar',
    'fr', 'eu', 'mx', 'cl', 'uk', 'tv',
  ];
  static const List<String> _shortHosts = [
    'wa.me', 't.me', 'bit.ly', 'tinyurl.com', 'chat.whatsapp.com', 'discord.gg', 'linktr.ee',
  ];

  static bool _hostAllowed(String host) {
    final h = host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '').replaceAll(RegExp(r'\.+$'), '');
    return _allowedHosts.any((d) => h == d || h.endsWith('.$d'));
  }

  static String _prepLink(String raw) {
    var s = _basic(raw);
    s = s.replaceAll(RegExp(r'\s*\[\s*(?:\.|dot|ponto)\s*\]\s*'), '.');
    s = s.replaceAllMapped(
        RegExp(r'\s+(?:ponto|dot|punto|point)\s+(com|net|org|br|me|ly|app|io)\b'), (m) => '.${m[1]}');
    return s;
  }

  static List<String> findLinkHosts(String? raw) {
    final s = _prepLink(raw ?? '');
    final hosts = <String>[];
    final re = RegExp(
        r'(?:https?:\/\/|www\.)?((?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+([a-z]{2,24}))(?::\d+)?(?:\/[^\s]*)?');
    for (final m in re.allMatches(s)) {
      final full = m[0]!;
      final host = m[1]!.replaceAll(RegExp(r'\.+$'), '');
      final tld = m[2]!;
      final explicit = RegExp(r'^(?:https?:\/\/|www\.)').hasMatch(full);
      final before = m.start > 0 ? s[m.start - 1] : '';
      if (before == '@') {
        hosts.add(host);
        continue;
      }
      final hasPath = RegExp(r'\/[^\s]').hasMatch(full);
      final multiDot = host.split('.').length > 2;
      final tldOk = _tlds.contains(tld) && (!_ambiguousTlds.contains(tld) || hasPath || multiDot);
      if (explicit || _shortHosts.contains(host) || tldOk) {
        // evita "1.5" sem esquema. URL explícita e host com letra (192.168.0.1x.io) entram.
        if (!explicit && !RegExp('[a-z]').hasMatch(host)) continue;
        hosts.add(host);
      }
    }
    for (final m in RegExp(r'https?:\/\/((?:\d{1,3}\.){3}\d{1,3})(?::\d+)?(?:\/[^\s]*)?').allMatches(s)) {
      hosts.add(m[1]!);
    }
    return hosts;
  }

  static bool hasBlockedLink(String? raw) => findLinkHosts(raw).any((h) => !_hostAllowed(h));

  // ---------- telefones ----------
  static final RegExp _phoneWords = RegExp(
      r'\b(?:whats(?:app)?|wpp|zap|zapzap|tel|telefone|telemovel|fone|celular|cel|liga|ligue|chama|call|text me|phone|llamame|llama|movil|appelle|portable)\b');

  static bool hasPhone(String? raw) {
    final s = _basic(raw ?? '');
    final re = RegExp(r'(\+\s?)?(?:\(?\d[\d\s.\-()]{6,22}\d)');
    for (final m in re.allMatches(s)) {
      final chunk = m[0]!;
      final start = m.start;
      final end = m.end;
      final before = s.substring(start - 4 < 0 ? 0 : start - 4, start);
      final after = s.substring(end, end + 6 > s.length ? s.length : end + 6);
      final digits = chunk.replaceAll(RegExp(r'\D'), '');
      final plus = m[1] != null;
      final prev = start > 0 ? s[start - 1] : '';
      if (RegExp(r'[/:]').hasMatch(prev) || RegExp(r'^[/:h]\d').hasMatch(after)) continue;
      if (RegExp(r'(?:r\$|us\$|\$|€|£|eur|usd|brl|cad)\s*$').hasMatch(before)) continue;
      if (RegExp(r'^\s*(?:€|eur|reais|real|usd|dolares|dollars|cad|\$|%|km|kg|m2|mil)\b').hasMatch(after) ||
          RegExp(r'^\s*[€$%]').hasMatch(after)) {
        continue;
      }
      if (RegExp(r'[.,]\d{2}$').hasMatch(chunk) && !plus) continue;
      if (RegExp(r'^\d{4}[-.]\d{1,2}[-.]\d{1,2}$').hasMatch(chunk.trim())) continue;
      final groups = chunk.trim().split(RegExp(r'[\s.\-()]+')).where((g) => g.isNotEmpty).toList();
      if (groups.length > 1 && groups.every((g) => RegExp(r'^(?:19|20)\d{2}$').hasMatch(g))) continue;
      final n = digits.length;
      var phone = false;
      if (plus && n >= 8 && n <= 15) {
        phone = true;
      } else if (n >= 10 && n <= 13) {
        phone = true;
      } else if (n == 9 && RegExp(r'^[29]').hasMatch(digits) && groups.length >= 2) {
        phone = true;
      } else if (n >= 8 && n <= 9 && _phoneWords.hasMatch(s)) {
        phone = true;
      }
      if (phone) return true;
    }
    return false;
  }

  /// Decisão do bot para mensagem de grupo: 'insult' | 'profanity' | 'bot_link' | 'bot_phone' | null.
  static String? evaluateGroup(String? text, Map<String, dynamic>? group) {
    final raw = text ?? '';
    if (raw.trim().isEmpty) return null;
    final p = profanity(raw, loose: botFlag(group, 'blockProfanity'));
    if (p != null) return p;
    if (botFlag(group, 'blockLinks') && hasBlockedLink(raw)) return 'bot_link';
    if (botFlag(group, 'blockPhones') && hasPhone(raw)) return 'bot_phone';
    return null;
  }

  /// Chave do aviso para cada motivo.
  static String noticeKey(String reason) {
    switch (reason) {
      case 'bot_link':
        return 'bot_blocked_link';
      case 'bot_phone':
        return 'bot_blocked_phone';
      case 'profanity':
        return 'bot_blocked_profanity';
      default:
        return 'insult_blocked_notice';
    }
  }
}
