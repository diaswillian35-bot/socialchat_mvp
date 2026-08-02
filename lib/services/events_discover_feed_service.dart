import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/event_presentation.dart';
import 'events_discover_feed_logic.dart';

/// Carrega um pool limitado de eventos ativos (poucas leituras) e particiona.
class EventsDiscoverFeedService {
  EventsDiscoverFeedService({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  static const int poolLimit = 50;
  static const int featuredQueryLimit = 8;

  Future<EventsDiscoverFeedResult> load() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return EventsDiscoverFeedResult.empty();
    }

    final userSnap = await _db.collection('users').doc(uid).get();
    final user = userSnap.data() ?? const <String, dynamic>{};
    final country = (user['homeCountryCode'] ?? user['countryCode'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final city = (user['cityName'] ?? user['city'] ?? '').toString().trim();
    final cityKey = city.toLowerCase();
    final lat = _asDouble(user['lat']);
    final lng = _asDouble(user['lng']);

    if (country.isEmpty) {
      return EventsDiscoverFeedResult(
        sections: const EventsDiscoverSections(
          featured: [],
          nearby: [],
          today: [],
          upcoming: [],
          categories: {},
        ),
        countryCode: country,
        city: city,
        userLat: lat,
        userLng: lng,
      );
    }

    final now = Timestamp.now();

    // 1) Destaque (featured/sponsored) — query pequena.
    final featuredSnap = await _db
        .collection('events')
        .where('isActive', isEqualTo: true)
        .where('countryCode', isEqualTo: country)
        .where('sponsored', isEqualTo: true)
        .where('startAt', isGreaterThan: now)
        .orderBy('startAt')
        .limit(featuredQueryLimit)
        .get();

    // 2) Pool principal do país (reutilizado para perto/hoje/próximos/categorias).
    final poolSnap = await _db
        .collection('events')
        .where('isActive', isEqualTo: true)
        .where('countryCode', isEqualTo: country)
        .where('startAt', isGreaterThan: now)
        .orderBy('startAt')
        .limit(poolLimit)
        .get();

    final byId = <String, EventPresentation>{};
    for (final doc in featuredSnap.docs) {
      byId[doc.id] = EventPresentation.fromDoc(doc);
    }
    for (final doc in poolSnap.docs) {
      byId.putIfAbsent(doc.id, () => EventPresentation.fromDoc(doc));
    }

    // Tentar featured==true se o índice existir; falha silenciosa.
    try {
      final featTrue = await _db
          .collection('events')
          .where('isActive', isEqualTo: true)
          .where('countryCode', isEqualTo: country)
          .where('featured', isEqualTo: true)
          .where('startAt', isGreaterThan: now)
          .orderBy('startAt')
          .limit(featuredQueryLimit)
          .get();
      for (final doc in featTrue.docs) {
        byId[doc.id] = EventPresentation.fromDoc(doc);
      }
    } catch (_) {
      // Índice pode não existir; sponsored + pool bastam.
    }

    final pool = byId.values.toList()
      ..sort((a, b) {
        final aT = a.startAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bT = b.startAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return aT.compareTo(bT);
      });

    final sections = EventsDiscoverFeedLogic.partition(
      pool: pool,
      userLat: lat,
      userLng: lng,
      userCityKey: cityKey,
    );

    return EventsDiscoverFeedResult(
      sections: sections,
      countryCode: country,
      city: city,
      userLat: lat,
      userLng: lng,
    );
  }

  static double? _asDouble(dynamic v) {
    if (v is num && v.isFinite) return v.toDouble();
    return null;
  }
}

class EventsDiscoverFeedResult {
  const EventsDiscoverFeedResult({
    required this.sections,
    required this.countryCode,
    required this.city,
    required this.userLat,
    required this.userLng,
  });

  final EventsDiscoverSections sections;
  final String countryCode;
  final String city;
  final double? userLat;
  final double? userLng;

  factory EventsDiscoverFeedResult.empty() => const EventsDiscoverFeedResult(
        sections: EventsDiscoverSections(
          featured: [],
          nearby: [],
          today: [],
          upcoming: [],
          categories: {},
        ),
        countryCode: '',
        city: '',
        userLat: null,
        userLng: null,
      );
}
