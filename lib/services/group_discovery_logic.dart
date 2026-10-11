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
class GroupListFetchResult {
  const GroupListFetchResult({
    required this.loading,
    required this.loadedOnce,
    required this.applyRemotePage,
    required this.showError,
  });

  final bool loading;
  final bool loadedOnce;
  final bool applyRemotePage;
  final bool showError;
}

class GroupDiscoveryLogic {
  GroupDiscoveryLogic._();

  static const int pageSize = 20;
  static const int overFetchMultiplier = 3;

  /// Teto da consulta de grupos de cidade candidatos à aba Região.
  /// Usa o índice já existente `deleted + countryCode + scope + updatedAt`.
  /// A distância de [GroupGeo.nearbyCityRadiusKm] é aplicada depois, no cliente.
  static const int nearbyCityQueryLimit = 40;

  static String cacheKey({
    required GroupDiscoveryTab tab,
    required String uid,
    required String countryCode,
    required String cityKey,
    String placeId = '',
    required num? cityLatitude,
    required num? cityLongitude,
    required int retryToken,
  }) {
    return [
      tab.name,
      uid,
      GroupLocationNormalize.countryCode(countryCode),
      cityKey,
      placeId,
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

  static bool isPrivateGroup(Map<String, dynamic> data) =>
      data['isPrivate'] == true;

  /// Opt-out explícito de descoberta (campo futuro / admin).
  /// Valores: `discoverable: false` ou `hiddenFromDiscovery: true`.
  static bool isOptedOutOfDiscovery(Map<String, dynamic> data) {
    if (data['hiddenFromDiscovery'] == true) return true;
    if (data['discoverable'] == false) return true;
    return false;
  }

  /// Oculto para esta pessoa (`hiddenFor`) ou bloqueio registrado no grupo.
  static bool isConcealedFromViewer(Map<String, dynamic> data, String uid) {
    if (uid.isEmpty) return false;
    for (final key in ['hiddenFor', 'blocked', 'blockedUsers']) {
      final raw = data[key];
      if (raw is List && raw.map((e) => '$e').contains(uid)) return true;
    }
    return false;
  }

  /// Latitude/longitude canônicas do lugar. Não usa texto de cidade nem GPS.
  static GroupLatLng? trustedPlaceCoordinates(
    Map<String, dynamic> data,
  ) {
    final scope = GroupLocationNormalize.scope(data['scope']);
    final num? lat;
    final num? lng;
    if (scope == 'region') {
      lat = _num(data['regionCenterLat']) ?? _num(data['latitude']);
      lng = _num(data['regionCenterLng']) ?? _num(data['longitude']);
    } else if (scope == 'city') {
      lat = _num(data['latitude']);
      lng = _num(data['longitude']);
    } else {
      return null;
    }
    if (!GroupGeo.trustedCityCenter(lat, lng)) return null;
    return GroupLatLng(lat!.toDouble(), lng!.toDouble());
  }

  /// Documentos sem escopo canônico confiável: fora das abas de descoberta.
  static bool isDiscoverableScope(String scope) =>
      scope == 'city' || scope == 'region' || scope == 'country';

  static bool matchesMine(Map<String, dynamic> data, String uid) {
    if (isDeletedOrInactive(data)) return false;
    return isParticipating(data: data, uid: uid);
  }

  /// Remove grupos ocultos pelo usuário (preferência pessoal).
  /// Applies a membership snapshot onto the already loaded "mine" list.
  /// Does not clear unread, does not drop hidden ids, and does not mark read.
  static List<GroupDiscoveryItem> mergeUnreadSnapshot({
    required List<GroupDiscoveryItem> items,
    required Map<String, Map<String, dynamic>> updates,
  }) {
    final next = <GroupDiscoveryItem>[];
    final seen = <String>{};
    for (final item in items) {
      final incoming = updates[item.id];
      if (incoming == null) {
        next.add(item);
        continue;
      }
      seen.add(item.id);
      next.add(
        GroupDiscoveryItem(
          id: item.id,
          data: incoming,
          isMember: true,
          isPending: item.isPending,
        ),
      );
    }
    for (final entry in updates.entries) {
      if (seen.contains(entry.key)) continue;
      next.insert(
        0,
        GroupDiscoveryItem(
          id: entry.key,
          data: entry.value,
          isMember: true,
        ),
      );
    }
    return next;
  }

  static bool unreadSurfaceChanged({
    required List<GroupDiscoveryItem> before,
    required List<GroupDiscoveryItem> after,
    required String uid,
  }) {
    if (before.length != after.length) return true;
    for (var i = 0; i < before.length; i++) {
      if (before[i].id != after[i].id) return true;
      final previous = before[i].data['unread'];
      final incoming = after[i].data['unread'];
      if (previous.toString() != incoming.toString()) return true;
      if (before[i].data['unread.$uid'] != after[i].data['unread.$uid']) {
        return true;
      }
    }
    return false;
  }

  static const catalogFields = <String>[
    'name',
    'bio',
    'avatarUrl',
    'city',
    'cityName',
    'displayLocation',
    'cityKey',
    'scope',
    'stateName',
  ];

  /// Membership, city, name, bio and cover — not only the unread counters.
  static bool listSurfaceChanged({
    required List<GroupDiscoveryItem> before,
    required List<GroupDiscoveryItem> after,
    required String uid,
  }) {
    if (unreadSurfaceChanged(before: before, after: after, uid: uid)) {
      return true;
    }
    if (before.length != after.length) return true;
    for (var i = 0; i < before.length; i++) {
      for (final key in catalogFields) {
        if (before[i].data[key]?.toString() != after[i].data[key]?.toString()) {
          return true;
        }
      }
    }
    return false;
  }

  /// Full membership query result. Groups the user joined or created appear
  /// even when their city does not match the profile city.
  static List<GroupDiscoveryItem> replaceMembershipSnapshot({
    required List<GroupDiscoveryItem> previous,
    required Map<String, Map<String, dynamic>> updates,
  }) {
    final pending = <String, bool>{
      for (final item in previous) item.id: item.isPending,
    };
    final next = <GroupDiscoveryItem>[];
    for (final entry in updates.entries) {
      if (isDeletedOrInactive(entry.value)) continue;
      next.add(
        GroupDiscoveryItem(
          id: entry.key,
          data: entry.value,
          isMember: true,
          isPending: pending[entry.key] ?? false,
        ),
      );
    }
    next.sort(
      (a, b) => compareByRecentActivity(a.data, b.data),
    );
    return next;
  }

  /// Discovery page for someone who is not a member. Members stay on Mine.
  static List<GroupDiscoveryItem> visibleDiscoveryFromDocs({
    required List<Map<String, dynamic>> docs,
    required GroupDiscoveryTab tab,
    required String uid,
    required String userCountryCode,
    required String userCityKey,
    String userPlaceId = '',
    required num? userCityLatitude,
    required num? userCityLongitude,
    required Set<String> pendingIds,
  }) {
    final out = <GroupDiscoveryItem>[];
    for (final data in docs) {
      if (isDeletedOrInactive(data)) continue;
      if (isConcealedFromViewer(data, uid)) continue;
      if (isParticipating(data: data, uid: uid)) continue;
      final where = discoveryTabForNonMember(
        data: data,
        uid: uid,
        userCountryCode: userCountryCode,
        userCityKey: userCityKey,
        userPlaceId: userPlaceId,
        userCityLatitude: userCityLatitude,
        userCityLongitude: userCityLongitude,
      );
      if (where != tab) continue;
      final id = (data['id'] ?? '').toString();
      if (id.isEmpty) continue;
      out.add(
        GroupDiscoveryItem(
          id: id,
          data: data,
          isPending: pendingIds.contains(id),
        ),
      );
    }
    out.sort((a, b) => compareByRecentActivity(a.data, b.data));
    return out;
  }

  static List<GroupDiscoveryItem> excludeHidden({
    required List<GroupDiscoveryItem> items,
    required Set<String> hiddenIds,
  }) {
    if (hiddenIds.isEmpty) return items;
    return items.where((e) => !hiddenIds.contains(e.id)).toList();
  }

  /// Card de descoberta para privado não-membro: só metadados públicos mínimos.
  static bool shouldShowLockedPrivateDiscoveryCard({
    required Map<String, dynamic> data,
    required bool isMember,
  }) {
    if (isMember) return false;
    return isPrivateGroup(data);
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
      final stored = (data['regionCenterCity'] ?? '').toString().trim();
      return GroupCardLocation(
        scope: scope,
        country: country,
        city: GroupLocationNormalize.selectedPlaceLabel(data, stored: stored),
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

  static bool sameSelectedPlace(Map<String, dynamic> data, String userPlaceId) {
    final groupPlace = (data['placeId'] ?? '').toString().trim();
    final userPlace = userPlaceId.trim();
    return groupPlace.isNotEmpty &&
        userPlace.isNotEmpty &&
        groupPlace == userPlace;
  }

  static bool matchesCityDiscovery({
    required Map<String, dynamic> data,
    required String uid,
    required String userCountryCode,
    required String userCityKey,
    String userPlaceId = '',
  }) {
    if (isDeletedOrInactive(data)) return false;
    if (isOptedOutOfDiscovery(data)) return false;
    if (isConcealedFromViewer(data, uid)) return false;
    if (isParticipating(data: data, uid: uid)) return false;
    if (GroupLocationNormalize.scope(data['scope']) != 'city') return false;

    final gCountry = GroupLocationNormalize.countryCode(
      data['countryCode'] ?? data['country'],
    );
    final uCountry = GroupLocationNormalize.countryCode(userCountryCode);
    if (gCountry.isEmpty || uCountry.isEmpty || gCountry != uCountry) {
      return false;
    }

    if (sameSelectedPlace(data, userPlaceId)) return true;

    final gCity = GroupLocationNormalize.discoveryCityKey(data);
    final uCity = GroupLocationNormalize.cityKey(userCityKey);
    if (uCity.isEmpty || gCity.isEmpty || gCity != uCity) return false;
    return true;
  }

  /// Cidade de outro cityKey, perto o bastante para a aba Região.
  /// Sem coordenadas confiáveis o grupo não aparece — não há fallback por nome.
  static bool matchesNearbyCityDiscovery({
    required Map<String, dynamic> data,
    required String uid,
    required String userCountryCode,
    required String userCityKey,
    String userPlaceId = '',
    required num? userCityLatitude,
    required num? userCityLongitude,
  }) {
    if (matchesCityDiscovery(
      data: data,
      uid: uid,
      userCountryCode: userCountryCode,
      userCityKey: userCityKey,
      userPlaceId: userPlaceId,
    )) {
      return false;
    }
    if (isDeletedOrInactive(data)) return false;
    if (isOptedOutOfDiscovery(data)) return false;
    if (isConcealedFromViewer(data, uid)) return false;
    if (isParticipating(data: data, uid: uid)) return false;
    if (GroupLocationNormalize.scope(data['scope']) != 'city') return false;

    final gCountry = GroupLocationNormalize.countryCode(
      data['countryCode'] ?? data['country'],
    );
    final uCountry = GroupLocationNormalize.countryCode(userCountryCode);
    if (gCountry.isEmpty || uCountry.isEmpty || gCountry != uCountry) {
      return false;
    }

    final place = trustedPlaceCoordinates(data);
    if (place == null ||
        !GroupGeo.trustedCityCenter(userCityLatitude, userCityLongitude)) {
      return false;
    }
    return GroupGeo.withinRegion(
      userLat: userCityLatitude,
      userLng: userCityLongitude,
      centerLat: place.latitude,
      centerLng: place.longitude,
      radiusKm: GroupGeo.nearbyCityRadiusKm,
    );
  }

  static bool matchesRegionDiscovery({
    required Map<String, dynamic> data,
    required String uid,
    required String userCountryCode,
    required num? userCityLatitude,
    required num? userCityLongitude,
  }) {
    if (isDeletedOrInactive(data)) return false;
    if (isOptedOutOfDiscovery(data)) return false;
    if (isConcealedFromViewer(data, uid)) return false;
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

  /// Aba Região: documento regional no raio de 110 km, ou cidade dentro de 50 km.
  static bool matchesRegionTab({
    required Map<String, dynamic> data,
    required String uid,
    required String userCountryCode,
    required String userCityKey,
    String userPlaceId = '',
    required num? userCityLatitude,
    required num? userCityLongitude,
  }) {
    final scope = GroupLocationNormalize.scope(data['scope']);
    if (scope == 'region') {
      return matchesRegionDiscovery(
        data: data,
        uid: uid,
        userCountryCode: userCountryCode,
        userCityLatitude: userCityLatitude,
        userCityLongitude: userCityLongitude,
      );
    }
    if (scope == 'city') {
      return matchesNearbyCityDiscovery(
        data: data,
        uid: uid,
        userCountryCode: userCountryCode,
        userCityKey: userCityKey,
        userPlaceId: userPlaceId,
        userCityLatitude: userCityLatitude,
        userCityLongitude: userCityLongitude,
      );
    }
    return false;
  }

  /// Une candidatos regionais e de cidade sem duplicar id. Ordena por atividade.
  static List<GroupDiscoveryItem> combineRegionTabItems({
    required List<GroupDiscoveryItem> regional,
    required List<GroupDiscoveryItem> nearbyCities,
    int limit = pageSize,
  }) {
    final byId = <String, GroupDiscoveryItem>{};
    for (final item in [...regional, ...nearbyCities]) {
      byId.putIfAbsent(item.id, () => item);
    }
    final items = byId.values.toList()
      ..sort((a, b) => compareByRecentActivity(a.data, b.data));
    if (limit < 1) return items;
    return items.take(limit).toList();
  }

  static bool matchesCountryDiscovery({
    required Map<String, dynamic> data,
    required String uid,
    required String userCountryCode,
  }) {
    if (isDeletedOrInactive(data)) return false;
    if (isOptedOutOfDiscovery(data)) return false;
    if (isConcealedFromViewer(data, uid)) return false;
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
    String userPlaceId = '',
    required num? userCityLatitude,
    required num? userCityLongitude,
  }) {
    if (isDeletedOrInactive(data)) return null;
    if (isParticipating(data: data, uid: uid)) return GroupDiscoveryTab.mine;

    final scope = GroupLocationNormalize.scope(data['scope']);
    if (!isDiscoverableScope(scope)) return null;

    switch (scope) {
      case 'city':
        if (matchesCityDiscovery(
          data: data,
          uid: uid,
          userCountryCode: userCountryCode,
          userCityKey: userCityKey,
          userPlaceId: userPlaceId,
        )) {
          return GroupDiscoveryTab.city;
        }
        return matchesNearbyCityDiscovery(
          data: data,
          uid: uid,
          userCountryCode: userCountryCode,
          userCityKey: userCityKey,
          userPlaceId: userPlaceId,
          userCityLatitude: userCityLatitude,
          userCityLongitude: userCityLongitude,
        )
            ? GroupDiscoveryTab.region
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

  /// How a one-shot fetch finishes once a live snapshot may already have
  /// delivered the tab. A discarded fetch must never leave the spinner up,
  /// and a failed query must not throw away groups already on screen.
  static GroupListFetchResult completeListFetch({
    required bool liveSeen,
    required bool failed,
    required bool hasItems,
  }) {
    if (liveSeen) {
      return const GroupListFetchResult(
        loading: false,
        loadedOnce: true,
        applyRemotePage: false,
        showError: false,
      );
    }
    if (failed) {
      return GroupListFetchResult(
        loading: false,
        loadedOnce: true,
        applyRemotePage: false,
        showError: !hasItems,
      );
    }
    return const GroupListFetchResult(
      loading: false,
      loadedOnce: true,
      applyRemotePage: true,
      showError: false,
    );
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
