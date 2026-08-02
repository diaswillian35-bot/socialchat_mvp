import 'dart:math' as math;

import 'brazil_states.dart';
import 'events_geo_constants.dart';
import 'group_geo.dart';

/// Lógica pura (testável) da exploração nacional e Arredores.
class EventsBrasilExploreLogic {
  EventsBrasilExploreLogic._();

  /// Haversine em km (espelho da lista clássica / GroupGeo).
  static double distanceKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadius = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  /// Arredores: outra cidade e distância <= [EVENTS_SURROUNDINGS_RADIUS_KM].
  static bool passesSurroundings({
    required String userCity,
    required String eventCity,
    required double? userLat,
    required double? userLng,
    required double? eventLat,
    required double? eventLng,
    double radiusKm = EventsGeoConstants.EVENTS_SURROUNDINGS_RADIUS_KM,
  }) {
    if (userLat == null || userLng == null) return false;
    if (eventLat == null || eventLng == null) return false;
    if (!GroupGeo.validCoordinates(userLat, userLng) ||
        !GroupGeo.validCoordinates(eventLat, eventLng)) {
      return false;
    }

    final uCity = userCity.toLowerCase().trim();
    final eCity = eventCity.toLowerCase().trim();
    if (uCity.isNotEmpty && eCity.isNotEmpty && uCity == eCity) {
      return false;
    }

    final d = distanceKm(userLat, userLng, eventLat, eventLng);
    return d <= radiusKm;
  }

  /// Deduplica por ID preservando a primeira ocorrência.
  static List<T> dedupeById<T>(
    Iterable<T> items,
    String Function(T) idOf,
  ) {
    final seen = <String>{};
    final out = <T>[];
    for (final item in items) {
      final id = idOf(item);
      if (id.isEmpty || !seen.add(id)) continue;
      out.add(item);
    }
    return out;
  }

  /// Agrupa eventos em estados com contagem. Só estados com count > 0.
  /// [userStateRaw] vai primeiro; demais em ordem alfabética pelo nome.
  static List<BrasilStateSummary> buildStateSummaries({
    required Iterable<BrasilEventRef> events,
    String? userStateRaw,
    bool preferBrazilCatalog = true,
  }) {
    final buckets = <String, _StateBucket>{};

    for (final e in events) {
      final rawCode = e.stateCode;
      final rawName = e.stateName;
      final key = preferBrazilCatalog
          ? (BrazilStates.groupingKey(
                rawCode.trim().isNotEmpty ? rawCode : rawName,
              ))
          : (rawCode.trim().isNotEmpty
              ? rawCode.trim().toLowerCase()
              : rawName.trim().toLowerCase());
      if (key.isEmpty) continue;

      final bucket = buckets.putIfAbsent(
        key,
        () => _StateBucket(
          key: key,
          name: preferBrazilCatalog
              ? BrazilStates.displayName(
                  rawCode.trim().isNotEmpty ? rawCode : rawName,
                )
              : (rawName.trim().isNotEmpty ? rawName.trim() : rawCode.trim()),
          uf: preferBrazilCatalog
              ? BrazilStates.displayUf(
                  rawCode.trim().isNotEmpty ? rawCode : rawName,
                )
              : (rawCode.trim().length == 2 ? rawCode.trim().toUpperCase() : ''),
        ),
      );
      if (!bucket.ids.add(e.id)) continue;
      bucket.count += 1;
    }

    final userKey = preferBrazilCatalog
        ? BrazilStates.groupingKey(userStateRaw)
        : (userStateRaw ?? '').trim().toLowerCase();

    final list = buckets.values
        .where((b) => b.count > 0)
        .map(
          (b) => BrasilStateSummary(
            key: b.key,
            name: b.name.isNotEmpty ? b.name : b.key,
            uf: b.uf,
            eventCount: b.count,
            isUserState: userKey.isNotEmpty && b.key == userKey,
          ),
        )
        .toList();

    list.sort((a, b) {
      if (a.isUserState != b.isUserState) {
        return a.isUserState ? -1 : 1;
      }
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return list;
  }

  /// Eventos de um estado (por chave UF/nome). Sem filtro de distância.
  static List<BrasilEventRef> eventsForState({
    required Iterable<BrasilEventRef> events,
    required String stateKey,
    bool preferBrazilCatalog = true,
  }) {
    final want = stateKey.trim();
    if (want.isEmpty) return const [];

    final filtered = <BrasilEventRef>[];
    final seen = <String>{};
    for (final e in events) {
      if (e.id.isEmpty || !seen.add(e.id)) continue;
      final key = preferBrazilCatalog
          ? BrazilStates.groupingKey(
              e.stateCode.trim().isNotEmpty ? e.stateCode : e.stateName,
            )
          : (e.stateCode.trim().isNotEmpty
              ? e.stateCode.trim().toLowerCase()
              : e.stateName.trim().toLowerCase());
      if (key != want) continue;
      filtered.add(e);
    }
    return filtered;
  }

  /// Busca por cidade ou título do evento (case-insensitive, sem acento).
  static bool matchesCityOrTitle({
    required String query,
    required String title,
    required String city,
  }) {
    final q = _fold(query);
    if (q.isEmpty) return true;
    return _fold(title).contains(q) || _fold(city).contains(q);
  }

  static String _fold(String raw) {
    return raw
        .trim()
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('â', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ç', 'c');
  }

  /// Patrocinado primeiro; depois startAt ascendente (nulos por último).
  static int compareSponsoredThenStart({
    required bool aSponsored,
    required bool bSponsored,
    required DateTime? aStart,
    required DateTime? bStart,
  }) {
    final s = (bSponsored ? 1 : 0).compareTo(aSponsored ? 1 : 0);
    if (s != 0) return s;
    if (aStart == null && bStart == null) return 0;
    if (aStart == null) return 1;
    if (bStart == null) return -1;
    return aStart.compareTo(bStart);
  }
}

class BrasilEventRef {
  const BrasilEventRef({
    required this.id,
    required this.title,
    required this.city,
    required this.stateName,
    this.stateCode = '',
    this.startAt,
    this.sponsored = false,
  });

  final String id;
  final String title;
  final String city;
  final String stateName;
  final String stateCode;
  final DateTime? startAt;
  final bool sponsored;
}

class BrasilStateSummary {
  const BrasilStateSummary({
    required this.key,
    required this.name,
    required this.uf,
    required this.eventCount,
    this.isUserState = false,
  });

  final String key;
  final String name;
  final String uf;
  final int eventCount;
  final bool isUserState;
}

class _StateBucket {
  _StateBucket({
    required this.key,
    required this.name,
    required this.uf,
  });

  final String key;
  String name;
  String uf;
  final Set<String> ids = <String>{};
  int count = 0;
}
