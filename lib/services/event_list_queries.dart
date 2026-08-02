import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/event_lifecycle.dart';
import 'events_geo_constants.dart';

/// Consultas Firestore para listas públicas e Meus eventos.
///
/// Índices correspondentes: `firestore.indexes.events_date_org.DRAFT.json`
/// (não publicar sem autorização).
class EventListQueries {
  EventListQueries._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  static Timestamp get _now => Timestamp.now();

  /// Base pública: aprovado + ativo. Não usa `deleted == false` / `archived == false`
  /// para não excluir legados sem o campo; exclusão de deleted/archived fica
  /// no filtro [EventLifecycle.passesPublicVisibility] + queries de data.
  static Query<Map<String, dynamic>> _publicBase({
    required String countryCode,
  }) {
    return _db
        .collection('events')
        .where('status', isEqualTo: 'approved')
        .where('isActive', isEqualTo: true)
        .where('countryCode', isEqualTo: countryCode);
  }

  /// Futuros públicos (startAt > agora).
  ///
  /// [stateName] filtra por estado (aba Brasil → estado). Requer índice
  /// status+isActive+countryCode+stateName+startAt (ver DRAFT).
  static Query<Map<String, dynamic>> publicUpcoming({
    required String countryCode,
    String? scope,
    String? cityKey,
    String? regionKey,
    String? stateName,
    int limit = EventLifecycle.publicPageSize,
  }) {
    Query<Map<String, dynamic>> q = _publicBase(countryCode: countryCode);
    if (scope == 'city' && cityKey != null) {
      q = q.where('scope', isEqualTo: 'city').where('cityKey', isEqualTo: cityKey);
    } else if (regionKey != null) {
      q = q.where('regionKey', isEqualTo: regionKey);
    } else if (stateName != null && stateName.trim().isNotEmpty) {
      q = q.where('stateName', isEqualTo: stateName.trim());
    }
    return q
        .where('startAt', isGreaterThan: _now)
        .orderBy('startAt')
        .limit(limit);
  }

  /// Acontecendo agora (startAt <= agora && endAt >= agora).
  static Query<Map<String, dynamic>> publicLive({
    required String countryCode,
    String? scope,
    String? cityKey,
    String? regionKey,
    String? stateName,
    int limit = EventLifecycle.publicPageSize,
  }) {
    final now = _now;
    Query<Map<String, dynamic>> q = _publicBase(countryCode: countryCode);
    if (scope == 'city' && cityKey != null) {
      q = q.where('scope', isEqualTo: 'city').where('cityKey', isEqualTo: cityKey);
    } else if (regionKey != null) {
      q = q.where('regionKey', isEqualTo: regionKey);
    } else if (stateName != null && stateName.trim().isNotEmpty) {
      q = q.where('stateName', isEqualTo: stateName.trim());
    }
    return q
        .where('startAt', isLessThanOrEqualTo: now)
        .where('endAt', isGreaterThanOrEqualTo: now)
        .orderBy('startAt')
        .orderBy('endAt')
        .limit(limit);
  }

  /// País inteiro (Arredores / Brasil): sem regionKey e com page size maior.
  static Query<Map<String, dynamic>> publicUpcomingExplore({
    required String countryCode,
    int limit = EventsGeoConstants.publicExplorePageSize,
  }) {
    return publicUpcoming(countryCode: countryCode, limit: limit);
  }

  static Query<Map<String, dynamic>> publicLiveExplore({
    required String countryCode,
    int limit = EventsGeoConstants.publicExplorePageSize,
  }) {
    return publicLive(countryCode: countryCode, limit: limit);
  }

  // --- Meus eventos (por seção; pageSize 20) ---

  static Query<Map<String, dynamic>> myUpcoming({
    required String uid,
    int limit = EventLifecycle.pageSize,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection('events')
        .where('createdBy', isEqualTo: uid)
        // Compat: não filtrar archived==false até backfill (legado sem campo).
        .where('startAt', isGreaterThan: _now)
        .orderBy('startAt')
        .limit(limit);
    if (startAfter != null) q = q.startAfterDocument(startAfter);
    return q;
  }

  static Query<Map<String, dynamic>> myLive({
    required String uid,
    int limit = EventLifecycle.pageSize,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) {
    final now = _now;
    Query<Map<String, dynamic>> q = _db
        .collection('events')
        .where('createdBy', isEqualTo: uid)
        // Compat: não filtrar archived==false até backfill.
        .where('startAt', isLessThanOrEqualTo: now)
        .where('endAt', isGreaterThanOrEqualTo: now)
        .orderBy('startAt')
        .orderBy('endAt')
        .limit(limit);
    if (startAfter != null) q = q.startAfterDocument(startAfter);
    return q;
  }

  static Query<Map<String, dynamic>> myPast({
    required String uid,
    int limit = EventLifecycle.pageSize,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection('events')
        .where('createdBy', isEqualTo: uid)
        // Compat: não filtrar archived==false até backfill.
        .where('endAt', isLessThan: _now)
        .orderBy('endAt', descending: true)
        .limit(limit);
    if (startAfter != null) q = q.startAfterDocument(startAfter);
    return q;
  }

  static Query<Map<String, dynamic>> myArchived({
    required String uid,
    int limit = EventLifecycle.pageSize,
    DocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) {
    Query<Map<String, dynamic>> q = _db
        .collection('events')
        .where('createdBy', isEqualTo: uid)
        .where('archived', isEqualTo: true)
        .orderBy('archivedAt', descending: true)
        .limit(limit);
    if (startAfter != null) q = q.startAfterDocument(startAfter);
    return q;
  }
}
