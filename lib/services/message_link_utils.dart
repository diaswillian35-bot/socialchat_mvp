/// Detecção e validação de links em mensagens (Parte 4B–4D).
///
/// Regras:
/// - Aceita apenas web `https://` (ou domínio válido sem esquema → https).
/// - Não transforma e-mails em links.
/// - Bloqueia esquemas perigosos.
/// - Domínios oficiais Remdy (`remdy.app`) são deep links internos.
class MessageLinkMatch {
  const MessageLinkMatch({
    required this.raw,
    required this.start,
    required this.end,
    required this.normalizedHttpsUrl,
    required this.isRemdyInternal,
    required this.displayHost,
  });

  final String raw;
  final int start;
  final int end;
  final String normalizedHttpsUrl;
  final bool isRemdyInternal;

  /// Host registrável / apex para confirmação (ex.: amazon.com).
  final String displayHost;
}

class MessageLinkUtils {
  MessageLinkUtils._();

  static const Set<String> remdyHosts = {
    'remdy.app',
    'www.remdy.app',
  };

  static const Set<String> blockedSchemes = {
    'javascript',
    'data',
    'file',
    'intent',
    'content',
    'about',
    'blob',
    'ftp',
    'mailto',
    'tel',
    'sms',
    'ws',
    'wss',
  };

  /// TLD comuns + genéricos; evita transformar "oi.tudo" em link.
  static final RegExp _bareDomain = RegExp(
    r'(?<![\w@])(?:www\.)?(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+(?:com|net|org|edu|gov|io|co|app|dev|info|biz|br|ca|uk|us|pt|es|fr|de|it|jp|au|in|mx|ar|cl|pe|uy|py|bo|ec|ve|nl|be|ch|at|se|no|dk|fi|pl|cz|ro|hu|gr|tr|za|nz|sg|hk|tw|kr|cn|ru|ua|il|ae|sa|id|ph|th|vn|my|pk|bd|ng|eg|ma|ke|gh|tz|ug|zw|me|tv|cc|xyz|online|store|shop|site|blog|cloud|tech|ai)(?::\d{2,5})?(?:/[^\s]*)?',
    caseSensitive: false,
  );

  static final RegExp _explicitUrl = RegExp(
    r'(?<![\w])(?:https?):\/\/[^\s<>"]+',
    caseSensitive: false,
  );

  static final RegExp _emailLike = RegExp(
    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
  );

  /// Extrai links do texto na ordem de aparição.
  static List<MessageLinkMatch> extractLinks(String text) {
    if (text.trim().isEmpty) return const [];

    final matches = <MessageLinkMatch>[];
    final occupied = <_Range>[];

    void consider(int start, int end, String raw) {
      final trimmed = _trimTrailingPunctuation(raw);
      if (trimmed.isEmpty) return;
      final endAdj = start + trimmed.length;
      for (final r in occupied) {
        if (start < r.end && endAdj > r.start) return;
      }
      final normalized = normalizeToHttps(trimmed);
      if (normalized == null) return;
      final uri = Uri.tryParse(normalized);
      if (uri == null || !isAllowedHttpsUri(uri)) return;
      occupied.add(_Range(start, endAdj));
      matches.add(
        MessageLinkMatch(
          raw: trimmed,
          start: start,
          end: endAdj,
          normalizedHttpsUrl: normalized,
          isRemdyInternal: isRemdyHost(uri.host),
          displayHost: displayDomain(uri.host),
        ),
      );
    }

    for (final m in _explicitUrl.allMatches(text)) {
      consider(m.start, m.end, m.group(0)!);
    }
    for (final m in _bareDomain.allMatches(text)) {
      final raw = m.group(0)!;
      if (_emailLike.hasMatch(raw)) continue;
      // Evita e-mail: caractere imediatamente antes é @
      if (m.start > 0 && text[m.start - 1] == '@') continue;
      consider(m.start, m.end, raw);
    }

    matches.sort((a, b) => a.start.compareTo(b.start));
    return matches;
  }

  static String _trimTrailingPunctuation(String raw) {
    var s = raw.trim();
    // Remove pontuação de frase colada ao final do link.
    while (s.isNotEmpty &&
        '.,);]!?:\'\"…»'.contains(s[s.length - 1])) {
      s = s.substring(0, s.length - 1);
    }
    // Balanceia parênteses finais sobrando.
    if (s.endsWith(')') && !_hasBalancedParens(s)) {
      s = s.substring(0, s.length - 1);
    }
    return s.trim();
  }

  static bool _hasBalancedParens(String s) {
    var n = 0;
    for (final c in s.codeUnits) {
      if (c == 0x28) n++;
      if (c == 0x29) n--;
      if (n < 0) return false;
    }
    return n == 0;
  }

  /// Normaliza para URL https absoluta, ou null se inválida/bloqueada.
  static String? normalizeToHttps(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    if (_emailLike.hasMatch(t)) return null;

    final lower = t.toLowerCase();
    final schemeMatch = RegExp(r'^([a-z][a-z0-9+.-]*):').firstMatch(lower);
    if (schemeMatch != null) {
      final scheme = schemeMatch.group(1)!;
      if (blockedSchemes.contains(scheme)) return null;
      if (scheme == 'http') {
        // Só aceitamos https — upgrade explícito de http digitado.
        final upgraded = 'https://${t.substring(scheme.length + 1)}';
        return _finalizeHttps(upgraded);
      }
      if (scheme != 'https') return null;
      return _finalizeHttps(t);
    }

    return _finalizeHttps('https://$t');
  }

  static String? _finalizeHttps(String candidate) {
    final uri = Uri.tryParse(candidate);
    if (uri == null) return null;
    if (!isAllowedHttpsUri(uri)) return null;
    return uri.toString();
  }

  static bool isAllowedHttpsUri(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https') return false;
    if (uri.host.isEmpty) return false;
    if (uri.userInfo.isNotEmpty) return false;
    final host = uri.host.toLowerCase();
    if (host == 'localhost' || host.endsWith('.localhost')) return false;
    if (_isIpLiteral(host) && isPrivateOrLocalIp(host)) return false;
    return true;
  }

  static bool isRemdyHost(String host) {
    final h = host.toLowerCase().trim();
    if (remdyHosts.contains(h)) return true;
    return h.endsWith('.remdy.app');
  }

  /// Domínio exibido na confirmação (reduz engano por subdomínio).
  static String displayDomain(String host) {
    final h = host.toLowerCase().trim();
    if (h.isEmpty) return host;
    final parts = h.split('.');
    if (parts.length <= 2) return h;
    // co.uk / com.br etc.
    const multi = {
      'co.uk',
      'com.br',
      'com.au',
      'co.jp',
      'com.mx',
      'com.ar',
      'co.za',
      'com.pt',
    };
    final last2 = '${parts[parts.length - 2]}.${parts[parts.length - 1]}';
    if (multi.contains(last2) && parts.length >= 3) {
      return '${parts[parts.length - 3]}.$last2';
    }
    return last2;
  }

  static bool _isIpLiteral(String host) {
    if (host.contains(':')) return true; // IPv6
    final parts = host.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }

  /// Bloqueia localhost, privados, link-local, multicast, metadata (v4/v6).
  static bool isPrivateOrLocalIp(String host) {
    final h = host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
    if (h == 'localhost') return true;

    // IPv4
    final v4 = h.split('.');
    if (v4.length == 4 && v4.every((p) => int.tryParse(p) != null)) {
      final a = int.parse(v4[0]);
      final b = int.parse(v4[1]);
      if (a == 10) return true;
      if (a == 127) return true;
      if (a == 0) return true;
      if (a == 169 && b == 254) return true; // link-local / metadata AWS
      if (a == 172 && b >= 16 && b <= 31) return true;
      if (a == 192 && b == 168) return true;
      if (a == 100 && b >= 64 && b <= 127) return true; // CGNAT
      if (a >= 224) return true; // multicast/reserved
      return false;
    }

    // IPv6
    if (h.contains(':')) {
      if (h == '::1' || h == '::') return true;
      if (h.startsWith('fc') || h.startsWith('fd')) return true; // ULA
      if (h.startsWith('fe80')) return true; // link-local
      if (h.startsWith('ff')) return true; // multicast
      // IPv4-mapped
      if (h.contains('.')) {
        final mapped = h.split(':').last;
        if (isPrivateOrLocalIp(mapped)) return true;
      }
      return false;
    }
    return false;
  }

  /// Primeiro link externo elegível para prévia (ignora deep links Remdy).
  static MessageLinkMatch? firstPreviewCandidate(String text) {
    for (final m in extractLinks(text)) {
      if (!m.isRemdyInternal) return m;
    }
    return null;
  }
}

class _Range {
  _Range(this.start, this.end);
  final int start;
  final int end;
}
