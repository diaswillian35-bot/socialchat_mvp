import '../models/place_listing.dart';

/// Adaptador único entre `remdy.places.v1` (portal/Admin) e a apresentação do
/// aplicativo. Nenhuma coleção paralela é criada pelo cliente.
class FirestorePlaceMapper {
  FirestorePlaceMapper._();

  static const String contractVersion = 'remdy.places.v1';

  static PlaceListing? tryParse(String documentId, Map<String, dynamic> data) {
    if (!_isPublic(data)) return null;
    try {
      final photos = _photos(data);
      if (photos.isEmpty) return null;
      final latitude = _double(data['latitude']);
      final longitude = _double(data['longitude']);
      if (latitude == null || longitude == null) return null;
      final rating = _rating(data);
      return PlaceListing(
        id: documentId,
        slug: _text(data['slug'], fallback: documentId),
        name: _required(data['name']),
        category: PlaceCategory.parse(data['category']),
        description: _text(data['description']),
        photos: photos,
        rating: rating.average,
        ratingCount: rating.count,
        address: PlaceAddress(
          line1: _text(data['addressLine']),
          district: _text(data['district']),
          city: _required(data['cityName']),
          region: _text(data['stateName'], fallback: _text(data['stateCode'])),
          countryCode: _text(data['countryCode'], fallback: 'BR').toUpperCase(),
          postalCode: _text(data['postalCode']),
          latitude: latitude,
          longitude: longitude,
        ),
        contact: PlaceContact(
          phone: _nullable(data['phone']),
          whatsapp: _nullable(data['whatsapp']),
          website: _safeHttps(data['websiteUrl']),
          instagram: _safeHttps(data['instagramUrl']) ??
              _nullable(data['instagramUrl']),
        ),
        hours: _hours(data),
        accessibility: PlaceAccessibility(
          wheelchairEntrance: data['wheelchairEntrance'] == true,
          stepFree: data['stepFree'] == true,
          accessibleRestroom: data['accessibleRestroom'] == true,
          notes: _text(data['accessibilityNote']),
        ),
        reviews: _embeddedReviews(data),
        upcomingEvents: _events(data),
        menu: _menu(data),
      );
    } catch (_) {
      return null;
    }
  }

  static PlaceReview? tryParseReview(
    String documentId,
    Map<String, dynamic> data,
  ) {
    if (data['status'] != 'approved' && data['status'] != 'published') {
      return null;
    }
    final stars = _int(data['stars']);
    if (stars == null || stars < 1 || stars > 5) return null;
    return PlaceReview(
      id: _text(data['publicId'], fallback: documentId),
      authorName: _text(data['authorDisplayName'], fallback: 'Visitante'),
      rating: stars,
      comment: _text(data['comment']),
      createdAt: _text(data['createdAtIso']),
      ownerReply: _reply(data['ownerReply']),
    );
  }

  static bool _isPublic(Map<String, dynamic> data) {
    return data['contractVersion'] == contractVersion &&
        data['moderationStatus'] == 'published' &&
        data['active'] == true &&
        data['deleted'] != true;
  }

  static List<PlacePhoto> _photos(Map<String, dynamic> data) {
    final result = <PlacePhoto>[];
    final cover = _safeHttps(data['coverUrl']);
    if (cover != null) {
      result.add(
        PlacePhoto(
          id: 'cover',
          alt: _text(data['name']),
          color: 0xFF3157A4,
          url: cover,
        ),
      );
    }
    final raw = data['photoUrls'];
    if (raw is List) {
      for (final value in raw) {
        final url = _safeHttps(value);
        if (url == null || result.any((photo) => photo.url == url)) continue;
        result.add(
          PlacePhoto(
            id: 'photo_${result.length}',
            alt: _text(data['name']),
            color: 0xFF3157A4,
            url: url,
          ),
        );
        if (result.length == 7) {
          break;
        }
      }
    }
    return result;
  }

  static _RatingValue _rating(Map<String, dynamic> data) {
    final summary = data['rating'];
    if (summary is Map) {
      final average = _double(summary['average']) ?? 0;
      final count = _int(summary['count']) ?? 0;
      return _RatingValue(
          average.clamp(0, 5).toDouble(), count < 0 ? 0 : count);
    }
    return _RatingValue(
      (_double(data['averageRating']) ?? 0).clamp(0, 5).toDouble(),
      _int(data['reviewCount']) ?? 0,
    );
  }

  static List<PlaceHours> _hours(Map<String, dynamic> data) {
    final result = <PlaceHours>[];
    final note = _text(data['hoursNote']);
    final match = RegExp(r'^(\d{2}:\d{2})-(\d{2}:\d{2})$').firstMatch(note);
    if (match == null) return result;
    for (var day = 1; day <= 7; day++) {
      result.add(
        PlaceHours(
          weekday: day,
          opens: match.group(1)!,
          closes: match.group(2)!,
        ),
      );
    }
    return result;
  }

  static List<PlaceReview> _embeddedReviews(Map<String, dynamic> data) {
    final raw = data['reviews'];
    if (raw is! List) return const [];
    final result = <PlaceReview>[];
    for (final item in raw) {
      if (item is! Map ||
          (item['status'] != 'approved' && item['status'] != 'published')) {
        continue;
      }
      final stars = _int(item['stars']);
      if (stars == null || stars < 1 || stars > 5) {
        continue;
      }
      result.add(
        PlaceReview(
          id: _text(item['publicId'], fallback: 'review_${result.length}'),
          authorName: _text(item['authorDisplayName'], fallback: 'Visitante'),
          rating: stars,
          comment: _text(item['comment']),
          createdAt: _text(item['createdAtIso']),
          ownerReply: _reply(item['ownerReply']),
        ),
      );
    }
    return result;
  }

  static List<PlaceUpcomingEvent> _events(Map<String, dynamic> data) {
    final raw = data['upcomingEvents'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => PlaceUpcomingEvent(
            id: _text(item['id']),
            title: _text(item['title']),
            startsAt: _text(item['startsAtIso']),
          ),
        )
        .where((event) => event.id.isNotEmpty && event.title.isNotEmpty)
        .toList();
  }

  static PlaceMenu _menu(Map<String, dynamic> data) {
    final raw = data['menu'];
    if (raw is! Map || raw['enabled'] != true) return PlaceMenu.disabled;
    final category = _text(data['category']);
    if (category != 'restaurant' && category != 'bar' && category != 'cafe') {
      return PlaceMenu.disabled;
    }
    final photos =
        (raw['photoUrls'] is List ? raw['photoUrls'] as List : const [])
            .map(_safeHttps)
            .whereType<String>()
            .take(6)
            .toList();
    final items = <PlaceMenuItem>[];
    if (raw['items'] is List) {
      for (final item in raw['items'] as List) {
        if (item is! Map) continue;
        final name = _text(item['name']);
        if (name.isEmpty) continue;
        items.add(PlaceMenuItem(
          name: name,
          description: _text(item['description']),
          price: _text(item['price']),
          available: item['available'] != false,
        ));
        if (items.length == 60) break;
      }
    }
    final pdf = _safeHttps(raw['pdfUrl']);
    return PlaceMenu(
      enabled: photos.isNotEmpty || pdf != null || items.isNotEmpty,
      photoUrls: photos,
      pdfUrl: pdf,
      items: items,
      notice: _text(raw['notice']),
    );
  }

  static PlaceOwnerReply? _reply(Object? raw) {
    if (raw is! Map) return null;
    final text = _text(raw['text']);
    if (text.isEmpty) return null;
    return PlaceOwnerReply(text: text, createdAt: _text(raw['createdAtIso']));
  }

  static String _required(Object? value) {
    final text = _text(value);
    if (text.isEmpty) throw const PlaceContractException('required');
    return text;
  }

  static String _text(Object? value, {String fallback = ''}) =>
      value is String && value.trim().isNotEmpty ? value.trim() : fallback;
  static String? _nullable(Object? value) {
    final text = _text(value);
    return text.isEmpty ? null : text;
  }

  static String? _safeHttps(Object? value) {
    final text = _nullable(value);
    if (text == null) return null;
    final uri = Uri.tryParse(text);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
        ? text
        : null;
  }

  static double? _double(Object? value) => value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  static int? _int(Object? value) =>
      value is int ? value : int.tryParse(value?.toString() ?? '');
}

class _RatingValue {
  const _RatingValue(this.average, this.count);
  final double average;
  final int count;
}
