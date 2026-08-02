import 'package:cloud_firestore/cloud_firestore.dart';

import 'group_discovery_logic.dart';
import 'group_geo.dart';
import 'group_location_normalize.dart';

/// Cursor de paginação determinístico.
///
/// - Abas simples (cidade/país/meus): [document] = último doc da query ordenada
///   por `updatedAt` desc.
/// - Região com múltiplos lotes geohash: [batchDocuments] guarda o cursor de
///   cada lote `whereIn`; [seenIds] evita duplicatas entre lotes/rodadas.
class GroupDiscoveryCursor {
  const GroupDiscoveryCursor({
    this.document,
    this.batchDocuments = const {},
    this.seenIds = const {},
    this.batchExhausted = const {},
  });

  final DocumentSnapshot<Map<String, dynamic>>? document;
  final Map<int, DocumentSnapshot<Map<String, dynamic>>> batchDocuments;
  final Set<String> seenIds;
  final Map<int, bool> batchExhausted;

  bool get isEmpty =>
      document == null && batchDocuments.isEmpty && seenIds.isEmpty;
}

/// Resultado paginado de uma aba de descoberta.
class GroupDiscoveryPage {
  const GroupDiscoveryPage({
    required this.items,
    required this.hasMore,
    this.cursor,
  });

  final List<GroupDiscoveryItem> items;
  final bool hasMore;
  final GroupDiscoveryCursor? cursor;

  /// Compat: último documento da query simples.
  DocumentSnapshot<Map<String, dynamic>>? get lastDocument => cursor?.document;
}

/// Consultas limitadas/paginadas por aba — sem scan mundial.
///
/// Membership é excluída no cliente após consulta já limitada geograficamente
/// (Firestore não tem `array-not-contains`). Over-fetch controlado; a Região
/// continua buscando até encher a página ou atingir o orçamento de leituras.
class GroupDiscoveryService {
  GroupDiscoveryService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  /// Orçamento máximo de documentos lidos por chamada de página (custo).
  static const int maxDocsPerPageRequest = 300;

  /// Rodadas extras quando muitos candidatos caem fora do Haversine.
  static const int maxContinueRounds = 6;

  CollectionReference<Map<String, dynamic>> get _groups =>
      _db.collection('groups');

  Future<Set<String>> loadPendingGroupIds(String uid) async {
    if (uid.isEmpty) return {};
    try {
      final snap = await _db
          .collectionGroup('pendingRequests')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .limit(100)
          .get();
      final ids = <String>{};
      for (final doc in snap.docs) {
        final parent = doc.reference.parent.parent;
        if (parent != null) ids.add(parent.id);
      }
      return ids;
    } catch (_) {
      return {};
    }
  }

  Future<GroupDiscoveryPage> fetchMine({
    required String uid,
    GroupDiscoveryCursor? startAfter,
    int pageSize = GroupDiscoveryLogic.pageSize,
  }) async {
    Query<Map<String, dynamic>> q = _groups
        .where('members', arrayContains: uid)
        .where('deleted', isEqualTo: false)
        .orderBy('updatedAt', descending: true)
        .limit(pageSize);

    final after = startAfter?.document;
    if (after != null) q = q.startAfterDocument(after);

    try {
      final snap = await q.get();
      final items = <GroupDiscoveryItem>[];
      for (final doc in snap.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['id'] = doc.id;
        if (GroupDiscoveryLogic.isDeletedOrInactive(data)) continue;
        if (!GroupDiscoveryLogic.matchesMine(data, uid)) continue;
        items.add(GroupDiscoveryItem(id: doc.id, data: data, isMember: true));
      }
      items.sort(
        (a, b) => GroupDiscoveryLogic.compareByRecentActivity(a.data, b.data),
      );
      return GroupDiscoveryPage(
        items: items,
        hasMore: snap.docs.length >= pageSize,
        cursor: GroupDiscoveryCursor(
          document: snap.docs.isEmpty ? null : snap.docs.last,
        ),
      );
    } on FirebaseException catch (e) {
      if (e.code == 'failed-precondition' || e.code == 'invalid-argument') {
        return _fetchMineFallback(uid: uid, pageSize: pageSize);
      }
      rethrow;
    }
  }

  Future<GroupDiscoveryPage> _fetchMineFallback({
    required String uid,
    required int pageSize,
  }) async {
    final snap = await _groups
        .where('members', arrayContains: uid)
        .limit(pageSize * 2)
        .get();
    final items = <GroupDiscoveryItem>[];
    for (final doc in snap.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['id'] = doc.id;
      if (!GroupDiscoveryLogic.matchesMine(data, uid)) continue;
      items.add(GroupDiscoveryItem(id: doc.id, data: data, isMember: true));
    }
    items.sort(
      (a, b) => GroupDiscoveryLogic.compareByRecentActivity(a.data, b.data),
    );
    final page = items.take(pageSize).toList();
    return GroupDiscoveryPage(
      items: page,
      hasMore: items.length > pageSize,
      cursor: null,
    );
  }

  Future<GroupDiscoveryPage> fetchDiscovery({
    required GroupDiscoveryTab tab,
    required String uid,
    required String countryCode,
    required String cityKey,
    required num? userCityLatitude,
    required num? userCityLongitude,
    required Set<String> pendingIds,
    GroupDiscoveryCursor? startAfter,
    int pageSize = GroupDiscoveryLogic.pageSize,
  }) async {
    assert(tab != GroupDiscoveryTab.mine);

    final code = GroupLocationNormalize.countryCode(countryCode);
    late final String scope;
    switch (tab) {
      case GroupDiscoveryTab.city:
        scope = 'city';
        break;
      case GroupDiscoveryTab.region:
        scope = 'region';
        break;
      case GroupDiscoveryTab.country:
        scope = 'country';
        break;
      case GroupDiscoveryTab.mine:
        throw StateError('use fetchMine');
    }

    if (tab == GroupDiscoveryTab.region) {
      return _fetchRegionDiscovery(
        uid: uid,
        countryCode: code,
        userCityLatitude: userCityLatitude,
        userCityLongitude: userCityLongitude,
        pendingIds: pendingIds,
        startAfter: startAfter,
        pageSize: pageSize,
      );
    }

    return _fetchScopedDiscovery(
      tab: tab,
      scope: scope,
      uid: uid,
      countryCode: code,
      cityKey: cityKey,
      userCityLatitude: userCityLatitude,
      userCityLongitude: userCityLongitude,
      pendingIds: pendingIds,
      startAfter: startAfter,
      pageSize: pageSize,
    );
  }

  Future<GroupDiscoveryPage> _fetchScopedDiscovery({
    required GroupDiscoveryTab tab,
    required String scope,
    required String uid,
    required String countryCode,
    required String cityKey,
    required num? userCityLatitude,
    required num? userCityLongitude,
    required Set<String> pendingIds,
    GroupDiscoveryCursor? startAfter,
    required int pageSize,
  }) async {
    final perFetch = pageSize * GroupDiscoveryLogic.overFetchMultiplier;
    final visible = <GroupDiscoveryItem>[];
    var cursorDoc = startAfter?.document;
    var docsRead = 0;
    var hasMore = true;
    var rounds = 0;

    while (visible.length < pageSize &&
        hasMore &&
        rounds < maxContinueRounds &&
        docsRead < maxDocsPerPageRequest) {
      rounds++;
      final remainingBudget = maxDocsPerPageRequest - docsRead;
      final limit = remainingBudget < perFetch ? remainingBudget : perFetch;
      if (limit <= 0) break;

      Query<Map<String, dynamic>> q = _groups
          .where('deleted', isEqualTo: false)
          .where('countryCode', isEqualTo: countryCode)
          .where('scope', isEqualTo: scope);

      if (tab == GroupDiscoveryTab.city && cityKey.isNotEmpty) {
        q = q.where('cityKey', isEqualTo: cityKey);
      }

      q = q.orderBy('updatedAt', descending: true).limit(limit);
      if (cursorDoc != null) q = q.startAfterDocument(cursorDoc);

      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        snap = await q.get();
      } on FirebaseException catch (e) {
        if (e.code == 'failed-precondition' || e.code == 'invalid-argument') {
          Query<Map<String, dynamic>> fallback = _groups
              .where('deleted', isEqualTo: false)
              .where('countryCode', isEqualTo: countryCode)
              .where('scope', isEqualTo: scope)
              .limit(limit);
          if (cursorDoc != null) {
            fallback = fallback.startAfterDocument(cursorDoc);
          }
          snap = await fallback.get();
        } else {
          rethrow;
        }
      }

      docsRead += snap.docs.length;
      if (snap.docs.isEmpty) {
        hasMore = false;
        break;
      }
      cursorDoc = snap.docs.last;
      hasMore = snap.docs.length >= limit;

      for (final doc in snap.docs) {
        final item = _toDiscoveryItem(
          doc: doc,
          tab: tab,
          uid: uid,
          countryCode: countryCode,
          cityKey: cityKey,
          userCityLatitude: userCityLatitude,
          userCityLongitude: userCityLongitude,
          pendingIds: pendingIds,
        );
        if (item == null || item.isMember) continue;
        visible.add(item);
        if (visible.length >= pageSize) break;
      }
    }

    return GroupDiscoveryPage(
      items: visible.take(pageSize).toList(),
      hasMore: hasMore,
      cursor: GroupDiscoveryCursor(document: cursorDoc),
    );
  }

  Future<GroupDiscoveryPage> _fetchRegionDiscovery({
    required String uid,
    required String countryCode,
    required num? userCityLatitude,
    required num? userCityLongitude,
    required Set<String> pendingIds,
    GroupDiscoveryCursor? startAfter,
    required int pageSize,
  }) async {
    final batches = GroupGeo.geohashBatches(
      latitude: userCityLatitude,
      longitude: userCityLongitude,
    );

    // Sem células (coords inválidas): fallback país+scope com continue.
    if (batches.isEmpty) {
      return _fetchScopedDiscovery(
        tab: GroupDiscoveryTab.region,
        scope: 'region',
        uid: uid,
        countryCode: countryCode,
        cityKey: '',
        userCityLatitude: userCityLatitude,
        userCityLongitude: userCityLongitude,
        pendingIds: pendingIds,
        startAfter: startAfter,
        pageSize: pageSize,
      );
    }

    final batchCursors = Map<int, DocumentSnapshot<Map<String, dynamic>>>.from(
      startAfter?.batchDocuments ?? const {},
    );
    final exhausted = Map<int, bool>.from(startAfter?.batchExhausted ?? const {});
    final seen = Set<String>.from(startAfter?.seenIds ?? const {});
    final visible = <GroupDiscoveryItem>[];
    var docsRead = 0;
    var rounds = 0;
    final perBatchLimit = pageSize * GroupDiscoveryLogic.overFetchMultiplier;

    bool anyBatchHasMore() {
      for (var i = 0; i < batches.length; i++) {
        if (exhausted[i] != true) return true;
      }
      return false;
    }

    while (visible.length < pageSize &&
        anyBatchHasMore() &&
        rounds < maxContinueRounds &&
        docsRead < maxDocsPerPageRequest) {
      rounds++;
      final roundDocs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];

      for (var i = 0; i < batches.length; i++) {
        if (exhausted[i] == true) continue;
        if (docsRead >= maxDocsPerPageRequest) break;
        final remainingBudget = maxDocsPerPageRequest - docsRead;
        final limit =
            remainingBudget < perBatchLimit ? remainingBudget : perBatchLimit;
        if (limit <= 0) break;

        Query<Map<String, dynamic>> q = _groups
            .where('deleted', isEqualTo: false)
            .where('countryCode', isEqualTo: countryCode)
            .where('scope', isEqualTo: 'region')
            .where('regionCenterGeohash', whereIn: batches[i])
            .orderBy('updatedAt', descending: true)
            .limit(limit);

        final after = batchCursors[i];
        if (after != null) q = q.startAfterDocument(after);

        QuerySnapshot<Map<String, dynamic>> snap;
        try {
          snap = await q.get();
        } on FirebaseException catch (e) {
          if (e.code == 'failed-precondition' || e.code == 'invalid-argument') {
            // Índice ausente: uma rodada de fallback país+scope basta.
            return _fetchScopedDiscovery(
              tab: GroupDiscoveryTab.region,
              scope: 'region',
              uid: uid,
              countryCode: countryCode,
              cityKey: '',
              userCityLatitude: userCityLatitude,
              userCityLongitude: userCityLongitude,
              pendingIds: pendingIds,
              startAfter: startAfter,
              pageSize: pageSize,
            );
          }
          rethrow;
        }

        docsRead += snap.docs.length;
        if (snap.docs.isEmpty || snap.docs.length < limit) {
          exhausted[i] = true;
        }
        if (snap.docs.isNotEmpty) {
          batchCursors[i] = snap.docs.last;
          roundDocs.addAll(snap.docs);
        } else {
          exhausted[i] = true;
        }
      }

      // Une lotes, deduplica e ordena por updatedAt desc (campo canônico).
      final byId = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final doc in roundDocs) {
        byId.putIfAbsent(doc.id, () => doc);
      }
      final merged = byId.values.toList()
        ..sort((a, b) {
          final aData = Map<String, dynamic>.from(a.data())..['id'] = a.id;
          final bData = Map<String, dynamic>.from(b.data())..['id'] = b.id;
          return GroupDiscoveryLogic.compareByRecentActivity(aData, bData);
        });

      for (final doc in merged) {
        if (seen.contains(doc.id)) continue;
        seen.add(doc.id);
        final item = _toDiscoveryItem(
          doc: doc,
          tab: GroupDiscoveryTab.region,
          uid: uid,
          countryCode: countryCode,
          cityKey: '',
          userCityLatitude: userCityLatitude,
          userCityLongitude: userCityLongitude,
          pendingIds: pendingIds,
        );
        if (item == null || item.isMember) continue;
        visible.add(item);
        if (visible.length >= pageSize) break;
      }
    }

    return GroupDiscoveryPage(
      items: visible.take(pageSize).toList(),
      hasMore: anyBatchHasMore(),
      cursor: GroupDiscoveryCursor(
        batchDocuments: batchCursors,
        batchExhausted: exhausted,
        seenIds: seen,
      ),
    );
  }

  GroupDiscoveryItem? _toDiscoveryItem({
    required QueryDocumentSnapshot<Map<String, dynamic>> doc,
    required GroupDiscoveryTab tab,
    required String uid,
    required String countryCode,
    required String cityKey,
    required num? userCityLatitude,
    required num? userCityLongitude,
    required Set<String> pendingIds,
  }) {
    final data = Map<String, dynamic>.from(doc.data());
    data['id'] = doc.id;

    final isMember = GroupDiscoveryLogic.isParticipating(
      data: data,
      uid: uid,
    );

    bool matches = false;
    switch (tab) {
      case GroupDiscoveryTab.city:
        matches = GroupDiscoveryLogic.matchesCityDiscovery(
          data: data,
          uid: uid,
          userCountryCode: countryCode,
          userCityKey: cityKey,
        );
        break;
      case GroupDiscoveryTab.region:
        matches = GroupDiscoveryLogic.matchesRegionDiscovery(
          data: data,
          uid: uid,
          userCountryCode: countryCode,
          userCityLatitude: userCityLatitude,
          userCityLongitude: userCityLongitude,
        );
        break;
      case GroupDiscoveryTab.country:
        matches = GroupDiscoveryLogic.matchesCountryDiscovery(
          data: data,
          uid: uid,
          userCountryCode: countryCode,
        );
        break;
      case GroupDiscoveryTab.mine:
        matches = false;
        break;
    }

    if (!matches && !isMember) return null;

    return GroupDiscoveryItem(
      id: doc.id,
      data: data,
      isMember: isMember,
      isPending: pendingIds.contains(doc.id),
    );
  }
}
