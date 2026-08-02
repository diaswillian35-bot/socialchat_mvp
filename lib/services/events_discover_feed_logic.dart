import '../models/event_presentation.dart';
import 'group_geo.dart';

/// Particionamento client-side do pool de eventos (testável, sem Firestore).
class EventsDiscoverFeedLogic {
  EventsDiscoverFeedLogic._();

  static const int featuredLimit = 8;
  static const int nearbyLimit = 12;
  static const int todayLimit = 12;
  static const int upcomingLimit = 15;
  static const int categoryLimit = 10;
  static const double nearbyRadiusKm = 50;

  /// Prioridade de dedupe: featured → nearby → today → upcoming → category.
  static EventsDiscoverSections partition({
    required List<EventPresentation> pool,
    required double? userLat,
    required double? userLng,
    required String userCityKey,
    DateTime? now,
  }) {
    final clock = now ?? DateTime.now();
    final todayStart = DateTime(clock.year, clock.month, clock.day);
    final tomorrowStart = todayStart.add(const Duration(days: 1));
    final used = <String>{};

    List<EventPresentation> take(
      Iterable<EventPresentation> source,
      int limit,
    ) {
      final out = <EventPresentation>[];
      for (final e in source) {
        if (used.contains(e.id)) continue;
        out.add(e);
        used.add(e.id);
        if (out.length >= limit) break;
      }
      return out;
    }

    final active = pool.where((e) {
      if (e.deleted) return false;
      if (!e.isActive && e.status != 'approved') return false;
      if (e.isCancelled) return false;
      final start = e.startAt;
      if (start == null) return true;
      // Expire ~1 day after start (compat com lista antiga).
      return !start.add(const Duration(days: 1)).isBefore(clock);
    }).toList();

    final featured = take(
      active.where((e) => e.isFeaturedLive),
      featuredLimit,
    );

    final nearby = take(
      active.where((e) {
        final cityMatch = userCityKey.isNotEmpty &&
            e.city.trim().toLowerCase() == userCityKey;
        if (cityMatch) return true;
        final d = GroupGeo.distanceKm(
          lat1: userLat,
          lng1: userLng,
          lat2: e.lat,
          lng2: e.lng,
        );
        return d != null && d <= nearbyRadiusKm;
      }),
      nearbyLimit,
    );

    final today = take(
      active.where((e) {
        final s = e.startAt;
        if (s == null) return false;
        return !s.isBefore(todayStart) && s.isBefore(tomorrowStart);
      }),
      todayLimit,
    );

    // Categorias a partir do restante (antes de “Próximos”) para ter conteúdo.
    final byCat = <String, List<EventPresentation>>{};
    for (final e in active) {
      if (used.contains(e.id)) continue;
      final key = _normalizeCategory(e.category);
      if (key.isEmpty) continue;
      byCat.putIfAbsent(key, () => <EventPresentation>[]).add(e);
    }
    final categorySections = <String, List<EventPresentation>>{};
    final catKeys = byCat.keys.toList()..sort();
    for (final key in catKeys) {
      final items = take(byCat[key]!, categoryLimit);
      if (items.isNotEmpty) {
        categorySections[key] = items;
      }
    }

    final upcoming = take(
      active.where((e) {
        final s = e.startAt;
        if (s == null) return false;
        return !s.isBefore(tomorrowStart);
      }),
      upcomingLimit,
    );

    return EventsDiscoverSections(
      featured: featured,
      nearby: nearby,
      today: today,
      upcoming: upcoming,
      categories: categorySections,
    );
  }

  static String _normalizeCategory(String raw) {
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return '';
    if (v.contains('music') ||
        v.contains('música') ||
        v.contains('musica') ||
        v == 'show') {
      return 'music';
    }
    if (v.contains('sport') || v.contains('esporte')) return 'sports';
    if (v.contains('restaurant') ||
        v.contains('restaurante') ||
        v.contains('cafe') ||
        v.contains('café') ||
        v.contains('food') ||
        v.contains('comida')) {
      return 'restaurant';
    }
    if (v.contains('cultur')) return 'culture';
    if (v.contains('idioma') || v.contains('language')) return 'languages';
    if (v.contains('geral') || v.contains('general')) return 'general';
    return v;
  }

  static String categoryL10nKey(String normalized) {
    switch (normalized) {
      case 'music':
        return 'events_music';
      case 'sports':
        return 'events_sports';
      case 'restaurant':
        return 'events_restaurant';
      case 'culture':
        return 'events_culture';
      case 'languages':
        return 'events_languages';
      case 'general':
        return 'events_general';
      default:
        return 'events_default_category';
    }
  }
}

class EventsDiscoverSections {
  const EventsDiscoverSections({
    required this.featured,
    required this.nearby,
    required this.today,
    required this.upcoming,
    required this.categories,
  });

  final List<EventPresentation> featured;
  final List<EventPresentation> nearby;
  final List<EventPresentation> today;
  final List<EventPresentation> upcoming;
  final Map<String, List<EventPresentation>> categories;

  bool get isEmpty =>
      featured.isEmpty &&
      nearby.isEmpty &&
      today.isEmpty &&
      upcoming.isEmpty &&
      categories.isEmpty;
}
