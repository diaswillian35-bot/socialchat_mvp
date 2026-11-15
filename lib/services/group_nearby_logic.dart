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

/// Ordenação da aba "Perto de você": cidade (mesma cidade ou ≤25 km) e
/// depois região (≤110 km e mesmo estado). Nacionais ficam só no chip País.
/// Cada grupo aparece uma vez só.
class GroupNearbyLogic {
  GroupNearbyLogic._();

  /// Mesma cidade por distância (bairros / sublocalidades do Places).
  static const double sameCityRadiusKm =
      UserLocationScope.sameCityMaxDistanceKm;

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

  static bool _sameCity(Map<String, dynamic> data, NearbyViewer viewer) {
    final samePlace =
        GroupDiscoveryLogic.sameSelectedPlace(data, viewer.placeId);
    final gCity = GroupLocationNormalize.discoveryCityKey(data);
    final vCity = GroupLocationNormalize.cityKey(viewer.cityKey);
    final sameKey = gCity.isNotEmpty && vCity.isNotEmpty && gCity == vCity;
    return samePlace || sameKey;
  }

  static bool _sameStateOrUndetermined(
    Map<String, dynamic> data,
    NearbyViewer viewer,
  ) {
    final cc = GroupLocationNormalize.countryCode(
      data['countryCode'] ?? data['country'] ?? viewer.countryCode,
    );
    return GroupStateCodes.sameStateOrUndetermined(
      countryCode: cc.isEmpty ? viewer.countryCode : cc,
      groupData: data,
      viewerStateCode: viewer.stateCode,
      viewerStateKey: viewer.stateKey,
    );
  }

  /// Entra na aba "Perto de você"? Cidade ou região até 110 km; não nacionais.
  static bool includedInNearby(
    Map<String, dynamic> data,
    NearbyViewer viewer,
  ) =>
      classify(data, viewer) != null;

  /// Cidade (mesma cidade ou ≤25 km) ou região (≤110 km e mesmo estado).
  /// `null` = não entra nesta aba (estado, outro estado, nacional ou longe).
  static NearbySectionKind? classify(
    Map<String, dynamic> data,
    NearbyViewer viewer,
  ) {
    final scope = GroupLocationNormalize.scope(data['scope']);
    if (scope == 'country') return null;

    if (_sameCity(data, viewer)) return NearbySectionKind.city;

    final d = distanceToViewer(data, viewer);
    if (d == null) return null;
    if (!_sameStateOrUndetermined(data, viewer)) return null;
    if (d <= sameCityRadiusKm + 1e-9) return NearbySectionKind.city;
    if (d <= regionRadiusKm + 1e-9) return NearbySectionKind.region;
    return null;
  }

  static List<NearbySection> sections({
    required List<GroupDiscoveryItem> items,
    required NearbyViewer viewer,
  }) {
    final city = <GroupDiscoveryItem>[];
    final region = <GroupDiscoveryItem>[];
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
        case NearbySectionKind.national:
        case NearbySectionKind.otherState:
        case null:
          break;
      }
    }

    int byActivity(GroupDiscoveryItem a, GroupDiscoveryItem b) =>
        GroupDiscoveryLogic.compareByRecentActivity(a.data, b.data);

    final out = <NearbySection>[];
    void add(NearbySectionKind kind, List<GroupDiscoveryItem> list) {
      if (list.isEmpty) return;
      list.sort(byActivity);
      out.add(NearbySection(kind: kind, items: list));
    }

    add(NearbySectionKind.city, city);
    add(NearbySectionKind.region, region);
    return out;
  }
}
