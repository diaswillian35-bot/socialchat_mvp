import 'group_geo.dart';
import 'group_location_normalize.dart';

/// Seletor da tela de grupos Remdy.
enum GroupDiscoveryTab { mine, city, region, country }

/// Estado visual por aba (independente).
enum GroupDiscoveryUiState {
  loading,
  list,
  empty,
  error,
  locationIncomplete,
}

/// Item de descoberta (grupo + flags de UI).
class GroupDiscoveryItem {
  const GroupDiscoveryItem({
    required this.id,
    required this.data,
    this.isMember = false,
    this.isPending = false,
  });

  final String id;
  final Map<String, dynamic> data;
  final bool isMember;
  final bool isPending;
}

class GroupCardLocation {
  const GroupCardLocation({
    required this.scope,
    required this.country,
    this.city = '',
  });

  final String scope;
  final String country;
  final String city;

  bool get showsCity => scope == 'city' && city.isNotEmpty;
  bool get showsRegionCenter => scope == 'region' && city.isNotEmpty;
  bool get countryOnly => scope == 'country';
}

/// Regras puras de descoberta (testáveis sem Firebase).
///
/// Invariantes:
/// - Meus grupos = participação confirmada
/// - Cidade/Região/País = scope canônico + geo + NÃO membro
/// - Pedido pendente NÃO é membership; permanece na aba de origem
/// - scope `unknown` (legado sem escopo confiável) NÃO entra em descoberta
class GroupDiscoveryLogic {
  GroupDiscoveryLogic._();

  static const int pageSize = 20;
  static const int overFetchMultiplier = 3;

  static String cacheKey({
    required GroupDiscoveryTab tab,
    required String uid,
    required String countryCode,
    required String cityKey,
    required num? cityLatitude,
    required num? cityLongitude,
    required int retryToken,
  }) {
    return [
      tab.name,
      uid,
      GroupLocationNormalize.countryCode(countryCode),
      cityKey,
      cityLatitude?.toStringAsFixed(5) ?? '',
      cityLongitude?.toStringAsFixed(5) ?? '',
      'r$retryToken',
    ].join('|');
  }

  static bool isParticipating({
    required Map<String, dynamic> data,
    required String uid,
  }) {
    if (uid.isEmpty) return false;
    if ((data['ownerId'] ?? '').toString() == uid) return true;
    if ((data['createdBy'] ?? '').toString() == uid) return true;

    final members = data['members'];
    if (members is List && members.map((e) => '$e').contains(uid)) {
      return true;
    }

    final admins = data['admins'];
    if (admins is List && admins.map((e) => '$e').contains(uid)) {
      return true;
    }

    final mods = data['moderators'] ?? data['mods'];
    if (mods is List && mods.map((e) => '$e').contains(uid)) {
      return true;
    }

    return false;
  }

  static bool isDeletedOrInactive(Map<String, dynamic> data) {
    if (data['deleted'] == true) return true;
    if (data['isActive'] == false) return true;
    return false;
  }

  /// Documentos sem escopo canônico confiável: fora das abas de descoberta.
  static bool isDiscoverableScope(String scope) =>
      scope == 'city' || scope == 'region' || scope == 'country';

  static bool matchesMine(Map<String, dynamic> data, String uid) {
    if (isDeletedOrInactive(data)) return false;
    return isParticipating(data: data, uid: uid);
  }

  /// País do card: sempre ISO-2, nunca o nome do Places.
  /// A UI resolve o rótulo no idioma atual via [IsoCountryNames].
  static GroupCardLocation cardLocation(Map<String, dynamic> data) {
    final scope = GroupLocationNormalize.scope(data['scope']);
    final country = GroupLocationNormalize.countryCode(
      data['countryCode'] ?? data['country'],
    );
    if (scope == 'country') {
      return GroupCardLocation(scope: scope, country: country);
    }
    if (scope == 'region') {
      return GroupCardLocation(
        scope: scope,
        country: country,
        city: (data['regionCenterCity'] ?? '').toString().trim(),
      );
    }
    return GroupCardLocation(
      scope: scope,
      country: country,
      city: GroupLocationNormalize.cityDisplayName(data),
    );
  }

  /// @Deprecated — use [IsoCountryNames.displayName] (mapa global ISO).
  static String countryL10nKey(String countryCodeOrName) {
    // Mantido só para compat transitória de testes antigos.
    switch (GroupLocationNormalize.countryCode(countryCodeOrName)) {
      case 'br':
        return 'country_brazil';
      case 'ca':
        return 'country_canada';
      case 'pt':
        return 'country_portugal';
      default:
        return '';
    }
  }

  static bool matchesCityDiscovery({
    required Map<String, dynamic> data,
    required String uid,
    required String userCountryCode,
    required String userCityKey,
  }) {
    if (isDeletedOrInactive(data)) return false;
    if (isParticipating(data: data, uid: uid)) return false;
    if (GroupLocationNormalize.scope(data['scope']) != 'city') return false;

    final gCountry = GroupLocationNormalize.countryCode(
      data['countryCode'] ?? data['country'],
    );
    final uCountry = GroupLocationNormalize.countryCode(userCountryCode);
    if (gCountry.isEmpty || uCountry.isEmpty || gCountry != uCountry) {
      return false;
    }

    final gCity = GroupLocationNormalize.cityKey(
      data['cityKey'] ?? data['city'] ?? data['cityName'],
    );
    if (userCityKey.isEmpty || gCity.isEmpty || gCity != userCityKey) {
      return false;
    }
    return true;
  }

  static bool matchesRegionDiscovery({
    required Map<String, dynamic> data,
    required String uid,
    required String userCountryCode,
    required num? userCityLatitude,
    required num? userCityLongitude,
  }) {
    if (isDeletedOrInactive(data)) return false;
    if (isParticipating(data: data, uid: uid)) return false;
    if (GroupLocationNormalize.scope(data['scope']) != 'region') return false;

    final gCountry = GroupLocationNormalize.countryCode(
      data['countryCode'] ?? data['country'],
    );
    final uCountry = GroupLocationNormalize.countryCode(userCountryCode);
    if (gCountry.isEmpty || uCountry.isEmpty || gCountry != uCountry) {
      return false;
    }

    // Região Remdy é exclusivamente radial. Nunca inferimos centro por
    // state/province/adminArea nem reutilizamos latitude residencial.
    final centerLat = _num(data['regionCenterLat']);
    final centerLng = _num(data['regionCenterLng']);
    final radius = _num(data['regionRadiusKm']);
    final centerCountry = GroupLocationNormalize.countryCode(
      data['regionCenterCountryCode'] ?? gCountry,
    );
    if (centerCountry != uCountry ||
        centerLat == null ||
        centerLng == null ||
        radius == null ||
        (radius - GroupGeo.regionRadiusKm).abs() > 1e-9) {
      return false;
    }
    return GroupGeo.withinRegion(
      userLat: userCityLatitude,
      userLng: userCityLongitude,
      centerLat: centerLat,
      centerLng: centerLng,
      radiusKm: radius,
    );
  }

  static bool matchesCountryDiscovery({
    required Map<String, dynamic> data,
    required String uid,
    required String userCountryCode,
  }) {
    if (isDeletedOrInactive(data)) return false;
    if (isParticipating(data: data, uid: uid)) return false;
    if (GroupLocationNormalize.scope(data['scope']) != 'country') return false;

    final gCountry = GroupLocationNormalize.countryCode(
      data['countryCode'] ?? data['country'],
    );
    final uCountry = GroupLocationNormalize.countryCode(userCountryCode);
    if (gCountry.isEmpty || uCountry.isEmpty || gCountry != uCountry) {
      return false;
    }
    return true;
  }

  /// Qual aba de descoberta (se alguma) exibe o grupo para um não-membro.
  /// Retorna null se membro, apagado, ou legado sem scope.
  static GroupDiscoveryTab? discoveryTabForNonMember({
    required Map<String, dynamic> data,
    required String uid,
    required String userCountryCode,
    required String userCityKey,
    required num? userCityLatitude,
    required num? userCityLongitude,
  }) {
    if (isDeletedOrInactive(data)) return null;
    if (isParticipating(data: data, uid: uid)) return GroupDiscoveryTab.mine;

    final scope = GroupLocationNormalize.scope(data['scope']);
    if (!isDiscoverableScope(scope)) return null;

    switch (scope) {
      case 'city':
        return matchesCityDiscovery(
          data: data,
          uid: uid,
          userCountryCode: userCountryCode,
          userCityKey: userCityKey,
        )
            ? GroupDiscoveryTab.city
            : null;
      case 'region':
        return matchesRegionDiscovery(
          data: data,
          uid: uid,
          userCountryCode: userCountryCode,
          userCityLatitude: userCityLatitude,
          userCityLongitude: userCityLongitude,
        )
            ? GroupDiscoveryTab.region
            : null;
      case 'country':
        return matchesCountryDiscovery(
          data: data,
          uid: uid,
          userCountryCode: userCountryCode,
        )
            ? GroupDiscoveryTab.country
            : null;
      default:
        return null;
    }
  }

  static GroupDiscoveryUiState decideState({
    required bool profileLoaded,
    required bool locationOk,
    required bool loading,
    required bool hasError,
    required bool hasItems,
  }) {
    if (!profileLoaded || loading) {
      if (hasItems) return GroupDiscoveryUiState.list;
      return GroupDiscoveryUiState.loading;
    }
    if (!locationOk) return GroupDiscoveryUiState.locationIncomplete;
    if (hasError && !hasItems) return GroupDiscoveryUiState.error;
    if (!hasItems) return GroupDiscoveryUiState.empty;
    return GroupDiscoveryUiState.list;
  }

  static String emptyMessageKey(GroupDiscoveryTab tab) {
    switch (tab) {
      case GroupDiscoveryTab.mine:
        return 'groups_empty_mine';
      case GroupDiscoveryTab.city:
        return 'groups_empty_city';
      case GroupDiscoveryTab.region:
        return 'groups_empty_region';
      case GroupDiscoveryTab.country:
        return 'groups_empty_country';
    }
  }

  static String tabLabelKey(GroupDiscoveryTab tab) {
    switch (tab) {
      case GroupDiscoveryTab.mine:
        return 'groups_tab_mine';
      case GroupDiscoveryTab.city:
        return 'groups_tab_city';
      case GroupDiscoveryTab.region:
        return 'groups_tab_region';
      case GroupDiscoveryTab.country:
        return 'groups_tab_country';
    }
  }

  static String tabSemanticsKey(GroupDiscoveryTab tab) {
    switch (tab) {
      case GroupDiscoveryTab.mine:
        return 'groups_tab_mine_a11y';
      case GroupDiscoveryTab.city:
        return 'groups_tab_city_a11y';
      case GroupDiscoveryTab.region:
        return 'groups_tab_region_a11y';
      case GroupDiscoveryTab.country:
        return 'groups_tab_country_a11y';
    }
  }

  /// Ordena por atividade recente; documentos sem `updatedAt` vão ao fim
  /// (fallback estável por `createdAt` / id).
  static int compareByRecentActivity(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final aMs = _activityMs(a);
    final bMs = _activityMs(b);
    if (aMs != bMs) return bMs.compareTo(aMs);
    final aId = (a['id'] ?? '').toString();
    final bId = (b['id'] ?? '').toString();
    return aId.compareTo(bId);
  }

  static int _activityMs(Map<String, dynamic> data) {
    for (final key in ['updatedAt', 'lastMessageAt', 'createdAt']) {
      final v = data[key];
      if (v == null) continue;
      if (v is DateTime) return v.millisecondsSinceEpoch;
      try {
        // Timestamp Firestore (duck-typed)
        final ms = (v as dynamic).millisecondsSinceEpoch;
        if (ms is int) return ms;
      } catch (_) {}
    }
    return 0;
  }

  /// Após over-fetch: filtra membership e preenche até [pageSize].
  static List<GroupDiscoveryItem> takePageAfterMembershipFilter({
    required List<GroupDiscoveryItem> candidates,
    required int pageSize,
  }) {
    final out = <GroupDiscoveryItem>[];
    for (final item in candidates) {
      if (item.isMember) continue;
      out.add(item);
      if (out.length >= pageSize) break;
    }
    return out;
  }

  static bool needsLocation(GroupDiscoveryTab tab) =>
      tab != GroupDiscoveryTab.mine;

  static bool locationComplete({
    required GroupDiscoveryTab tab,
    required String countryCode,
    required String cityKey,
    required num? cityLatitude,
    required num? cityLongitude,
  }) {
    if (tab == GroupDiscoveryTab.mine) return true;
    final cc = GroupLocationNormalize.countryCode(countryCode);
    if (cc.isEmpty) return false;
    if (tab == GroupDiscoveryTab.city) return cityKey.isNotEmpty;
    if (tab == GroupDiscoveryTab.region) {
      return GroupGeo.validCoordinates(cityLatitude, cityLongitude);
    }
    return true; // country
  }

  static double? _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString());
  }
}
