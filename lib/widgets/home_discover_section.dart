import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../pages/event_detail_page.dart';
import '../pages/events_page_new.dart';
import 'home_section_header.dart';

/// Carrossel de eventos na home — somente leitura, não altera lógica da aba Eventos.
class HomeDiscoverSection extends StatelessWidget {
  const HomeDiscoverSection({
    super.key,
    required this.countryCode,
    this.limit = 15,
  });

  final String countryCode;
  final int limit;

  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _logoBlue = Color(0xFF264E9A);

  bool _isPromoted(Map<String, dynamic> data) {
    return data['sponsored'] == true ||
        data['isBoosted'] == true ||
        data['boosted'] == true;
  }

  String _resolveImageUrl(Map<String, dynamic> data) {
    final rawPhotos = data['photoUrls'];
    final photoUrls = rawPhotos is List
        ? rawPhotos
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList()
        : <String>[];

    if (photoUrls.isNotEmpty) return photoUrls.first;

    for (final key in ['coverUrl', 'coverImageUrl', 'imageUrl']) {
      final url = (data[key] ?? '').toString().trim();
      if (url.isNotEmpty) return url;
    }
    return '';
  }

  String _eventBadge(Timestamp? ts) {
    if (ts == null) return '';
    final now = DateTime.now();
    final date = ts.toDate();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay = DateTime(date.year, date.month, date.day);
    final diff = eventDay.difference(today).inDays;
    if (diff == 0) return AppTexts.t('events_today_badge');
    if (diff == 1) return AppTexts.t('events_tomorrow_badge');
    return '';
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _prepareDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final normalizedCountry = countryCode.trim().toLowerCase();
    final now = Timestamp.now();

    final upcoming = docs.where((doc) {
      final data = doc.data();
      if (data['isActive'] != true) return false;
      final startAt = data['startAt'];
      if (startAt is! Timestamp || startAt.compareTo(now) <= 0) return false;

      if (normalizedCountry.isEmpty) return true;
      final eventCountry = (data['countryCode'] ?? data['country'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      return eventCountry.isEmpty || eventCountry == normalizedCountry;
    }).toList();

    upcoming.sort((a, b) {
      final aPromoted = _isPromoted(a.data()) ? 1 : 0;
      final bPromoted = _isPromoted(b.data()) ? 1 : 0;
      if (aPromoted != bPromoted) return bPromoted.compareTo(aPromoted);

      final aStart = a.data()['startAt'];
      final bStart = b.data()['startAt'];
      if (aStart is Timestamp && bStart is Timestamp) {
        return aStart.compareTo(bStart);
      }
      return 0;
    });

    if (upcoming.length <= limit) return upcoming;
    return upcoming.sublist(0, limit);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: t.get('home_discover'),
          seeAllLabel: t.get('home_see_all'),
          onSeeAll: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const EventsPage()),
            );
          },
        ),
        const SizedBox(height: 8),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('events')
              .where('isActive', isEqualTo: true)
              .where('startAt', isGreaterThan: Timestamp.now())
              .orderBy('startAt')
              .limit(50)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return SizedBox(
                height: 170,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  t.get('home_events_load_error'),
                  style: const TextStyle(color: _muted, fontSize: 14),
                ),
              );
            }

            final docs = _prepareDocs(snapshot.data?.docs ?? []);
            if (docs.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  t.get('home_discover_empty'),
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              );
            }

            return LayoutBuilder(
              builder: (context, constraints) {
                const gap = 8.0;
                const visibleCards = 3;
                final cardWidth =
                    (constraints.maxWidth - (gap * (visibleCards - 1))) /
                        visibleCards;
                final carouselHeight = (cardWidth * 1.52).clamp(150.0, 188.0);
                final imageHeight = (cardWidth * 0.56).clamp(58.0, 72.0);

                return SizedBox(
                  height: carouselHeight,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: gap),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data();
                      final title = (data['title'] ?? 'Evento').toString();
                      final city = (data['city'] ?? '').toString();
                      final state = (data['stateName'] ?? data['state'] ?? '')
                          .toString();
                      final category =
                          (data['category'] ?? t.get('events_default_category'))
                              .toString();
                      final startAt = data['startAt'] is Timestamp
                          ? data['startAt'] as Timestamp
                          : null;
                      final imageUrl = _resolveImageUrl(data);
                      final location = city.isNotEmpty
                          ? (state.isNotEmpty ? '$city, $state' : city)
                          : t.get('events_regional_event');
                      final badge = _eventBadge(startAt);

                      return InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EventDetailPage(eventId: doc.id),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: cardWidth,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(11),
                                    ),
                                    child: SizedBox(
                                      height: imageHeight,
                                      width: double.infinity,
                                      child: imageUrl.isNotEmpty
                                          ? Image.network(
                                              imageUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  _placeholder(),
                                            )
                                          : _placeholder(),
                                    ),
                                  ),
                                  if (badge.isNotEmpty)
                                    Positioned(
                                      top: 5,
                                      left: 5,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: badge ==
                                                  t.get('events_today_badge')
                                              ? const Color(0xFF16A34A)
                                              : const Color(0xFFF97316),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          badge,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 8,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    7,
                                    6,
                                    7,
                                    7,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _text,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          height: 1.12,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        location,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _muted,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        category,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: _logoBlue,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xFFEFF2F7),
      alignment: Alignment.center,
      child: const Icon(Icons.event_rounded, color: Color(0xFF94A3B8), size: 24),
    );
  }
}
