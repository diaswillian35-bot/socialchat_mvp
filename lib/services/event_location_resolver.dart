import 'package:cloud_firestore/cloud_firestore.dart';

import 'event_address_parts.dart';

/// Destino público resolvido a partir do documento do evento (somente leitura).
///
/// Ordem canônica:
/// 1) coordenadas públicas válidas;
/// 2) endereço público (com número quando existir);
/// 3) nome do local + cidade + estado + país.
/// Nunca usa endereço residencial do organizador.
class EventPublicDestination {
  const EventPublicDestination({
    required this.placeName,
    required this.address,
    required this.city,
    required this.stateName,
    required this.countryCode,
    required this.countryName,
    required this.lat,
    required this.lng,
    required this.placeId,
    this.street = '',
    this.streetNumber = '',
    this.noStreetNumber = false,
    this.addressComplement = '',
    this.district = '',
    this.postalCode = '',
  });

  final String placeName;
  final String address;
  final String city;
  final String stateName;
  final String countryCode;
  final String countryName;
  final double? lat;
  final double? lng;
  final String placeId;
  final String street;
  final String streetNumber;
  final bool noStreetNumber;
  final String addressComplement;
  final String district;
  final String postalCode;

  bool get hasValidCoords => EventLocationResolver.validCoords(lat, lng);

  /// Query textual para Maps quando não há coordenadas confiáveis.
  String get mapsQuery {
    final composed = address.trim().isNotEmpty
        ? address
        : EventAddressParts(
            street: street,
            streetNumber: streetNumber,
            noStreetNumber: noStreetNumber,
            addressComplement: addressComplement,
            district: district,
            city: city,
            stateName: stateName,
            postalCode: postalCode,
            countryCode: countryCode,
            countryName: countryName,
          ).composePublicAddress();

    final country =
        countryName.isNotEmpty ? countryName : countryCode.toUpperCase();
    final lower = composed.toLowerCase();
    bool missing(String value) {
      final v = value.trim();
      if (v.isEmpty) return false;
      return !lower.contains(v.toLowerCase());
    }

    final parts = <String>[
      placeName,
      composed,
      if (missing(city)) city,
      if (missing(stateName)) stateName,
      if (missing(country)) country,
    ].where((e) => e.trim().isNotEmpty).map((e) => e.trim()).toList();

    final out = <String>[];
    for (final p in parts) {
      if (out.any((e) => e.toLowerCase() == p.toLowerCase())) continue;
      out.add(p);
    }
    return out.join(', ');
  }

  bool get hasValidDestination =>
      hasValidCoords || mapsQuery.trim().isNotEmpty;
}

/// Parsing único de localização pública do evento (app / portal / legado).
class EventLocationResolver {
  EventLocationResolver._();

  static EventPublicDestination fromEventMap(Map<String, dynamic> data) {
    final nested = _asStringKeyedMap(data['location']);
    final parts = EventAddressParts.fromEventMap(data);

    final lat = _coord(
      data['lat'] ??
          data['latitude'] ??
          nested?['lat'] ??
          nested?['latitude'] ??
          data['geoPoint'] ??
          nested?['geoPoint'] ??
          data['geo'],
      isLat: true,
    );
    final lng = _coord(
      data['lng'] ??
          data['longitude'] ??
          nested?['lng'] ??
          nested?['longitude'] ??
          data['geoPoint'] ??
          nested?['geoPoint'] ??
          data['geo'],
      isLat: false,
    );

    final geo = data['geoPoint'] ?? nested?['geoPoint'] ?? data['geo'];
    final geoLatLng = _fromGeoPoint(geo);

    final structured = parts.composePublicAddress();
    final legacy = firstNonEmpty([
      data['publicAddress'],
      data['address'],
      data['fullAddress'],
      data['placeDisplay'],
      nested?['address'],
      nested?['fullAddress'],
    ]);
    // Prefer endereço estruturado (com número) quando street existir.
    final address = parts.street.trim().isNotEmpty ? structured : legacy;
    final addressOrStructured =
        address.isNotEmpty ? address : structured;

    return EventPublicDestination(
      placeName: firstNonEmpty([
        data['placeName'],
        data['venue'],
        data['venueName'],
        data['locationName'],
        nested?['placeName'],
        nested?['name'],
        data['placeDisplay'],
      ]),
      address: addressOrStructured,
      city: parts.city,
      stateName: parts.stateName,
      countryCode: parts.countryCode,
      countryName: parts.countryName,
      lat: lat ?? (geoLatLng == null ? null : geoLatLng[0]),
      lng: lng ?? (geoLatLng == null ? null : geoLatLng[1]),
      placeId: firstNonEmpty([
        data['placeId'],
        nested?['placeId'],
      ]),
      street: parts.street,
      streetNumber: parts.streetNumber,
      noStreetNumber: parts.noStreetNumber,
      addressComplement: parts.addressComplement,
      district: parts.district,
      postalCode: parts.postalCode,
    );
  }

  /// Primeiro texto não vazio (trata `''` como ausente — diferente de `??`).
  static String firstNonEmpty(Iterable<dynamic> values) {
    for (final v in values) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static bool validCoords(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (!lat.isFinite || !lng.isFinite) return false;
    if (lat < -90 || lat > 90) return false;
    if (lng < -180 || lng > 180) return false;
    if (lat.abs() < 0.000001 && lng.abs() < 0.000001) return false;
    return true;
  }

  static double? parseCoordinate(dynamic value) {
    if (value == null) return null;
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String) {
      final t = value.trim().replaceAll(',', '.');
      if (t.isEmpty) return null;
      return double.tryParse(t);
    }
    return null;
  }

  static double? _coord(dynamic value, {required bool isLat}) {
    if (value is GeoPoint) {
      return isLat ? value.latitude : value.longitude;
    }
    if (value is Map) {
      final m = _asStringKeyedMap(value);
      if (m != null) {
        if (isLat) {
          return parseCoordinate(m['lat'] ?? m['latitude']);
        }
        return parseCoordinate(m['lng'] ?? m['longitude']);
      }
    }
    return parseCoordinate(value);
  }

  static List<double>? _fromGeoPoint(dynamic value) {
    if (value is GeoPoint) {
      return <double>[value.latitude, value.longitude];
    }
    return null;
  }

  static Map<String, dynamic>? _asStringKeyedMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }
}
