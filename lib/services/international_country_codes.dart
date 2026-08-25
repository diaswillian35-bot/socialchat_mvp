/// Normalização ISO alpha-2 alinhada a `international_dm_policy.js`.
class InternationalCountryCodes {
  InternationalCountryCodes._();

  static const Set<String> validIso2 = {
    'ad', 'ae', 'af', 'ag', 'ai', 'al', 'am', 'ao', 'aq', 'ar', 'as', 'at',
    'au', 'aw', 'ax', 'az', 'ba', 'bb', 'bd', 'be', 'bf', 'bg', 'bh', 'bi',
    'bj', 'bl', 'bm', 'bn', 'bo', 'bq', 'br', 'bs', 'bt', 'bv', 'bw', 'by',
    'bz', 'ca', 'cc', 'cd', 'cf', 'cg', 'ch', 'ci', 'ck', 'cl', 'cm', 'cn',
    'co', 'cr', 'cu', 'cv', 'cw', 'cx', 'cy', 'cz', 'de', 'dj', 'dk', 'dm',
    'do', 'dz', 'ec', 'ee', 'eg', 'eh', 'er', 'es', 'et', 'fi', 'fj', 'fk',
    'fm', 'fo', 'fr', 'ga', 'gb', 'gd', 'ge', 'gf', 'gg', 'gh', 'gi', 'gl',
    'gm', 'gn', 'gp', 'gq', 'gr', 'gs', 'gt', 'gu', 'gw', 'gy', 'hk', 'hm',
    'hn', 'hr', 'ht', 'hu', 'id', 'ie', 'il', 'im', 'in', 'io', 'iq', 'ir',
    'is', 'it', 'je', 'jm', 'jo', 'jp', 'ke', 'kg', 'kh', 'ki', 'km', 'kn',
    'kp', 'kr', 'kw', 'ky', 'kz', 'la', 'lb', 'lc', 'li', 'lk', 'lr', 'ls',
    'lt', 'lu', 'lv', 'ly', 'ma', 'mc', 'md', 'me', 'mf', 'mg', 'mh', 'mk',
    'ml', 'mm', 'mn', 'mo', 'mp', 'mq', 'mr', 'ms', 'mt', 'mu', 'mv', 'mw',
    'mx', 'my', 'mz', 'na', 'nc', 'ne', 'nf', 'ng', 'ni', 'nl', 'no', 'np',
    'nr', 'nu', 'nz', 'om', 'pa', 'pe', 'pf', 'pg', 'ph', 'pk', 'pl', 'pm',
    'pn', 'pr', 'ps', 'pt', 'pw', 'py', 'qa', 're', 'ro', 'rs', 'ru', 'rw',
    'sa', 'sb', 'sc', 'sd', 'se', 'sg', 'sh', 'si', 'sj', 'sk', 'sl', 'sm',
    'sn', 'so', 'sr', 'ss', 'st', 'sv', 'sx', 'sy', 'sz', 'tc', 'td', 'tf',
    'tg', 'th', 'tj', 'tk', 'tl', 'tm', 'tn', 'to', 'tr', 'tt', 'tv', 'tw',
    'tz', 'ua', 'ug', 'um', 'us', 'uy', 'uz', 'va', 'vc', 've', 'vg', 'vi',
    'vn', 'vu', 'wf', 'ws', 'ye', 'yt', 'za', 'zm', 'zw',
  };

  static const Map<String, String> nameAliases = {
    'brazil': 'br',
    'brasil': 'br',
    'canada': 'ca',
    'canadá': 'ca',
    'portugal': 'pt',
    'united states': 'us',
    'estados unidos': 'us',
    'usa': 'us',
    'united kingdom': 'gb',
    'reino unido': 'gb',
    'uk': 'gb',
    'mexico': 'mx',
    'méxico': 'mx',
    'argentina': 'ar',
    'chile': 'cl',
    'colombia': 'co',
    'colômbia': 'co',
    'peru': 'pe',
    'perú': 'pe',
    'france': 'fr',
    'frança': 'fr',
    'germany': 'de',
    'alemanha': 'de',
    'spain': 'es',
    'espanha': 'es',
    'italy': 'it',
    'itália': 'it',
    'australia': 'au',
    'austrália': 'au',
    'japan': 'jp',
    'japão': 'jp',
  };

  static String normalizeCandidate(String raw) {
    final s = raw.trim().toLowerCase();
    if (s.isEmpty) return '';
    if (s.length == 2 && validIso2.contains(s)) return s;
    return nameAliases[s] ?? '';
  }

  /// Resolve país canônico: homeCountryCode → countryCode → country (nome).
  static String resolve(Map<String, dynamic> data) {
    final home = normalizeCandidate(
      (data['homeCountryCode'] ?? '').toString(),
    );
    if (home.isNotEmpty) return home;

    final code = normalizeCandidate((data['countryCode'] ?? '').toString());
    if (code.isNotEmpty) return code;

    final countryName = (data['country'] ?? '').toString().trim().toLowerCase();
    if (countryName.isNotEmpty) return normalizeCandidate(countryName);

    return '';
  }
}

enum DmCountryRelation { same, international, unknown }
