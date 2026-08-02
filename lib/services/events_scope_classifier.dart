import 'events_geo_constants.dart';
import 'group_geo.dart';
import 'events_brasil_explore_logic.dart';

/// Escopos mutuamente exclusivos da aba clássica Eventos.
enum EventsClassicScopeBucket {
  /// Mesma cidade do perfil (`cityKey` / nome normalizado).
  city,

  /// Outra cidade no mesmo país, 0 < d ≤ raio (110 km).
  surroundings,

  /// Mesmo país, d > raio **ou** evento nacional (`scope: country`).
  country,

  /// `countryCode` diferente do perfil.
  outOfCountry,

  /// Dados insuficientes para classificar com segurança (ex.: local sem coords).
  unclassifiable,
}

/// Classificador canônico Cidade / Arredores / País (exclusivo).
///
/// Única regra geográfica da lista clássica — páginas e testes devem
/// reutilizar este helper em vez de duplicar Haversine/limites.
class EventsScopeClassifier {
  EventsScopeClassifier._();

  static String normalizeCityKey(Object? raw) =>
      (raw ?? '').toString().trim().toLowerCase();

  static String normalizeCountryCode(Object? raw) =>
      (raw ?? '').toString().trim().toLowerCase();

  static String normalizeEventScope(Object? raw) =>
      (raw ?? '').toString().trim().toLowerCase();

  /// Evento nacional: aparece no escopo País sem exigir distância.
  static bool isNationalEventScope(Object? scope) =>
      normalizeEventScope(scope) == 'country';

  static bool sameCity({
    required String userCityKey,
    required String eventCityKey,
    String userCityName = '',
    String eventCityName = '',
  }) {
    final uk = normalizeCityKey(userCityKey);
    final ek = normalizeCityKey(eventCityKey);
    if (uk.isNotEmpty && ek.isNotEmpty && uk == ek) return true;

    final un = normalizeCityKey(userCityName);
    final en = normalizeCityKey(eventCityName);
    if (un.isNotEmpty && en.isNotEmpty && un == en) return true;
    return false;
  }

  static double? tryDistanceKm({
    required double? userLat,
    required double? userLng,
    required double? eventLat,
    required double? eventLng,
  }) {
    if (!GroupGeo.validCoordinates(userLat, userLng) ||
        !GroupGeo.validCoordinates(eventLat, eventLng)) {
      return null;
    }
    return EventsBrasilExploreLogic.distanceKm(
      userLat!,
      userLng!,
      eventLat!,
      eventLng!,
    );
  }

  /// Classifica um evento relativo ao perfil autenticado.
  ///
  /// [userHasCoordinates] / coords do evento devem ser validados via
  /// [GroupGeo.validCoordinates] antes — valores inválidos → unclassifiable
  /// (exceto nacional / fora do país / mesma cidade).
  static EventsClassicScopeBucket classify({
    required String userCountryCode,
    required String eventCountryCode,
    required String userCityKey,
    required String eventCityKey,
    String userCityName = '',
    String eventCityName = '',
    double? userLat,
    double? userLng,
    double? eventLat,
    double? eventLng,
    String eventScope = '',
    double radiusKm = EventsGeoConstants.EVENTS_SURROUNDINGS_RADIUS_KM,
  }) {
    final uCountry = normalizeCountryCode(userCountryCode);
    final eCountry = normalizeCountryCode(eventCountryCode);

    if (uCountry.isEmpty || eCountry.isEmpty || uCountry != eCountry) {
      return EventsClassicScopeBucket.outOfCountry;
    }

    if (sameCity(
      userCityKey: userCityKey,
      eventCityKey: eventCityKey,
      userCityName: userCityName,
      eventCityName: eventCityName,
    )) {
      return EventsClassicScopeBucket.city;
    }

    // Nacional: contrato do escopo País (sem distância).
    if (isNationalEventScope(eventScope)) {
      return EventsClassicScopeBucket.country;
    }

    final userOk = GroupGeo.validCoordinates(userLat, userLng);
    final eventOk = GroupGeo.validCoordinates(eventLat, eventLng);
    if (!userOk || !eventOk) {
      return EventsClassicScopeBucket.unclassifiable;
    }

    final d = EventsBrasilExploreLogic.distanceKm(
      userLat!,
      userLng!,
      eventLat!,
      eventLng!,
    );

    // d == 0 (mesmo ponto) não entra em Arredores.
    if (d > 0 && d <= radiusKm) {
      return EventsClassicScopeBucket.surroundings;
    }
    if (d > radiusKm) {
      return EventsClassicScopeBucket.country;
    }
    return EventsClassicScopeBucket.unclassifiable;
  }

  static bool matchesSelectedScope({
    required EventsClassicScopeBucket bucket,
    required int selectedScopeIndex,
  }) {
    switch (selectedScopeIndex) {
      case 0:
        return bucket == EventsClassicScopeBucket.city;
      case 1:
        return bucket == EventsClassicScopeBucket.surroundings;
      case 2:
        return bucket == EventsClassicScopeBucket.country;
      default:
        return false;
    }
  }

  /// Perfil sem coords: Cidade ok; Arredores/País exigem CTA (não inventar).
  static bool userNeedsLocationForGeoScopes({
    required double? userLat,
    required double? userLng,
  }) =>
      !GroupGeo.validCoordinates(userLat, userLng);
}
