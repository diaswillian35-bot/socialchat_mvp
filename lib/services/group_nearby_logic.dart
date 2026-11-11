import 'group_discovery_logic.dart';
import 'group_geo.dart';
import 'group_location_normalize.dart';
import 'group_state_codes.dart';
import 'user_location_scope.dart';

/// De onde veio a localização usada para ordenar "Perto de você".
enum NearbyLocationSource { gps, profile, none }

/// Ponto de vista de quem abre a aba. As coordenadas nunca saem do aparelho:
/// com GPS ficam só na memória; sem GPS são o centro da cidade do perfil.
class NearbyViewer {
  const NearbyViewer({
    required this.countryCode,
    this.cityKey = '',
    this.placeId = '',
    this.latitude,
    this.longitude,
    this.stateCode = '',
    this.cityLabel = '',
    this.source = NearbyLocationSource.none,
  });

  final String countryCode;
  final String cityKey;
  final String placeId;
  final double? latitude;
  final double? longitude;
  final String stateCode;
  final String cityLabel;
  final NearbyLocationSource source;

  String get stateKey => GroupStateCodes.stateKey(countryCode, stateCode);

  bool get hasPoint => GroupGeo.trustedCityCenter(latitude, longitude);
}

enum NearbySectionKind { city, region, state, national, otherState }

class NearbySection {
  const NearbySection({
    required this.kind,
    required this.items,
    this.stateCode = '',
    this.stateKey = '',
    this.stateLabel = '',
  });

  final NearbySectionKind kind;
  final List<GroupDiscoveryItem> items;
  final String stateCode;
  final String stateKey;

  /// Nome do estado como veio no grupo (fallback de título).
  final String stateLabel;
}

/// Ordenação da aba "Perto de você": cidade > região (110 km) > estado >
/// grupos nacionais > outros estados (um bloco por estado, do mais perto ao
/// mais longe). Cada grupo aparece uma vez só.
class GroupNearbyLogic {
  GroupNearbyLogic._();

  /// Mesma cidade por distância (bairros / sublocalidades do Places).
  static const double sameCityRadiusKm = UserLocationScope.sameCityMaxDistanceKm;

  /// Região Remdy (pessoas, eventos e grupos).
  static const double regionRadiusKm = GroupGeo.regionRadiusKm;

  /// Visível nesta aba para quem olha? Membros também aparecem ("Abrir").
  static bool eligible({
    required Map<String, dynamic> data,
    required String uid,
    required String viewerCountryCode,
  }) {
    if (GroupDiscoveryLogic.isDeletedOrInactive(data)) return false;
    if (GroupDiscoveryLogic.isOptedOutOfDiscovery(data)) return false;
    if (GroupDiscoveryLogic.isConcealedFromViewer(data, uid)) return false;
    final scope = GroupLocationNormalize.scope(data['scope']);
    if (!GroupDiscoveryLogic.isDiscoverableScope(scope)) return false;
    final g = GroupLocationNormalize.countryCode(
      data['countryCode'] ?? data['country'],
    );
    final v = GroupLocationNormalize.countryCode(viewerCountryCode);
    return g.isNotEmpty && v.isNotEmpty && g == v;
  }

  static double? distanceToViewer(
    Map<String, dynamic> data,
    NearbyViewer viewer,
  ) {
    if (!viewer.hasPoint) return null;
    final c = GroupDiscoveryLogic.trustedPlaceCoordinates(data);
    if (c == null) return null;
    return GroupGeo.distanceKm(
      lat1: viewer.latitude,
      lng1: viewer.longitude,
      lat2: c.latitude,
      lng2: c.longitude,
    );
  }

  static NearbySectionKind classify(
    Map<String, dynamic> data,
    NearbyViewer viewer,
  ) {
    final scope = GroupLocationNormalize.scope(data['scope']);
    if (scope == 'country') return NearbySectionKind.national;

    final d = distanceToViewer(data, viewer);
    if (scope == 'city') {
      final samePlace =
          GroupDiscoveryLogic.sameSelectedPlace(data, viewer.placeId);
      final gCity = GroupLocationNormalize.discoveryCityKey(data);
      final vCity = GroupLocationNormalize.cityKey(viewer.cityKey);
      final sameKey = gCity.isNotEmpty && vCity.isNotEmpty && gCity == vCity;
      final close = d != null && d <= sameCityRadiusKm + 1e-9;
      if (samePlace || sameKey || close) return NearbySectionKind.city;
    }

    if (d != null) {
      var radius = regionRadiusKm;
      if (scope == 'region') {
        final r = data['regionRadiusKm'];
        if (r is num && r.isFinite && r > 0) radius = r.toDouble();
      }
      if (d <= radius + 1e-9) return NearbySectionKind.region;
    }

    final cc = GroupLocationNormalize.countryCode(
      data['countryCode'] ?? data['country'],
    );
    final gState = GroupStateCodes.groupStateKey(data, cc);
    if (gState.isNotEmpty && gState == viewer.stateKey) {
      return NearbySectionKind.state;
    }
    return NearbySectionKind.otherState;
  }

  static List<NearbySection> sections({
    required List<GroupDiscoveryItem> items,
    required NearbyViewer viewer,
  }) {
    final city = <GroupDiscoveryItem>[];
    final region = <GroupDiscoveryItem>[];
    final state = <GroupDiscoveryItem>[];
    final national = <GroupDiscoveryItem>[];
    final others = <String, List<GroupDiscoveryItem>>{};
    final otherCode = <String, String>{};
    final otherLabel = <String, String>{};
    final otherMinKm = <String, double>{};
    final seen = <String>{};

    for (final item in items) {
      if (!seen.add(item.id)) continue;
      switch (classify(item.data, viewer)) {
        case NearbySectionKind.city:
          city.add(item);
          break;
        case NearbySectionKind.region:
          region.add(item);
          break;
        case NearbySectionKind.state:
          state.add(item);
          break;
        case NearbySectionKind.national:
          national.add(item);
          break;
        case NearbySectionKind.otherState:
          final cc = GroupLocationNormalize.countryCode(
            item.data['countryCode'] ?? item.data['country'],
          );
          final key = GroupStateCodes.groupStateKey(item.data, cc);
          others.putIfAbsent(key, () => []).add(item);
          otherCode.putIfAbsent(
            key,
            () => key.contains('-') ? key.split('-').last.toUpperCase() : '',
          );
          otherLabel.putIfAbsent(
            key,
            () => (item.data['stateName'] ?? '').toString().trim(),
          );
          final d = distanceToViewer(item.data, viewer);
          if (d != null) {
            final prev = otherMinKm[key];
            if (prev == null || d < prev) otherMinKm[key] = d;
          }
          break;
      }
    }

    int byActivity(GroupDiscoveryItem a, GroupDiscoveryItem b) =>
        GroupDiscoveryLogic.compareByRecentActivity(a.data, b.data);

    final out = <NearbySection>[];
    void add(NearbySectionKind kind, List<GroupDiscoveryItem> list) {
      if (list.isEmpty) return;
      list.sort(byActivity);
      out.add(NearbySection(
        kind: kind,
        items: list,
        stateCode: kind == NearbySectionKind.state ? viewer.stateCode : '',
        stateKey: kind == NearbySectionKind.state ? viewer.stateKey : '',
      ));
    }

    add(NearbySectionKind.city, city);
    add(NearbySectionKind.region, region);
    add(NearbySectionKind.state, state);
    add(NearbySectionKind.national, national);

    final keys = others.keys.toList()
      ..sort((a, b) {
        // Sem estado conhecido vai por último.
        if (a.isEmpty != b.isEmpty) return a.isEmpty ? 1 : -1;
        final da = otherMinKm[a];
        final db = otherMinKm[b];
        if (da != null && db != null && da != db) return da.compareTo(db);
        if (da != null && db == null) return -1;
        if (da == null && db != null) return 1;
        return a.compareTo(b);
      });
    for (final key in keys) {
      final list = others[key]!..sort(byActivity);
      out.add(NearbySection(
        kind: NearbySectionKind.otherState,
        items: list,
        stateCode: otherCode[key] ?? '',
        stateKey: key,
        stateLabel: otherLabel[key] ?? '',
      ));
    }
    return out;
  }
}
