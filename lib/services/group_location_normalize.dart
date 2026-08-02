/// Normalização canônica de localização de grupos (global / multi-país).
///
/// Usado pela descoberta (Cidade / Região / País) e por scripts de backfill.
/// Não altera documentos automaticamente — só deriva chaves estáveis.
/// Região radial é tratada por `GroupGeo`; estado/província não define Região.
class GroupLocationNormalize {
  GroupLocationNormalize._();

  /// ISO-2 em minúsculas. Aceita códigos e alguns nomes legados.
  static String countryCode(dynamic raw) {
    final v = (raw ?? '').toString().trim().toLowerCase();
    if (v.isEmpty) return '';
    if (v == 'brasil' || v == 'brazil') return 'br';
    if (v == 'canada' || v == 'canadá') return 'ca';
    if (v == 'portugal') return 'pt';
    if (v.length == 2) return v;
    return v;
  }

  /// Remove acentos, colapsa espaços e lowercase — chave de cidade.
  static String cityKey(dynamic raw) {
    final base = _fold((raw ?? '').toString().trim().toLowerCase());
    if (base.isEmpty) return '';
    return base.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Escopo canônico: `city` | `region` | `country`.
  ///
  /// Valores ausentes/ilegados → `unknown` (não entram em abas de descoberta).
  static String scope(dynamic raw) {
    final p = (raw ?? '').toString().trim().toLowerCase();
    if (p == 'city' || p == 'cidade') return 'city';
    if (p == 'region' || p == 'região' || p == 'regiao') {
      return 'region';
    }
    if (p == 'country' || p == 'país' || p == 'pais' || p == 'national') {
      return 'country';
    }
    return 'unknown';
  }

  static String cityDisplayName(Map<String, dynamic> data) {
    final city = (data['city'] ?? data['cityName'] ?? '').toString().trim();
    return city;
  }

  static String _fold(String input) {
    const map = <String, String>{
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
      'ñ': 'n',
    };
    final buf = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      buf.write(map[ch] ?? ch);
    }
    return buf.toString();
  }
}
