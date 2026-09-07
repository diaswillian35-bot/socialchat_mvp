import 'group_geo.dart';
import 'people_browse_grouping.dart';
import 'brazil_states.dart';
import '../utils/user_search_normalize.dart';

/// Escopo de descoberta de pessoas por cidade e raio geográfico.
///
/// Campos canônicos: `cityName`, `cityLat`/`cityLng` (fallback `lat`/`lng`),
/// `homeCountryCode`. Estado/província é só visual — nunca define o raio.
///
/// “Ver todos” / região = mesmo país + distância ≤ [regionRadiusKm] (110 km).
class UserLocationScope {
  UserLocationScope._();

  /// Raio canônico da região de pessoas (mesmo valor dos grupos/eventos).
  static const double regionRadiusKm = GroupGeo.regionRadiusKm;

  /// Tolerância para considerar o mesmo centro de cidade na Home.
  static const double sameCityMaxDistanceKm = 25;

  /// Coordenadas canônicas do centro da cidade (nunca GPS residencial).
  static GroupLatLng? resolveCanonicalCoords(
    Map<String, dynamic>? data,
  ) {
    if (data == null) return null;
    final lat = _asNum(data['cityLat'] ?? data['lat']);
    final lng = _asNum(data['cityLng'] ?? data['lng']);
    if (!isValidCityCoordinate(lat, lng)) return null;
    return GroupLatLng(lat!.toDouble(), lng!.toDouble());
  }

  /// Rejeita null, NaN, fora de faixa e (0,0) / Null Island.
  static bool isValidCityCoordinate(num? latitude, num? longitude) {
    if (!GroupGeo.validCoordinates(latitude, longitude)) return false;
    if (latitude!.abs() < 1e-6 && longitude!.abs() < 1e-6) return false;
    return true;
  }

  static String cityNameFromUserData(Map<String, dynamic>? data) {
    if (data == null) return '';
    return _firstNonEmpty([data['cityName'], data['city']]);
  }

  /// Estado/província — apenas exibição; não entra no raio.
  static String stateLabelFromUserData(Map<String, dynamic>? data) {
    if (data == null) return '';
    return _firstNonEmpty([
      data['stateName'],
      data['stateCode'],
      data['state'],
    ]);
  }

  /// Localização normalizada para rótulos (estado opcional).
  static PeopleBrowseLocation? resolveFromUserData(Map<String, dynamic>? data) {
    if (data == null) return null;
    final city = cityNameFromUserData(data);
    if (city.isEmpty) return null;
    final state = stateLabelFromUserData(data);
    final loc = PeopleBrowseGrouping.normalizeLocation(
      city: city,
      state: state.isEmpty ? city : state,
    );
    if (loc.cityDisplay.isEmpty || loc.cityDisplay == '—') return null;
    if (loc.cityKey.isEmpty || loc.cityKey == '—') return null;
    return loc;
  }

  static String countryCodeFromUserData(Map<String, dynamic>? data) {
    if (data == null) return '';
    final raw = (data['homeCountryCode'] ?? data['countryCode'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    return raw;
  }

  /// País + cidade + lat/lng canônicos válidos — obrigatório para usar o app.
  static bool hasCompleteProfileLocation(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (countryCodeFromUserData(data).isEmpty) return false;
    if (cityNameFromUserData(data).isEmpty) return false;
    return resolveCanonicalCoords(data) != null;
  }

  /// Pode aparecer em Home / Ver todos / descoberta.
  static bool isDiscoverableProfile(Map<String, dynamic>? data) {
    return hasCompleteProfileLocation(data);
  }

  static double? distanceKmBetweenUsers(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final ca = resolveCanonicalCoords(a);
    final cb = resolveCanonicalCoords(b);
    if (ca == null || cb == null) return null;
    return GroupGeo.distanceKm(
      lat1: ca.latitude,
      lng1: ca.longitude,
      lat2: cb.latitude,
      lng2: cb.longitude,
    );
  }

  /// Mesma cidade na Home: mesmo país, mesmo nome normalizado, centros próximos.
  /// Estado não decide o match; distância evita homônimos distantes.
  static bool sameCityFromUserData(
    Map<String, dynamic> viewer,
    Map<String, dynamic> other,
  ) {
    if (!isDiscoverableProfile(viewer) || !isDiscoverableProfile(other)) {
      return false;
    }
    final c1 = countryCodeFromUserData(viewer);
    final c2 = countryCodeFromUserData(other);
    if (c1.isEmpty || c1 != c2) return false;

    final k1 = UserSearchNormalize.normalize(cityNameFromUserData(viewer));
    final k2 = UserSearchNormalize.normalize(cityNameFromUserData(other));
    if (k1.isEmpty || k1 != k2) return false;

    final d = distanceKmBetweenUsers(viewer, other);
    if (d == null) return false;
    return d <= sameCityMaxDistanceKm + 1e-9;
  }

  /// Região (“Ver todos”): mesmo país + Haversine ≤ 110 km.
  /// Estado/UF/COMCAM administrativo **não** entra no critério.
  static bool withinRegionRadiusFromUserData(
    Map<String, dynamic> viewer,
    Map<String, dynamic> other, {
    double radiusKm = regionRadiusKm,
  }) {
    if (!isDiscoverableProfile(viewer) || !isDiscoverableProfile(other)) {
      return false;
    }
    final c1 = countryCodeFromUserData(viewer);
    final c2 = countryCodeFromUserData(other);
    if (c1.isEmpty || c1 != c2) return false;

    final va = resolveCanonicalCoords(viewer)!;
    final vb = resolveCanonicalCoords(other)!;
    return GroupGeo.withinRegion(
      userLat: va.latitude,
      userLng: va.longitude,
      centerLat: vb.latitude,
      centerLng: vb.longitude,
      radiusKm: radiusKm,
    );
  }

  static bool matchesViewerCity({
    required Map<String, dynamic> otherData,
    required String viewerCity,
    required String viewerCountryCode,
    required double viewerLat,
    required double viewerLng,
  }) {
    if (!isDiscoverableProfile(otherData)) return false;
    if (!isValidCityCoordinate(viewerLat, viewerLng)) return false;
    final country = viewerCountryCode.trim().toLowerCase();
    if (country.isEmpty ||
        countryCodeFromUserData(otherData) != country) {
      return false;
    }
    final vk = UserSearchNormalize.normalize(viewerCity);
    final ok = UserSearchNormalize.normalize(cityNameFromUserData(otherData));
    if (vk.isEmpty || vk != ok) return false;

    final otherCoords = resolveCanonicalCoords(otherData)!;
    final d = GroupGeo.distanceKm(
      lat1: viewerLat,
      lng1: viewerLng,
      lat2: otherCoords.latitude,
      lng2: otherCoords.longitude,
    );
    return d != null && d <= sameCityMaxDistanceKm + 1e-9;
  }

  /// “Ver todos”: raio geográfico — ignora estado/província.
  static bool matchesViewerRegion({
    required Map<String, dynamic> otherData,
    required String viewerCountryCode,
    required double viewerLat,
    required double viewerLng,
    double radiusKm = regionRadiusKm,
  }) {
    if (!isDiscoverableProfile(otherData)) return false;
    if (!isValidCityCoordinate(viewerLat, viewerLng)) return false;
    final country = viewerCountryCode.trim().toLowerCase();
    if (country.isEmpty ||
        countryCodeFromUserData(otherData) != country) {
      return false;
    }
    final otherCoords = resolveCanonicalCoords(otherData)!;
    return GroupGeo.withinRegion(
      userLat: viewerLat,
      userLng: viewerLng,
      centerLat: otherCoords.latitude,
      centerLng: otherCoords.longitude,
      radiusKm: radiusKm,
    );
  }

  static String _firstNonEmpty(List<dynamic> values) {
    for (final v in values) {
      final s = (v ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static num? _asNum(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) return raw;
    return num.tryParse(raw.toString().trim());
  }

  /// Helper de teste / display: UF canônica (não usada no raio).
  static String? resolveUf(String? stateRaw) =>
      BrazilStates.resolve(stateRaw)?.uf;
}
