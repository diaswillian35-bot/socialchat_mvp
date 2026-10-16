/// Contrato público `places.v1`, o mesmo documento que o portal web do
/// comerciante passará a publicar. Esta etapa só lê JSON local; não há
/// escrita, Firebase nem credencial.
class PlaceContract {
  PlaceContract._();

  static const String version = 'places.v1';
  static final RegExp idPattern = RegExp(r'^[a-z0-9_]{3,64}$');
  static final RegExp slugPattern = RegExp(r'^[a-z0-9-]{3,80}$');
}

class PlaceContractException implements Exception {
  const PlaceContractException(this.message);
  final String message;

  @override
  String toString() => 'PlaceContractException: $message';
}

enum PlaceCategory {
  restaurant,
  bar,
  cafe,
  hotel,
  pousada,
  nightclub;

  static PlaceCategory parse(Object? raw) {
    final value = raw?.toString().trim() ?? '';
    for (final category in PlaceCategory.values) {
      if (category.name == value) return category;
    }
    throw const PlaceContractException('unknown category');
  }
}

class PlacePhoto {
  const PlacePhoto({
    required this.id,
    required this.alt,
    required this.color,
    this.url,
  });

  final String id;
  final String alt;
  final int color;

  /// URL https opcional do portal. Esta etapa não faz download.
  final String? url;

  Map<String, dynamic> toPortalJson() => {
        'id': id,
        'alt': alt,
        'color': color,
        if (url != null) 'url': url,
      };

  static PlacePhoto fromPortalJson(Map<String, dynamic> json) {
    final id = _reqString(json, 'id');
    final alt = _reqString(json, 'alt');
    final color = json['color'];
    if (color is! int) {
      throw const PlaceContractException('photo color');
    }
    final url = _optionalHttps(json['url'], 'photo url');
    return PlacePhoto(id: id, alt: alt, color: color, url: url);
  }
}

class PlaceAddress {
  const PlaceAddress({
    required this.line1,
    required this.district,
    required this.city,
    required this.region,
    required this.countryCode,
    required this.postalCode,
    required this.latitude,
    required this.longitude,
  });

  final String line1;
  final String district;
  final String city;
  final String region;
  final String countryCode;
  final String postalCode;
  final double latitude;
  final double longitude;

  String get singleLine => '$line1, $district, $city, $region';

  Map<String, dynamic> toPortalJson() => {
        'line1': line1,
        'district': district,
        'city': city,
        'region': region,
        'countryCode': countryCode,
        'postalCode': postalCode,
        'latitude': latitude,
        'longitude': longitude,
      };

  static PlaceAddress fromPortalJson(Map<String, dynamic> json) {
    final country = _reqString(json, 'countryCode').toUpperCase();
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(country)) {
      throw const PlaceContractException('countryCode');
    }
    final lat = _reqDouble(json, 'latitude');
    final lng = _reqDouble(json, 'longitude');
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      throw const PlaceContractException('coordinates');
    }
    return PlaceAddress(
      line1: _reqString(json, 'line1'),
      district: _reqString(json, 'district'),
      city: _reqString(json, 'city'),
      region: _reqString(json, 'region'),
      countryCode: country,
      postalCode: _reqString(json, 'postalCode'),
      latitude: lat,
      longitude: lng,
    );
  }
}

class PlaceContact {
  const PlaceContact({this.phone, this.whatsapp, this.website, this.instagram});

  final String? phone;
  final String? whatsapp;
  final String? website;
  final String? instagram;

  Map<String, dynamic> toPortalJson() => {
        if (phone != null) 'phone': phone,
        if (whatsapp != null) 'whatsapp': whatsapp,
        if (website != null) 'website': website,
        if (instagram != null) 'instagram': instagram,
      };

  static PlaceContact fromPortalJson(Map<String, dynamic> json) {
    return PlaceContact(
      phone: _optionalString(json['phone']),
      whatsapp: _optionalString(json['whatsapp']),
      website: _optionalHttps(json['website'], 'website'),
      instagram: _optionalString(json['instagram']),
    );
  }
}

class PlaceHours {
  const PlaceHours({
    required this.weekday,
    required this.opens,
    required this.closes,
  });

  /// 1 = segunda … 7 = domingo, igual a [DateTime.weekday].
  final int weekday;
  final String opens;
  final String closes;

  int get opensMinutes => _parseClock(opens);
  int get closesMinutes => _parseClock(closes);

  bool containsMinute(int minuteOfDay) {
    final start = opensMinutes;
    final end = closesMinutes;
    if (start == end) return false;
    if (end > start) return minuteOfDay >= start && minuteOfDay < end;
    return minuteOfDay >= start || minuteOfDay < end;
  }

  Map<String, dynamic> toPortalJson() => {
        'weekday': weekday,
        'opens': opens,
        'closes': closes,
      };

  static PlaceHours fromPortalJson(Map<String, dynamic> json) {
    final weekday = json['weekday'];
    if (weekday is! int || weekday < 1 || weekday > 7) {
      throw const PlaceContractException('weekday');
    }
    final opens = _reqString(json, 'opens');
    final closes = _reqString(json, 'closes');
    _parseClock(opens);
    _parseClock(closes);
    return PlaceHours(weekday: weekday, opens: opens, closes: closes);
  }
}

class PlaceAccessibility {
  const PlaceAccessibility({
    required this.wheelchairEntrance,
    required this.stepFree,
    required this.accessibleRestroom,
    this.notes = '',
  });

  final bool wheelchairEntrance;
  final bool stepFree;
  final bool accessibleRestroom;
  final String notes;

  Map<String, dynamic> toPortalJson() => {
        'wheelchairEntrance': wheelchairEntrance,
        'stepFree': stepFree,
        'accessibleRestroom': accessibleRestroom,
        'notes': notes,
      };

  static PlaceAccessibility fromPortalJson(Map<String, dynamic> json) {
    return PlaceAccessibility(
      wheelchairEntrance: _reqBool(json, 'wheelchairEntrance'),
      stepFree: _reqBool(json, 'stepFree'),
      accessibleRestroom: _reqBool(json, 'accessibleRestroom'),
      notes: _optionalString(json['notes']) ?? '',
    );
  }
}

class PlaceReview {
  const PlaceReview({
    required this.id,
    required this.authorName,
    required this.rating,
    required this.comment,
    required this.createdAt,
    this.ownerReply,
  });

  final String id;
  final String authorName;
  final int rating;
  final String comment;
  final String createdAt;
  final PlaceOwnerReply? ownerReply;

  Map<String, dynamic> toPortalJson() => {
        'id': id,
        'authorName': authorName,
        'rating': rating,
        'comment': comment,
        'createdAt': createdAt,
        if (ownerReply != null) 'ownerReply': ownerReply!.toJson(),
      };

  static PlaceReview fromPortalJson(Map<String, dynamic> json) {
    final rating = json['rating'];
    if (rating is! int || rating < 1 || rating > 5) {
      throw const PlaceContractException('review rating');
    }
    return PlaceReview(
      id: _reqString(json, 'id'),
      authorName: _reqString(json, 'authorName'),
      rating: rating,
      comment: _reqString(json, 'comment'),
      createdAt: _reqString(json, 'createdAt'),
      ownerReply: PlaceOwnerReply.tryParse(json['ownerReply']),
    );
  }
}

class PlaceOwnerReply {
  const PlaceOwnerReply({required this.text, required this.createdAt});
  final String text;
  final String createdAt;

  Map<String, dynamic> toJson() => {'text': text, 'createdAtIso': createdAt};

  static PlaceOwnerReply? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text']?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return PlaceOwnerReply(
      text: text,
      createdAt: raw['createdAtIso']?.toString().trim() ?? '',
    );
  }
}

class PlaceMenuItem {
  const PlaceMenuItem({
    required this.name,
    required this.description,
    required this.price,
    required this.available,
  });

  final String name;
  final String description;
  final String price;
  final bool available;
}

class PlaceMenu {
  const PlaceMenu({
    required this.enabled,
    required this.photoUrls,
    required this.items,
    this.pdfUrl,
    this.notice = '',
  });

  final bool enabled;
  final List<String> photoUrls;
  final String? pdfUrl;
  final List<PlaceMenuItem> items;
  final String notice;

  static const disabled = PlaceMenu(
    enabled: false,
    photoUrls: [],
    items: [],
  );
}

class PlaceUpcomingEvent {
  const PlaceUpcomingEvent({
    required this.id,
    required this.title,
    required this.startsAt,
    this.note = '',
  });

  final String id;
  final String title;
  final String startsAt;
  final String note;

  Map<String, dynamic> toPortalJson() => {
        'id': id,
        'title': title,
        'startsAt': startsAt,
        if (note.isNotEmpty) 'note': note,
      };

  static PlaceUpcomingEvent fromPortalJson(Map<String, dynamic> json) {
    return PlaceUpcomingEvent(
      id: _reqString(json, 'id'),
      title: _reqString(json, 'title'),
      startsAt: _reqString(json, 'startsAt'),
      note: _optionalString(json['note']) ?? '',
    );
  }
}

class PlaceListing {
  const PlaceListing({
    required this.id,
    required this.slug,
    required this.name,
    required this.category,
    required this.description,
    required this.photos,
    required this.rating,
    required this.ratingCount,
    required this.address,
    required this.contact,
    required this.hours,
    required this.accessibility,
    required this.reviews,
    required this.upcomingEvents,
    this.menu = PlaceMenu.disabled,
  });

  final String id;
  final String slug;
  final String name;
  final PlaceCategory category;
  final String description;
  final List<PlacePhoto> photos;
  final double rating;
  final int ratingCount;
  final PlaceAddress address;
  final PlaceContact contact;
  final List<PlaceHours> hours;
  final PlaceAccessibility accessibility;
  final List<PlaceReview> reviews;
  final List<PlaceUpcomingEvent> upcomingEvents;
  final PlaceMenu menu;

  PlacePhoto get cover => photos.first;

  PlaceListing copyWith({List<PlaceReview>? reviews}) => PlaceListing(
        id: id,
        slug: slug,
        name: name,
        category: category,
        description: description,
        photos: photos,
        rating: rating,
        ratingCount: ratingCount,
        address: address,
        contact: contact,
        hours: hours,
        accessibility: accessibility,
        reviews: reviews ?? this.reviews,
        upcomingEvents: upcomingEvents,
        menu: menu,
      );

  bool isOpenAt(DateTime instant) {
    final minute = instant.hour * 60 + instant.minute;
    for (final slot in hours) {
      if (slot.weekday == instant.weekday && slot.containsMinute(minute)) {
        return true;
      }
    }
    return false;
  }

  Map<String, dynamic> toPortalJson() => {
        'contract': PlaceContract.version,
        'id': id,
        'slug': slug,
        'name': name,
        'category': category.name,
        'description': description,
        'photos': photos.map((photo) => photo.toPortalJson()).toList(),
        'rating': rating,
        'ratingCount': ratingCount,
        'address': address.toPortalJson(),
        'contact': contact.toPortalJson(),
        'hours': hours.map((slot) => slot.toPortalJson()).toList(),
        'accessibility': accessibility.toPortalJson(),
        'reviews': reviews.map((review) => review.toPortalJson()).toList(),
        'upcomingEvents':
            upcomingEvents.map((event) => event.toPortalJson()).toList(),
      };

  static PlaceListing fromPortalJson(Map<String, dynamic> json) {
    if (json['contract'] != PlaceContract.version) {
      throw const PlaceContractException('unsupported contract');
    }
    final id = _reqString(json, 'id');
    final slug = _reqString(json, 'slug');
    if (!PlaceContract.idPattern.hasMatch(id)) {
      throw const PlaceContractException('id');
    }
    if (!PlaceContract.slugPattern.hasMatch(slug)) {
      throw const PlaceContractException('slug');
    }
    final photosRaw = json['photos'];
    if (photosRaw is! List || photosRaw.isEmpty) {
      throw const PlaceContractException('photos');
    }
    final rating = _reqDouble(json, 'rating');
    if (rating < 0 || rating > 5) {
      throw const PlaceContractException('rating');
    }
    final ratingCount = json['ratingCount'];
    if (ratingCount is! int || ratingCount < 0) {
      throw const PlaceContractException('ratingCount');
    }
    final addressRaw = json['address'];
    final contactRaw = json['contact'];
    final hoursRaw = json['hours'];
    final accessRaw = json['accessibility'];
    if (addressRaw is! Map ||
        contactRaw is! Map ||
        hoursRaw is! List ||
        accessRaw is! Map) {
      throw const PlaceContractException('listing shape');
    }
    return PlaceListing(
      id: id,
      slug: slug,
      name: _reqString(json, 'name'),
      category: PlaceCategory.parse(json['category']),
      description: _reqString(json, 'description'),
      photos: photosRaw
          .map((item) => PlacePhoto.fromPortalJson(_asMap(item, 'photo')))
          .toList(),
      rating: rating,
      ratingCount: ratingCount,
      address: PlaceAddress.fromPortalJson(_asMap(addressRaw, 'address')),
      contact: PlaceContact.fromPortalJson(_asMap(contactRaw, 'contact')),
      hours: hoursRaw
          .map((item) => PlaceHours.fromPortalJson(_asMap(item, 'hours')))
          .toList(),
      accessibility: PlaceAccessibility.fromPortalJson(
        _asMap(accessRaw, 'accessibility'),
      ),
      reviews: _mapList(json['reviews'], 'review', PlaceReview.fromPortalJson),
      upcomingEvents: _mapList(
        json['upcomingEvents'],
        'event',
        PlaceUpcomingEvent.fromPortalJson,
      ),
    );
  }
}

int _parseClock(String value) {
  final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(value);
  if (match == null) throw const PlaceContractException('clock');
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) {
    throw const PlaceContractException('clock');
  }
  return hour * 60 + minute;
}

String _reqString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw PlaceContractException(key);
  }
  return value.trim();
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const PlaceContractException('string');
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _optionalHttps(Object? value, String label) {
  final text = _optionalString(value);
  if (text == null) return null;
  final uri = Uri.tryParse(text);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw PlaceContractException(label);
  }
  return text;
}

bool _reqBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw PlaceContractException(key);
  return value;
}

double _reqDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value.toDouble();
  if (value is double) return value;
  throw PlaceContractException(key);
}

Map<String, dynamic> _asMap(Object? value, String label) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  throw PlaceContractException(label);
}

List<T> _mapList<T>(
  Object? raw,
  String label,
  T Function(Map<String, dynamic> json) parse,
) {
  if (raw == null) return const [];
  if (raw is! List) throw PlaceContractException(label);
  return raw.map((item) => parse(_asMap(item, label))).toList();
}
