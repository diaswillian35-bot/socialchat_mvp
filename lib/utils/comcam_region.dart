import 'user_search_normalize.dart';

/// Initial COMCAM / Campo Mourão regional unification for people browse.
/// Cities map to a shared region search key without exposing low counts.
class ComcamRegion {
  ComcamRegion._();

  static const String unifiedRegionKey = 'campo mourao comcam';
  static const String unifiedRegionLabel = 'Campo Mourão e região (COMCAM)';

  /// Normalized city names in the initial regional bucket (COMCAM core).
  static const Set<String> cityKeys = {
    'campo mourao',
    'araruna',
    'barbosa ferraz',
    'corumbatai do sul',
    'engenheiro beltrao',
    'farol',
    'fenix',
    'iretama',
    'luiziana',
    'mambore',
    'nova cantu',
    'peabiru',
    'quinta do sol',
    'roncador',
    'quarta pontes',
    'rancho alegre do oeste',
    'moreira sales',
    'terra boa',
  };

  static const Map<String, String> aliases = {
    'cm': 'campo mourao',
    'campo-mourao': 'campo mourao',
  };

  static String normalizeCity(String city) {
    var n = UserSearchNormalize.normalize(city);
    n = aliases[n] ?? n;
    return n;
  }

  static bool isComcamCity(String city) {
    final n = normalizeCity(city);
    return cityKeys.contains(n);
  }

  static String regionSearchKey({
    required String stateName,
    required String cityName,
  }) {
    if (isComcamCity(cityName)) return unifiedRegionKey;
    return UserSearchNormalize.normalize(stateName);
  }
}
