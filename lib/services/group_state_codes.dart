import 'brazil_states.dart';

/// Sigla canônica de estado/província e nome para os títulos de seção da aba
/// Grupos ("Perto de você"). Espelha functions/group_state_codes.js.
class GroupStateCodes {
  GroupStateCodes._();

  static String _fold(String raw) {
    const from = 'áàãâäéèêëíìîïóòõôöúùûüçñÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇÑ';
    const to = 'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN';
    final b = StringBuffer();
    for (final ch in raw.split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim();
  }

  static const Map<String, List<String>> _caAliases = {
    'AB': ['Alberta'],
    'BC': [
      'British Columbia',
      'Colombie Britannique',
      'Columbia Britanica',
      'Colúmbia Britânica'
    ],
    'MB': ['Manitoba'],
    'NB': [
      'New Brunswick',
      'Nouveau Brunswick',
      'Nova Brunswick',
      'Nuevo Brunswick'
    ],
    'NL': [
      'Newfoundland and Labrador',
      'Terre Neuve et Labrador',
      'Terra Nova e Labrador',
      'Terranova y Labrador',
      'Newfoundland'
    ],
    'NS': ['Nova Scotia', 'Nouvelle Ecosse', 'Nova Escocia', 'Nueva Escocia'],
    'NT': [
      'Northwest Territories',
      'Territoires du Nord Ouest',
      'Territorios do Noroeste',
      'Territorios del Noroeste'
    ],
    'NU': ['Nunavut'],
    'ON': ['Ontario', 'Ontário'],
    'PE': [
      'Prince Edward Island',
      'Ile du Prince Edouard',
      'Ilha do Principe Eduardo',
      'Isla del Principe Eduardo'
    ],
    'QC': ['Quebec', 'Québec'],
    'SK': ['Saskatchewan'],
    'YT': ['Yukon', 'Yukon Territory', 'Yukón'],
  };

  static final Map<String, String> _caByFold = () {
    final map = <String, String>{};
    _caAliases.forEach((code, names) {
      map[_fold(code)] = code;
      for (final n in names) {
        map[_fold(n)] = code;
      }
    });
    return map;
  }();

  /// Nomes das províncias do Canadá: pt (pt-BR e pt-PT), en, es, fr.
  static const Map<String, Map<String, String>> _caNames = {
    'ON': {'pt': 'Ontário', 'en': 'Ontario', 'es': 'Ontario', 'fr': 'Ontario'},
    'QC': {'pt': 'Quebec', 'en': 'Quebec', 'es': 'Quebec', 'fr': 'Québec'},
    'BC': {
      'pt': 'Colúmbia Britânica',
      'en': 'British Columbia',
      'es': 'Columbia Británica',
      'fr': 'Colombie-Britannique'
    },
    'AB': {'pt': 'Alberta', 'en': 'Alberta', 'es': 'Alberta', 'fr': 'Alberta'},
    'MB': {
      'pt': 'Manitoba',
      'en': 'Manitoba',
      'es': 'Manitoba',
      'fr': 'Manitoba'
    },
    'SK': {
      'pt': 'Saskatchewan',
      'en': 'Saskatchewan',
      'es': 'Saskatchewan',
      'fr': 'Saskatchewan'
    },
    'NS': {
      'pt': 'Nova Escócia',
      'en': 'Nova Scotia',
      'es': 'Nueva Escocia',
      'fr': 'Nouvelle-Écosse'
    },
    'NB': {
      'pt': 'Nova Brunswick',
      'en': 'New Brunswick',
      'es': 'Nuevo Brunswick',
      'fr': 'Nouveau-Brunswick'
    },
    'PE': {
      'pt': 'Ilha do Príncipe Eduardo',
      'en': 'Prince Edward Island',
      'es': 'Isla del Príncipe Eduardo',
      'fr': 'Île-du-Prince-Édouard'
    },
    'NL': {
      'pt': 'Terra Nova e Labrador',
      'en': 'Newfoundland and Labrador',
      'es': 'Terranova y Labrador',
      'fr': 'Terre-Neuve-et-Labrador'
    },
    'NT': {
      'pt': 'Territórios do Noroeste',
      'en': 'Northwest Territories',
      'es': 'Territorios del Noroeste',
      'fr': 'Territoires du Nord-Ouest'
    },
    'YT': {'pt': 'Yukon', 'en': 'Yukon', 'es': 'Yukón', 'fr': 'Yukon'},
    'NU': {'pt': 'Nunavut', 'en': 'Nunavut', 'es': 'Nunavut', 'fr': 'Nunavut'},
  };

  /// Sigla em maiúsculas ("PR", "ON") ou '' quando não há estado confiável.
  static String normalize(String countryCode, dynamic raw) {
    final cc = countryCode.trim().toLowerCase();
    var value = (raw ?? '').toString().trim();
    if (value.isEmpty) return '';
    final cityUf = RegExp(r'^(.+?)\s*[-–]\s*([A-Za-z]{2})$').firstMatch(value);
    if (cityUf != null) value = cityUf.group(2)!;
    var key = _fold(value);
    if (key.isEmpty) return '';
    if (cc == 'br') {
      key = key.replaceFirst(
          RegExp(r'^(state of|estado de|estado do|estado da) '), '');
      final info = BrazilStates.resolve(key);
      return info?.uf ?? '';
    }
    if (cc == 'ca') return _caByFold[key] ?? '';
    if (RegExp(r'^[a-z0-9]{1,3}$').hasMatch(key)) return key.toUpperCase();
    return key.toUpperCase().replaceAll(' ', '_');
  }

  /// "br-pr"; '' quando falta país ou estado.
  static String stateKey(String countryCode, String stateCode) {
    final cc = countryCode.trim().toLowerCase();
    final sc = stateCode.trim().toLowerCase();
    if (cc.isEmpty || sc.isEmpty) return '';
    return '$cc-$sc';
  }

  /// stateKey do grupo: o campo novo quando existe, senão derivado de stateName.
  static String groupStateKey(Map<String, dynamic> data, String countryCode) {
    final stored = (data['stateKey'] ?? '').toString().trim().toLowerCase();
    if (stored.isNotEmpty) return stored;
    final code = normalize(countryCode, data['stateCode'] ?? data['stateName']);
    return stateKey(countryCode, code);
  }

  /// Sigla canônica ("PR") a partir de stateKey, stateCode ou stateName.
  /// Aceita "br-pr", "PR", "Paraná" e equivalentes, só no app (sem backfill).
  static String canonicalStateCode(
    String countryCode, {
    String stateKey = '',
    dynamic stateCode,
    dynamic stateName,
  }) {
    final fromCode = normalize(countryCode, stateCode);
    if (fromCode.isNotEmpty) return fromCode;
    final fromName = normalize(countryCode, stateName);
    if (fromName.isNotEmpty) return fromName;
    return _canonicalFromStateKey(countryCode, stateKey);
  }

  static String _canonicalFromStateKey(String countryCode, String stateKey) {
    final stored = stateKey.trim();
    if (stored.isEmpty) return '';
    final cc = countryCode.trim().toLowerCase();
    final lower = stored.toLowerCase();
    var candidate = stored;
    if (cc.isNotEmpty &&
        (lower.startsWith('$cc-') || lower.startsWith('${cc}_'))) {
      candidate = stored.substring(cc.length + 1);
    } else if (lower.contains('-')) {
      candidate = stored.split('-').last;
    }
    return normalize(countryCode, candidate);
  }

  static String canonicalStateCodeFromData(
    Map<String, dynamic> data,
    String countryCode,
  ) {
    return canonicalStateCode(
      countryCode,
      stateKey: (data['stateKey'] ?? '').toString(),
      stateCode: data['stateCode'],
      stateName: data['stateName'],
    );
  }

  /// Sem estado confiável no grupo ou no usuário: não exclui por estado.
  /// Só retorna false quando os dois lados têm sigla e elas diferem.
  static bool sameStateOrUndetermined({
    required String countryCode,
    required Map<String, dynamic> groupData,
    required String viewerStateCode,
    String viewerStateKey = '',
  }) {
    final g = canonicalStateCodeFromData(groupData, countryCode);
    final v = canonicalStateCode(
      countryCode,
      stateKey: viewerStateKey,
      stateCode: viewerStateCode,
    );
    if (g.isEmpty || v.isEmpty) return true;
    return g == v;
  }

  /// Nome do estado para título de seção, no idioma do app.
  static String displayName({
    required String countryCode,
    required String stateCode,
    String languageCode = 'pt',
    String fallback = '',
  }) {
    final cc = countryCode.trim().toLowerCase();
    final sc = stateCode.trim().toUpperCase();
    if (sc.isEmpty) return fallback;
    if (cc == 'br') {
      final info = BrazilStates.resolve(sc);
      if (info != null) return info.name;
    }
    if (cc == 'ca') {
      final names = _caNames[sc];
      if (names != null) {
        final lang = languageCode.toLowerCase();
        final key = lang.startsWith('pt')
            ? 'pt'
            : lang.startsWith('es')
                ? 'es'
                : lang.startsWith('fr')
                    ? 'fr'
                    : 'en';
        return names[key] ?? names['en']!;
      }
    }
    return fallback.isNotEmpty ? fallback : sc.replaceAll('_', ' ');
  }

  /// No Canadá a palavra é "província"; nos outros países, "estado".
  static bool usesProvince(String countryCode) =>
      countryCode.trim().toLowerCase() == 'ca';
}
