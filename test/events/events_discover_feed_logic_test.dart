import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/models/event_presentation.dart';
import 'package:socialchat_mvp/services/events_discover_feed_logic.dart';

EventPresentation _e({
  required String id,
  String city = '',
  double? lat,
  double? lng,
  DateTime? start,
  bool sponsored = false,
  bool featured = false,
  String category = '',
  bool active = true,
}) {
  return EventPresentation(
    id: id,
    title: id,
    coverUrl: '',
    photoUrls: const [],
    logoUrl: '',
    category: category,
    startAt: start,
    endAt: null,
    city: city,
    stateName: '',
    countryCode: 'ca',
    placeName: '',
    address: '',
    lat: lat,
    lng: lng,
    description: 'd',
    attendeesCount: 0,
    likesCount: 0,
    status: 'approved',
    isActive: active,
    deleted: false,
    sponsored: sponsored,
    featured: featured,
    featuredUntil: null,
    priceLabel: '',
    isFree: false,
    scheduleItems: const [],
    attractions: const [],
    createdBy: 'u',
  );
}

void main() {
  test('hides empty sections and dedupes across priority', () {
    final now = DateTime(2026, 7, 30, 12);
    final today = DateTime(2026, 7, 30, 18);
    final tomorrow = DateTime(2026, 7, 31, 18);
    final pool = [
      _e(id: 'feat', sponsored: true, start: tomorrow, city: 'Toronto'),
      _e(id: 'near', city: 'Toronto', lat: 43.65, lng: -79.38, start: tomorrow),
      _e(id: 'today', city: 'Ottawa', start: today),
      _e(id: 'up', city: 'Ottawa', start: tomorrow.add(const Duration(days: 2))),
      _e(id: 'music', category: 'Show', start: tomorrow.add(const Duration(days: 3))),
    ];

    final sections = EventsDiscoverFeedLogic.partition(
      pool: pool,
      userLat: 43.65,
      userLng: -79.38,
      userCityKey: 'toronto',
      now: now,
    );

    expect(sections.featured.map((e) => e.id), contains('feat'));
    // feat already used — not repeated in nearby
    expect(sections.nearby.map((e) => e.id), isNot(contains('feat')));
    expect(sections.nearby.map((e) => e.id), contains('near'));
    expect(sections.today.map((e) => e.id), contains('today'));
    expect(sections.categories['music']?.map((e) => e.id), contains('music'));
    // 'up' has empty category → still available for upcoming
    expect(sections.upcoming.map((e) => e.id), contains('up'));
  });

  test('empty pool yields empty sections', () {
    final sections = EventsDiscoverFeedLogic.partition(
      pool: const [],
      userLat: null,
      userLng: null,
      userCityKey: '',
    );
    expect(sections.isEmpty, isTrue);
  });
}
