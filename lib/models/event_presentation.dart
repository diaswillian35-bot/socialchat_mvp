import 'package:cloud_firestore/cloud_firestore.dart';

import '../l10n/app_texts.dart';
import '../services/iso_country_names.dart';

/// View-model de evento para lista/detalhe/share (sem escrita no Firestore).
class EventPresentation {
  const EventPresentation({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.photoUrls,
    required this.logoUrl,
    required this.category,
    required this.startAt,
    required this.endAt,
    required this.city,
    required this.stateName,
    required this.countryCode,
    required this.placeName,
    required this.address,
    required this.lat,
    required this.lng,
    required this.description,
    required this.attendeesCount,
    required this.likesCount,
    required this.status,
    required this.isActive,
    required this.deleted,
    required this.sponsored,
    required this.featured,
    required this.featuredUntil,
    required this.priceLabel,
    required this.isFree,
    required this.scheduleItems,
    required this.attractions,
    required this.createdBy,
  });

  final String id;
  final String title;
  final String coverUrl;
  final List<String> photoUrls;
  final String logoUrl;
  final String category;
  final DateTime? startAt;
  final DateTime? endAt;
  final String city;
  final String stateName;
  final String countryCode;
  final String placeName;
  final String address;
  final double? lat;
  final double? lng;
  final String description;
  final int attendeesCount;
  final int likesCount;
  final String status;
  final bool isActive;
  final bool deleted;
  final bool sponsored;
  final bool featured;
  final DateTime? featuredUntil;
  final String priceLabel;
  final bool isFree;
  final List<String> scheduleItems;
  final List<String> attractions;
  final String createdBy;

  bool get isCancelled =>
      status == 'cancelled' || status == 'canceled';

  bool get isConfirmed =>
      !isCancelled && (status == 'approved' || (isActive && status.isEmpty));

  bool get isFeaturedLive {
    if (!featured && !sponsored) return false;
    final until = featuredUntil;
    if (until == null) return featured || sponsored;
    return until.isAfter(DateTime.now());
  }

  String get primaryImageUrl {
    if (coverUrl.isNotEmpty) return coverUrl;
    if (photoUrls.isNotEmpty) return photoUrls.first;
    return '';
  }

  List<String> get galleryImages {
    final out = <String>[];
    final seen = <String>{};
    void add(String u) {
      final v = u.trim();
      if (v.isEmpty || !seen.add(v)) return;
      out.add(v);
    }

    add(coverUrl);
    for (final p in photoUrls) {
      add(p);
    }
    return out;
  }

  String venueLine() {
    if (placeName.isNotEmpty) return placeName;
    if (address.isNotEmpty) return address;
    return '';
  }

  /// Cidade • região • país (país via ISO + idioma do app).
  String locationLine(String languageCode) {
    final parts = <String>[];
    if (city.isNotEmpty) parts.add(_cap(city));
    if (stateName.isNotEmpty) parts.add(stateName);
    final country = IsoCountryNames.displayName(countryCode, languageCode);
    if (country.isNotEmpty) parts.add(country);
    return parts.join(' • ');
  }

  String shortDateLabel() {
    final start = startAt;
    if (start == null) return AppTexts.t('events_no_date');
    final end = endAt;
    String two(int n) => n.toString().padLeft(2, '0');
    final months = _monthShort(start.month);
    if (end != null &&
        (end.day != start.day ||
            end.month != start.month ||
            end.year != start.year)) {
      if (start.month == end.month && start.year == end.year) {
        return '${start.day}-${end.day} $months';
      }
      return '${start.day} $months – ${end.day} ${_monthShort(end.month)}';
    }
    final time = '${two(start.hour)}:${two(start.minute)}';
    return '${start.day} $months • $time';
  }

  String fullDateLabel() {
    final start = startAt;
    if (start == null) return AppTexts.t('events_no_date');
    String two(int n) => n.toString().padLeft(2, '0');
    final end = endAt;
    if (end != null &&
        (end.day != start.day ||
            end.month != start.month ||
            end.year != start.year)) {
      return '${start.day}–${end.day}/${two(start.month)}/${start.year}';
    }
    return '${two(start.day)}/${two(start.month)}/${start.year} • ${two(start.hour)}:${two(start.minute)}';
  }

  /// Badge temporal/social (Hoje, Amanhã, Em alta) — sem hardcode de país.
  String? statusBadgeKey() {
    if (isFeaturedLive) return 'events_trending_badge';
    final start = startAt;
    if (start == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(start.year, start.month, start.day);
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'events_today_badge';
    if (diff == 1) return 'events_tomorrow_badge';
    return null;
  }

  bool get hasAbout => description.trim().isNotEmpty;
  bool get hasSchedule => scheduleItems.isNotEmpty;
  bool get hasAttractions => attractions.isNotEmpty;
  bool get hasGallery => galleryImages.isNotEmpty;
  bool get hasLocation =>
      venueLine().isNotEmpty ||
      city.isNotEmpty ||
      (lat != null && lng != null);

  String? displayPrice() {
    if (priceLabel.isNotEmpty) return priceLabel;
    if (isFree) return AppTexts.t('events_free_entry');
    return null;
  }

  factory EventPresentation.fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    return EventPresentation.fromMap(doc.id, doc.data() ?? const {});
  }

  factory EventPresentation.fromMap(String id, Map<String, dynamic> data) {
    DateTime? asDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      return null;
    }

    double? asDouble(dynamic v) {
      if (v is num && v.isFinite) return v.toDouble();
      return null;
    }

    int asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return 0;
    }

    List<String> asStringList(dynamic v) {
      if (v is! List) return const [];
      return v
          .map((e) => _formatScheduleOrAttraction(e))
          .where((e) => e.isNotEmpty)
          .toList();
    }

    final photos = () {
      if (data['photoUrls'] is! List) return const <String>[];
      return (data['photoUrls'] as List)
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }();
    final schedule = asStringList(
      data['schedule'] ?? data['programacao'] ?? data['scheduleItems'],
    );
    final attractions = asStringList(
      data['attractions'] ?? data['atracoes'] ?? data['attractionsList'],
    );

    final price = (data['price'] ?? data['ticketInfo'] ?? data['ticketPrice'] ?? '')
        .toString()
        .trim();
    final isFree = data['isFree'] == true ||
        price.toLowerCase() == 'free' ||
        price.toLowerCase() == 'gratuito' ||
        price.toLowerCase() == 'gratis';

    return EventPresentation(
      id: id,
      title: (data['title'] ??
              data['eventTitle'] ??
              data['name'] ??
              AppTexts.t('events_default_category'))
          .toString()
          .trim(),
      coverUrl: (data['coverUrl'] ?? '').toString().trim(),
      photoUrls: photos,
      logoUrl: (data['logoUrl'] ?? '').toString().trim(),
      category: (data['category'] ?? data['type'] ?? '').toString().trim(),
      startAt: asDate(data['startAt']),
      endAt: asDate(data['endAt']),
      city: (data['city'] ?? '').toString().trim(),
      stateName: (data['stateName'] ?? '').toString().trim(),
      countryCode: (data['countryCode'] ?? '').toString().trim().toLowerCase(),
      placeName: (data['placeName'] ?? data['placeDisplay'] ?? '')
          .toString()
          .trim(),
      address: (data['address'] ?? '').toString().trim(),
      lat: asDouble(data['lat']),
      lng: asDouble(data['lng']),
      description: (data['description'] ??
              data['desc'] ??
              data['about'] ??
              data['sobre'] ??
              '')
          .toString()
          .trim(),
      attendeesCount: asInt(data['attendeesCount'] ?? data['participantsCount']),
      likesCount: asInt(data['likesCount']),
      status: (data['status'] ?? '').toString().trim().toLowerCase(),
      isActive: data['isActive'] == true,
      deleted: data['deleted'] == true,
      sponsored: data['sponsored'] == true,
      featured: data['featured'] == true,
      featuredUntil: asDate(data['featuredUntil']),
      priceLabel: isFree ? '' : price,
      isFree: data['isFree'] == true || (isFree && price.isEmpty),
      scheduleItems: schedule,
      attractions: attractions,
      createdBy: (data['createdBy'] ??
              data['organizerId'] ??
              data['ownerId'] ??
              '')
          .toString()
          .trim(),
    );
  }

  /// Formata item de schedule/attractions (string legado ou Map estruturado).
  static String _formatScheduleOrAttraction(dynamic e) {
    if (e == null) return '';
    if (e is String) return e.trim();
    if (e is! Map) return e.toString().trim();
    final m = Map<String, dynamic>.from(e);

    final name = (m['name'] ?? '').toString().trim();
    final title = (m['title'] ?? '').toString().trim();
    final description = (m['description'] ?? '').toString().trim();

    // Attraction: name — description
    if (name.isNotEmpty) {
      return description.isNotEmpty ? '$name — $description' : name;
    }

    // Schedule: day + time + title
    final parts = <String>[];
    final day = (m['day'] ?? '').toString().trim();
    if (day.isNotEmpty) parts.add(day);
    final start = (m['startTime'] ?? '').toString().trim();
    final end = (m['endTime'] ?? '').toString().trim();
    final time = [start, end].where((s) => s.isNotEmpty).join('–');
    if (time.isNotEmpty) parts.add(time);
    if (title.isNotEmpty) parts.add(title);
    final line = parts.join(' — ').trim();
    if (line.isNotEmpty) {
      return description.isNotEmpty ? '$line — $description' : line;
    }
    return description;
  }

  static String _cap(String value) {
    if (value.isEmpty) return value;
    return value
        .split(' ')
        .map((w) =>
            w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  static String _monthShort(int month) {
    const keys = [
      'month_short_1',
      'month_short_2',
      'month_short_3',
      'month_short_4',
      'month_short_5',
      'month_short_6',
      'month_short_7',
      'month_short_8',
      'month_short_9',
      'month_short_10',
      'month_short_11',
      'month_short_12',
    ];
    if (month < 1 || month > 12) return '';
    final t = AppTexts.t(keys[month - 1]);
    if (t == keys[month - 1]) {
      // Fallback ASCII if key missing during rollout.
      const en = [
        'JAN',
        'FEB',
        'MAR',
        'APR',
        'MAY',
        'JUN',
        'JUL',
        'AUG',
        'SEP',
        'OCT',
        'NOV',
        'DEC'
      ];
      return en[month - 1];
    }
    return t;
  }
}
