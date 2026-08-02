import '../utils/event_timezone.dart';

/// Item de programação canônico (create/update editorial).
class EventScheduleItem {
  const EventScheduleItem({
    required this.id,
    this.day = '',
    this.startTime = '',
    this.endTime = '',
    this.title = '',
    this.description = '',
    this.tag = '',
    this.order = 0,
  });

  final String id;
  final String day;
  final String startTime;
  final String endTime;
  final String title;
  final String description;
  final String tag;
  final int order;

  EventScheduleItem copyWith({
    String? id,
    String? day,
    String? startTime,
    String? endTime,
    String? title,
    String? description,
    String? tag,
    int? order,
  }) {
    return EventScheduleItem(
      id: id ?? this.id,
      day: day ?? this.day,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      title: title ?? this.title,
      description: description ?? this.description,
      tag: tag ?? this.tag,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'day': day,
        'startTime': startTime,
        'endTime': endTime,
        'title': title,
        'description': description,
        'tag': tag,
        'order': order,
      };

  factory EventScheduleItem.fromJson(Map<String, dynamic> json) {
    return EventScheduleItem(
      id: (json['id'] ?? '').toString(),
      day: (json['day'] ?? '').toString(),
      startTime: (json['startTime'] ?? '').toString(),
      endTime: (json['endTime'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      tag: (json['tag'] ?? '').toString(),
      order: (json['order'] is num) ? (json['order'] as num).toInt() : 0,
    );
  }
}

/// Atração canônica.
class EventAttractionItem {
  const EventAttractionItem({
    required this.id,
    this.name = '',
    this.description = '',
    this.photoUrl = '',
    this.type = '',
    this.order = 0,
  });

  final String id;
  final String name;
  final String description;
  final String photoUrl;
  final String type;
  final int order;

  EventAttractionItem copyWith({
    String? id,
    String? name,
    String? description,
    String? photoUrl,
    String? type,
    int? order,
  }) {
    return EventAttractionItem(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      photoUrl: photoUrl ?? this.photoUrl,
      type: type ?? this.type,
      order: order ?? this.order,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'photoUrl': photoUrl,
        'type': type,
        'order': order,
      };

  factory EventAttractionItem.fromJson(Map<String, dynamic> json) {
    return EventAttractionItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      photoUrl: (json['photoUrl'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      order: (json['order'] is num) ? (json['order'] as num).toInt() : 0,
    );
  }
}

/// Categorias unificadas (allowlist CF).
const List<String> kEventEditorialCategories = [
  'Restaurante',
  'café',
  'Esportes',
  'Show',
  'Geral',
  'Música',
  'Cultura',
  'Idiomas',
  'Festival',
  'Cultural',
];

const Set<String> kEventTicketTypes = {'free', 'paid', 'inquire'};

/// Estado serializável do wizard editorial (7 passos).
class EventEditorialDraft {
  const EventEditorialDraft({
    this.title = '',
    this.shortDescription = '',
    this.description = '',
    this.category = 'Geral',
    this.subcategories = const [],
    this.primaryLanguage = '',
    this.startDate,
    this.startTime = '',
    this.endDate,
    this.endTime = '',
    this.eventTimeZone = 'America/Toronto',
    this.city = '',
    this.cityKey = '',
    this.stateName = '',
    this.countryCode = '',
    this.countryName = '',
    this.placeName = '',
    this.address = '',
    this.placeDisplay = '',
    this.placeId = '',
    this.lat,
    this.lng,
    this.regionKey = '',
    this.scope = 'city',
    this.ticketType = 'free',
    this.isFree = true,
    this.price = '',
    this.priceCurrency = '',
    this.ticketUrl = '',
    this.ticketInfo = '',
    this.expectedAudience,
    this.coverUrl = '',
    this.photoUrls = const [],
    this.logoUrl = '',
    this.pendingPhotoPaths = const [],
    this.pendingCoverPath = '',
    this.pendingLogoPath = '',
    this.schedule = const [],
    this.attractions = const [],
    this.accessibility = '',
    this.parking = '',
    this.foodInfo = '',
    this.ageRating = '',
    this.entryPolicy = '',
    this.publicContact = '',
    this.publicContactConsent = false,
    this.websiteUrl = '',
    this.publicNotes = '',
    this.sponsorInterested = false,
  });

  final String title;
  final String shortDescription;
  final String description;
  final String category;
  final List<String> subcategories;
  final String primaryLanguage;

  final DateTime? startDate;
  final String startTime;
  final DateTime? endDate;
  final String endTime;
  final String eventTimeZone;

  final String city;
  final String cityKey;
  final String stateName;
  final String countryCode;
  final String countryName;
  final String placeName;
  final String address;
  final String placeDisplay;
  final String placeId;
  final double? lat;
  final double? lng;
  final String regionKey;
  final String scope;

  final String ticketType;
  final bool isFree;
  final String price;
  final String priceCurrency;
  final String ticketUrl;
  final String ticketInfo;
  final int? expectedAudience;

  final String coverUrl;
  final List<String> photoUrls;
  final String logoUrl;
  final List<String> pendingPhotoPaths;
  final String pendingCoverPath;
  final String pendingLogoPath;

  final List<EventScheduleItem> schedule;
  final List<EventAttractionItem> attractions;

  final String accessibility;
  final String parking;
  final String foodInfo;
  final String ageRating;
  final String entryPolicy;
  final String publicContact;
  final bool publicContactConsent;
  final String websiteUrl;
  final String publicNotes;
  final bool sponsorInterested;

  static const int stepCount = 7;

  EventEditorialDraft copyWith({
    String? title,
    String? shortDescription,
    String? description,
    String? category,
    List<String>? subcategories,
    String? primaryLanguage,
    DateTime? startDate,
    String? startTime,
    DateTime? endDate,
    String? endTime,
    String? eventTimeZone,
    String? city,
    String? cityKey,
    String? stateName,
    String? countryCode,
    String? countryName,
    String? placeName,
    String? address,
    String? placeDisplay,
    String? placeId,
    double? lat,
    double? lng,
    bool clearLatLng = false,
    String? regionKey,
    String? scope,
    String? ticketType,
    bool? isFree,
    String? price,
    String? priceCurrency,
    String? ticketUrl,
    String? ticketInfo,
    int? expectedAudience,
    bool clearExpectedAudience = false,
    String? coverUrl,
    List<String>? photoUrls,
    String? logoUrl,
    List<String>? pendingPhotoPaths,
    String? pendingCoverPath,
    String? pendingLogoPath,
    List<EventScheduleItem>? schedule,
    List<EventAttractionItem>? attractions,
    String? accessibility,
    String? parking,
    String? foodInfo,
    String? ageRating,
    String? entryPolicy,
    String? publicContact,
    bool? publicContactConsent,
    String? websiteUrl,
    String? publicNotes,
    bool? sponsorInterested,
  }) {
    return EventEditorialDraft(
      title: title ?? this.title,
      shortDescription: shortDescription ?? this.shortDescription,
      description: description ?? this.description,
      category: category ?? this.category,
      subcategories: subcategories ?? this.subcategories,
      primaryLanguage: primaryLanguage ?? this.primaryLanguage,
      startDate: startDate ?? this.startDate,
      startTime: startTime ?? this.startTime,
      endDate: endDate ?? this.endDate,
      endTime: endTime ?? this.endTime,
      eventTimeZone: eventTimeZone ?? this.eventTimeZone,
      city: city ?? this.city,
      cityKey: cityKey ?? this.cityKey,
      stateName: stateName ?? this.stateName,
      countryCode: countryCode ?? this.countryCode,
      countryName: countryName ?? this.countryName,
      placeName: placeName ?? this.placeName,
      address: address ?? this.address,
      placeDisplay: placeDisplay ?? this.placeDisplay,
      placeId: placeId ?? this.placeId,
      lat: clearLatLng ? null : (lat ?? this.lat),
      lng: clearLatLng ? null : (lng ?? this.lng),
      regionKey: regionKey ?? this.regionKey,
      scope: scope ?? this.scope,
      ticketType: ticketType ?? this.ticketType,
      isFree: isFree ?? this.isFree,
      price: price ?? this.price,
      priceCurrency: priceCurrency ?? this.priceCurrency,
      ticketUrl: ticketUrl ?? this.ticketUrl,
      ticketInfo: ticketInfo ?? this.ticketInfo,
      expectedAudience: clearExpectedAudience
          ? null
          : (expectedAudience ?? this.expectedAudience),
      coverUrl: coverUrl ?? this.coverUrl,
      photoUrls: photoUrls ?? this.photoUrls,
      logoUrl: logoUrl ?? this.logoUrl,
      pendingPhotoPaths: pendingPhotoPaths ?? this.pendingPhotoPaths,
      pendingCoverPath: pendingCoverPath ?? this.pendingCoverPath,
      pendingLogoPath: pendingLogoPath ?? this.pendingLogoPath,
      schedule: schedule ?? this.schedule,
      attractions: attractions ?? this.attractions,
      accessibility: accessibility ?? this.accessibility,
      parking: parking ?? this.parking,
      foodInfo: foodInfo ?? this.foodInfo,
      ageRating: ageRating ?? this.ageRating,
      entryPolicy: entryPolicy ?? this.entryPolicy,
      publicContact: publicContact ?? this.publicContact,
      publicContactConsent:
          publicContactConsent ?? this.publicContactConsent,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      publicNotes: publicNotes ?? this.publicNotes,
      sponsorInterested: sponsorInterested ?? this.sponsorInterested,
    );
  }

  /// Normaliza ticketType ↔ isFree.
  EventEditorialDraft withTicketType(String type) {
    final t = type.trim().toLowerCase();
    if (t == 'free') {
      return copyWith(ticketType: 'free', isFree: true);
    }
    if (t == 'paid' || t == 'inquire') {
      return copyWith(ticketType: t, isFree: false);
    }
    return this;
  }

  Map<String, dynamic> toJson() {
    return {
      'title': title,
      'shortDescription': shortDescription,
      'description': description,
      'category': category,
      'subcategories': subcategories,
      'primaryLanguage': primaryLanguage,
      'startDate': startDate?.toIso8601String(),
      'startTime': startTime,
      'endDate': endDate?.toIso8601String(),
      'endTime': endTime,
      'eventTimeZone': eventTimeZone,
      'city': city,
      'cityKey': cityKey,
      'stateName': stateName,
      'countryCode': countryCode,
      'countryName': countryName,
      'placeName': placeName,
      'address': address,
      'placeDisplay': placeDisplay,
      'placeId': placeId,
      'lat': lat,
      'lng': lng,
      'regionKey': regionKey,
      'scope': scope,
      'ticketType': ticketType,
      'isFree': isFree,
      'price': price,
      'priceCurrency': priceCurrency,
      'ticketUrl': ticketUrl,
      'ticketInfo': ticketInfo,
      'expectedAudience': expectedAudience,
      'coverUrl': coverUrl,
      'photoUrls': photoUrls,
      'logoUrl': logoUrl,
      'pendingPhotoPaths': pendingPhotoPaths,
      'pendingCoverPath': pendingCoverPath,
      'pendingLogoPath': pendingLogoPath,
      'schedule': schedule.map((e) => e.toJson()).toList(),
      'attractions': attractions.map((e) => e.toJson()).toList(),
      'accessibility': accessibility,
      'parking': parking,
      'foodInfo': foodInfo,
      'ageRating': ageRating,
      'entryPolicy': entryPolicy,
      'publicContact': publicContact,
      'publicContactConsent': publicContactConsent,
      'websiteUrl': websiteUrl,
      'publicNotes': publicNotes,
      'sponsorInterested': sponsorInterested,
    };
  }

  factory EventEditorialDraft.fromJson(Map<String, dynamic> json) {
    DateTime? asDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      final s = v.toString().trim();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s);
    }

    List<String> asStringList(dynamic v) {
      if (v is! List) return const [];
      return v
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    List<EventScheduleItem> asSchedule(dynamic v) {
      if (v is! List) return const [];
      final out = <EventScheduleItem>[];
      for (var i = 0; i < v.length; i++) {
        final raw = v[i];
        if (raw is String) {
          final title = raw.trim();
          if (title.isEmpty) continue;
          out.add(EventScheduleItem(
            id: 'legacy_$i',
            title: title,
            order: i,
          ));
          continue;
        }
        if (raw is Map) {
          out.add(EventScheduleItem.fromJson(Map<String, dynamic>.from(raw)));
        }
      }
      out.sort((a, b) => a.order.compareTo(b.order));
      return out;
    }

    List<EventAttractionItem> asAttractions(dynamic v) {
      if (v is! List) return const [];
      final out = <EventAttractionItem>[];
      for (var i = 0; i < v.length; i++) {
        final raw = v[i];
        if (raw is String) {
          final name = raw.trim();
          if (name.isEmpty) continue;
          out.add(EventAttractionItem(
            id: 'legacy_$i',
            name: name,
            order: i,
          ));
          continue;
        }
        if (raw is Map) {
          out.add(
            EventAttractionItem.fromJson(Map<String, dynamic>.from(raw)),
          );
        }
      }
      out.sort((a, b) => a.order.compareTo(b.order));
      return out;
    }

    int? asInt(dynamic v) {
      if (v == null || v == '') return null;
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    double? asDouble(dynamic v) {
      if (v == null || v == '') return null;
      if (v is num && v.isFinite) return v.toDouble();
      return double.tryParse(v.toString());
    }

    final ticket = (json['ticketType'] ?? '').toString().trim().toLowerCase();
    var isFree = json['isFree'] == true;
    var ticketType = ticket;
    if (ticketType == 'free') {
      isFree = true;
    } else if (ticketType == 'paid' || ticketType == 'inquire') {
      isFree = false;
    } else if (isFree) {
      ticketType = 'free';
    } else if (ticketType.isEmpty) {
      ticketType = 'free';
      isFree = true;
    }

    return EventEditorialDraft(
      title: (json['title'] ?? '').toString(),
      shortDescription: (json['shortDescription'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      category: (json['category'] ?? 'Geral').toString(),
      subcategories: asStringList(json['subcategories']),
      primaryLanguage: (json['primaryLanguage'] ?? '').toString(),
      startDate: asDate(json['startDate']),
      startTime: (json['startTime'] ?? '').toString(),
      endDate: asDate(json['endDate']),
      endTime: (json['endTime'] ?? '').toString(),
      eventTimeZone:
          (json['eventTimeZone'] ?? 'America/Toronto').toString().trim(),
      city: (json['city'] ?? '').toString(),
      cityKey: (json['cityKey'] ?? '').toString(),
      stateName: (json['stateName'] ?? '').toString(),
      countryCode: (json['countryCode'] ?? '').toString(),
      countryName: (json['countryName'] ?? '').toString(),
      placeName: (json['placeName'] ?? '').toString(),
      address: (json['address'] ?? '').toString(),
      placeDisplay: (json['placeDisplay'] ?? '').toString(),
      placeId: (json['placeId'] ?? '').toString(),
      lat: asDouble(json['lat']),
      lng: asDouble(json['lng']),
      regionKey: (json['regionKey'] ?? '').toString(),
      scope: (json['scope'] ?? 'city').toString(),
      ticketType: ticketType,
      isFree: isFree,
      price: (json['price'] ?? '').toString(),
      priceCurrency: (json['priceCurrency'] ?? '').toString(),
      ticketUrl: (json['ticketUrl'] ?? '').toString(),
      ticketInfo: (json['ticketInfo'] ?? '').toString(),
      expectedAudience: asInt(json['expectedAudience']),
      coverUrl: (json['coverUrl'] ?? '').toString(),
      photoUrls: asStringList(json['photoUrls']),
      logoUrl: (json['logoUrl'] ?? '').toString(),
      pendingPhotoPaths: asStringList(json['pendingPhotoPaths']),
      pendingCoverPath: (json['pendingCoverPath'] ?? '').toString(),
      pendingLogoPath: (json['pendingLogoPath'] ?? '').toString(),
      schedule: asSchedule(json['schedule']),
      attractions: asAttractions(json['attractions']),
      accessibility: (json['accessibility'] ?? '').toString(),
      parking: (json['parking'] ?? '').toString(),
      foodInfo: (json['foodInfo'] ?? '').toString(),
      ageRating: (json['ageRating'] ?? '').toString(),
      entryPolicy: (json['entryPolicy'] ?? '').toString(),
      publicContact: (json['publicContact'] ?? '').toString(),
      publicContactConsent: json['publicContactConsent'] == true,
      websiteUrl: (json['websiteUrl'] ?? '').toString(),
      publicNotes: (json['publicNotes'] ?? '').toString(),
      sponsorInterested: json['sponsorInterested'] == true,
    );
  }

  /// Hidrata a partir do doc Firestore (+ overlay pendingChanges).
  factory EventEditorialDraft.fromEventMap(Map<String, dynamic> data) {
    DateTime? asTs(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      try {
        // Timestamp from cloud_firestore
        final d = (v as dynamic).toDate();
        if (d is DateTime) return d;
      } catch (_) {}
      return DateTime.tryParse(v.toString());
    }

    String two(int n) => n.toString().padLeft(2, '0');
    String timeOf(DateTime? d) {
      if (d == null) return '';
      return '${two(d.hour)}:${two(d.minute)}';
    }

    DateTime? dateOnly(DateTime? d) {
      if (d == null) return null;
      return DateTime(d.year, d.month, d.day);
    }

    final start = asTs(data['startAt']);
    final end = asTs(data['endAt']);

    final base = EventEditorialDraft.fromJson({
      ...data,
      'startDate': dateOnly(start)?.toIso8601String(),
      'startTime': timeOf(start),
      'endDate': dateOnly(end)?.toIso8601String(),
      'endTime': timeOf(end),
    });

    final cat = base.category.trim();
    final category = kEventEditorialCategories.contains(cat) ? cat : 'Geral';
    return base.copyWith(category: category);
  }

  /// Returns [hour, minute] or null.
  static List<int>? parseHm(String value) {
    final s = value.trim();
    if (s.isEmpty) return null;
    final parts = s.split(':');
    if (parts.length < 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return null;
    }
    return [h, m];
  }

  /// Erro de validação do passo (chave l10n ou mensagem curta). Null = ok.
  String? validateStep(int step) {
    switch (step) {
      case 0:
        if (title.trim().isEmpty) return 'create_event_required_title';
        if (title.trim().length > 120) return 'event_wizard_title_too_long';
        if (description.trim().isEmpty) {
          return 'create_event_required_description';
        }
        if (description.trim().length > 5000) {
          return 'event_wizard_description_too_long';
        }
        if (shortDescription.trim().length > 280) {
          return 'event_wizard_short_desc_too_long';
        }
        if (!kEventEditorialCategories.contains(category)) {
          return 'event_wizard_invalid_category';
        }
        return null;
      case 1:
        if (startDate == null || startTime.trim().isEmpty) {
          return 'events_start_required';
        }
        if (endDate == null || endTime.trim().isEmpty) {
          return 'events_end_required';
        }
        if (parseHm(startTime) == null || parseHm(endTime) == null) {
          return 'create_event_required_date_time';
        }
        if (!EventTimezone.isValidIana(eventTimeZone)) {
          return 'events_timezone_invalid';
        }
        if (city.trim().isEmpty) return 'enter_city';
        if (placeName.trim().isEmpty) return 'event_wizard_place_required';
        if (countryCode.trim().isEmpty) {
          return 'event_wizard_country_required';
        }
        try {
          final startUtc = startAtUtc();
          final endUtc = endAtUtc();
          EventTimezone.assertEndAfterStart(startUtc: startUtc, endUtc: endUtc);
        } catch (_) {
          return 'events_end_before_start';
        }
        return null;
      case 2:
        final t = ticketType.trim().toLowerCase();
        if (!kEventTicketTypes.contains(t)) {
          return 'event_wizard_invalid_ticket';
        }
        if (t == 'paid' && price.trim().isEmpty) {
          return 'event_wizard_price_required';
        }
        if (expectedAudience != null &&
            (expectedAudience! < 1 || expectedAudience! > 10000000)) {
          return 'event_wizard_invalid_audience';
        }
        final cur = priceCurrency.trim().toUpperCase();
        if (cur.isNotEmpty &&
            (cur.length != 3 || !RegExp(r'^[A-Z]{3}$').hasMatch(cur))) {
          return 'event_wizard_invalid_currency';
        }
        return null;
      case 3:
        final totalPhotos = photoUrls.length + pendingPhotoPaths.length;
        if (totalPhotos > 5) return 'max_5_photos';
        return null;
      case 4:
        for (final s in schedule) {
          if (s.title.trim().isEmpty) {
            return 'event_wizard_schedule_title_required';
          }
        }
        for (final a in attractions) {
          if (a.name.trim().isEmpty) {
            return 'event_wizard_attraction_name_required';
          }
        }
        if (schedule.length > 40) return 'event_wizard_schedule_too_many';
        if (attractions.length > 30) {
          return 'event_wizard_attractions_too_many';
        }
        return null;
      case 5:
        if (publicContact.trim().isNotEmpty && !publicContactConsent) {
          return 'event_wizard_contact_consent_required';
        }
        final web = websiteUrl.trim();
        if (web.isNotEmpty && !web.toLowerCase().startsWith('https://')) {
          return 'event_wizard_invalid_url';
        }
        final tUrl = ticketUrl.trim();
        if (tUrl.isNotEmpty && !tUrl.toLowerCase().startsWith('https://')) {
          return 'event_wizard_invalid_url';
        }
        return null;
      case 6:
        for (var i = 0; i < 6; i++) {
          final err = validateStep(i);
          if (err != null) return err;
        }
        return null;
      default:
        return null;
    }
  }

  bool get isValidForSubmit => validateStep(6) == null;

  DateTime startAtUtc() {
    final hm = parseHm(startTime);
    final d = startDate;
    if (d == null || hm == null) {
      throw StateError('missing_start');
    }
    return EventTimezone.wallToUtc(
      year: d.year,
      month: d.month,
      day: d.day,
      hour: hm[0],
      minute: hm[1],
      timeZone: eventTimeZone,
    );
  }

  DateTime endAtUtc() {
    final hm = parseHm(endTime);
    final d = endDate;
    if (d == null || hm == null) {
      throw StateError('missing_end');
    }
    return EventTimezone.wallToUtc(
      year: d.year,
      month: d.month,
      day: d.day,
      hour: hm[0],
      minute: hm[1],
      timeZone: eventTimeZone,
    );
  }

  List<Map<String, dynamic>> _orderedScheduleJson() {
    final items = [...schedule]..sort((a, b) => a.order.compareTo(b.order));
    return [
      for (var i = 0; i < items.length; i++)
        items[i].copyWith(order: i).toJson(),
    ];
  }

  List<Map<String, dynamic>> _orderedAttractionsJson() {
    final items = [...attractions]..sort((a, b) => a.order.compareTo(b.order));
    return [
      for (var i = 0; i < items.length; i++)
        items[i].copyWith(order: i).toJson(),
    ];
  }

  Map<String, dynamic> _editorialFields({
    required bool includeEmptyOptionals,
  }) {
    final cityTrim = city.trim();
    final cityKeyOut =
        cityKey.trim().isNotEmpty ? cityKey.trim() : cityTrim.toLowerCase();
    final ticket = ticketType.trim().toLowerCase();
    final free = ticket == 'free' || (ticket.isEmpty && isFree);

    final map = <String, dynamic>{
      'title': title.trim(),
      'description': description.trim(),
      'shortDescription': shortDescription.trim(),
      'category': category.trim(),
      'subcategories': subcategories,
      'primaryLanguage': primaryLanguage.trim(),
      'startAtMs': startAtUtc().millisecondsSinceEpoch,
      'endAtMs': endAtUtc().millisecondsSinceEpoch,
      'eventTimeZone': eventTimeZone.trim(),
      'city': cityTrim,
      'cityKey': cityKeyOut,
      'stateName': stateName.trim(),
      'placeName': placeName.trim(),
      'address': address.trim(),
      'placeDisplay':
          placeDisplay.trim().isNotEmpty ? placeDisplay.trim() : placeName.trim(),
      'countryCode': countryCode.trim().toLowerCase(),
      'regionKey': regionKey.trim().isNotEmpty
          ? regionKey.trim()
          : _regionFromCity(cityTrim),
      'scope': scope.trim().isNotEmpty ? scope.trim() : 'city',
      'placeId': placeId.trim(),
      'lat': lat,
      'lng': lng,
      'sponsorInterested': sponsorInterested,
      'ticketType': free ? 'free' : ticket,
      'isFree': free,
      'price': price.trim(),
      'priceCurrency': priceCurrency.trim().toUpperCase(),
      'ticketUrl': ticketUrl.trim(),
      'ticketInfo': ticketInfo.trim(),
      'expectedAudience': expectedAudience,
      'schedule': _orderedScheduleJson(),
      'attractions': _orderedAttractionsJson(),
      'accessibility': accessibility.trim(),
      'parking': parking.trim(),
      'foodInfo': foodInfo.trim(),
      'ageRating': ageRating.trim(),
      'entryPolicy': entryPolicy.trim(),
      'publicContact': publicContact.trim(),
      'publicContactConsent': publicContactConsent,
      'websiteUrl': websiteUrl.trim(),
      'publicNotes': publicNotes.trim(),
    };

    if (coverUrl.trim().isNotEmpty || includeEmptyOptionals) {
      map['coverUrl'] = coverUrl.trim();
    }
    if (photoUrls.isNotEmpty || includeEmptyOptionals) {
      map['photoUrls'] = photoUrls;
    }
    if (logoUrl.trim().isNotEmpty || includeEmptyOptionals) {
      map['logoUrl'] = logoUrl.trim();
    }

    if (!includeEmptyOptionals) {
      map.removeWhere((key, value) {
        if (value == null) return true;
        if (value is String && value.isEmpty) {
          return !const {
            'shortDescription',
            'stateName',
            'address',
            'placeDisplay',
            'placeId',
            'regionKey',
            'primaryLanguage',
            'price',
            'priceCurrency',
            'ticketUrl',
            'ticketInfo',
            'accessibility',
            'parking',
            'foodInfo',
            'ageRating',
            'entryPolicy',
            'publicContact',
            'websiteUrl',
            'publicNotes',
            'coverUrl',
            'logoUrl',
          }.contains(key);
        }
        return false;
      });
    }

    return map;
  }

  /// Payload editorial para createEvent (sem requestId).
  Map<String, dynamic> toCreateCallablePayload() {
    return _editorialFields(includeEmptyOptionals: false);
  }

  /// Payload editorial para updateEvent (sem eventId).
  Map<String, dynamic> toUpdateCallablePayload({bool full = true}) {
    return _editorialFields(includeEmptyOptionals: full);
  }

  static String _regionFromCity(String city) {
    final c = city.toLowerCase();
    if (c.contains('toronto') ||
        c.contains('north york') ||
        c.contains('york') ||
        c.contains('scarborough') ||
        c.contains('etobicoke') ||
        c.contains('mississauga') ||
        c.contains('brampton')) {
      return 'gta';
    }
    if (c.contains('ottawa')) return 'ottawa';
    return 'default';
  }
}
