import '../models/place_listing.dart';

class PlaceQuery {
  const PlaceQuery({
    this.search = '',
    this.category,
    this.openNow = false,
    this.minRating,
    this.wheelchairEntrance = false,
  });

  /// Cidade, região, bairro ou nome. Sem acento e sem diferenciar maiúsculas.
  final String search;
  final PlaceCategory? category;
  final bool openNow;
  final double? minRating;
  final bool wheelchairEntrance;

  PlaceQuery copyWith({
    String? search,
    PlaceCategory? category,
    bool clearCategory = false,
    bool? openNow,
    double? minRating,
    bool clearMinRating = false,
    bool? wheelchairEntrance,
  }) {
    return PlaceQuery(
      search: search ?? this.search,
      category: clearCategory ? null : (category ?? this.category),
      openNow: openNow ?? this.openNow,
      minRating: clearMinRating ? null : (minRating ?? this.minRating),
      wheelchairEntrance: wheelchairEntrance ?? this.wheelchairEntrance,
    );
  }
}

class PlaceQueryEngine {
  const PlaceQueryEngine();

  List<PlaceListing> apply({
    required List<PlaceListing> source,
    required PlaceQuery query,
    required DateTime now,
  }) {
    final needle = _fold(query.search.trim());
    return source.where((place) {
      if (query.category != null && place.category != query.category) {
        return false;
      }
      if (query.openNow && !place.isOpenAt(now)) return false;
      if (query.minRating != null && place.rating < query.minRating!) {
        return false;
      }
      if (query.wheelchairEntrance && !place.accessibility.wheelchairEntrance) {
        return false;
      }
      if (needle.isEmpty) return true;
      final haystack = _fold(
        [
          place.name,
          place.address.city,
          place.address.region,
          place.address.district,
        ].join(' '),
      );
      return haystack.contains(needle);
    }).toList(growable: false);
  }
}

String _fold(String value) {
  const pairs = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
  };
  final buffer = StringBuffer();
  for (final char in value.toLowerCase().split('')) {
    buffer.write(pairs[char] ?? char);
  }
  return buffer.toString();
}
