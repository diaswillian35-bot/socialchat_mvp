import 'dart:math' as math;

/// Geografia pública usada pela descoberta de grupos regionais.
///
/// As coordenadas representam centros canônicos de cidades, nunca a posição
/// atual ou o endereço residencial do usuário/criador.
class GroupGeo {
  GroupGeo._();

  static const double regionRadiusKm = 110;
  static const double earthRadiusKm = 6371.0088;
  static const int geohashPrecision = 3;

  /// Limite do operador Firestore `whereIn` por consulta.
  static const int whereInLimit = 30;

  static bool validLatitude(num? value) =>
      value != null && value.isFinite && value >= -90 && value <= 90;

  static bool validLongitude(num? value) =>
      value != null && value.isFinite && value >= -180 && value <= 180;

  static bool validCoordinates(num? latitude, num? longitude) =>
      validLatitude(latitude) && validLongitude(longitude);

  /// Distância ortodrômica (Haversine). O delta de longitude é normalizado,
  /// portanto funciona também ao cruzar a linha internacional de data.
  static double? distanceKm({
    required num? lat1,
    required num? lng1,
    required num? lat2,
    required num? lng2,
  }) {
    if (!validCoordinates(lat1, lng1) || !validCoordinates(lat2, lng2)) {
      return null;
    }

    final phi1 = _radians(lat1!.toDouble());
    final phi2 = _radians(lat2!.toDouble());
    final dPhi = _radians(lat2.toDouble() - lat1.toDouble());
    final dLngDegrees = _normalizeLongitudeDelta(
      lng2!.toDouble() - lng1!.toDouble(),
    );
    final dLambda = _radians(dLngDegrees);

    final sinLat = math.sin(dPhi / 2);
    final sinLng = math.sin(dLambda / 2);
    final a =
        sinLat * sinLat + math.cos(phi1) * math.cos(phi2) * sinLng * sinLng;
    final clamped = a.clamp(0.0, 1.0).toDouble();
    return 2 * earthRadiusKm * math.asin(math.sqrt(clamped));
  }

  static bool withinRegion({
    required num? userLat,
    required num? userLng,
    required num? centerLat,
    required num? centerLng,
    num radiusKm = regionRadiusKm,
  }) {
    if (!radiusKm.isFinite || radiusKm <= 0) return false;
    final distance = distanceKm(
      lat1: userLat,
      lng1: userLng,
      lat2: centerLat,
      lng2: centerLng,
    );
    return distance != null && distance <= radiusKm + 1e-9;
  }

  static String geohash(
    num? latitude,
    num? longitude, {
    int precision = geohashPrecision,
  }) {
    if (!validCoordinates(latitude, longitude) ||
        precision < 1 ||
        precision > 12) {
      return '';
    }

    const alphabet = '0123456789bcdefghjkmnpqrstuvwxyz';
    var latMin = -90.0;
    var latMax = 90.0;
    var lngMin = -180.0;
    var lngMax = 180.0;
    var evenBit = true;
    var bit = 0;
    var value = 0;
    final out = StringBuffer();

    while (out.length < precision) {
      if (evenBit) {
        final mid = (lngMin + lngMax) / 2;
        if (longitude!.toDouble() >= mid) {
          value = (value << 1) | 1;
          lngMin = mid;
        } else {
          value <<= 1;
          lngMax = mid;
        }
      } else {
        final mid = (latMin + latMax) / 2;
        if (latitude!.toDouble() >= mid) {
          value = (value << 1) | 1;
          latMin = mid;
        } else {
          value <<= 1;
          latMax = mid;
        }
      }
      evenBit = !evenBit;
      bit++;
      if (bit == 5) {
        out.write(alphabet[value]);
        bit = 0;
        value = 0;
      }
    }
    return out.toString();
  }

  /// Prefixo geohash (precisão 3) de todos os pontos amostrados na bounding
  /// box do raio. **Não** corta em 30 — o serviço fatura em lotes `whereIn`.
  /// Haversine continua sendo o filtro final de inclusão.
  static List<String> candidateGeohashes({
    required num? latitude,
    required num? longitude,
    num radiusKm = regionRadiusKm,
  }) {
    if (!validCoordinates(latitude, longitude) ||
        !radiusKm.isFinite ||
        radiusKm <= 0) {
      return const [];
    }

    final lat = latitude!.toDouble();
    final lng = longitude!.toDouble();
    final latDelta = radiusKm.toDouble() / 110.574;
    final cosLat = math.cos(_radians(lat)).abs();
    final lngDelta =
        radiusKm.toDouble() / (111.320 * math.max(cosLat, 0.000001));

    final minLat = math.max(-90.0, lat - latDelta);
    final maxLat = math.min(90.0, lat + latDelta);
    final cells = <String>{};

    // Passo 0,25° cobre células de precisão 3 (~1,2°–1,5°) com margem.
    const step = 0.25;
    if (lngDelta >= 180) {
      // Polo / caixa global em longitude: amostra o anel completo.
      for (var sampleLat = minLat; sampleLat <= maxLat + 1e-9; sampleLat += step) {
        for (var sampleLng = -180.0; sampleLng < 180.0; sampleLng += step) {
          cells.add(geohash(sampleLat, sampleLng));
        }
      }
    } else {
      for (var sampleLat = minLat; sampleLat <= maxLat + 1e-9; sampleLat += step) {
        for (var offset = -lngDelta; offset <= lngDelta + 1e-9; offset += step) {
          cells.add(geohash(sampleLat, _wrapLongitude(lng + offset)));
        }
        cells.add(geohash(sampleLat, _wrapLongitude(lng + lngDelta)));
        cells.add(geohash(sampleLat, _wrapLongitude(lng - lngDelta)));
      }
    }

    // Bordas cardeais, diagonais e centro (cobertura explícita do círculo).
    for (final bearingDeg in [
      0.0,
      45.0,
      90.0,
      135.0,
      180.0,
      225.0,
      270.0,
      315.0,
    ]) {
      for (final dist in [0.0, radiusKm.toDouble() / 2, radiusKm.toDouble()]) {
        final p = destinationPoint(
          latitude: lat,
          longitude: lng,
          distanceKm: dist,
          bearingDeg: bearingDeg,
        );
        cells.add(geohash(p.latitude, p.longitude));
      }
    }

    cells.remove('');
    final sorted = cells.toList()..sort();
    return sorted;
  }

  /// Fatias de no máximo [whereInLimit] para consultas Firestore.
  static List<List<String>> geohashBatches({
    required num? latitude,
    required num? longitude,
    num radiusKm = regionRadiusKm,
    int batchSize = whereInLimit,
  }) {
    final all = candidateGeohashes(
      latitude: latitude,
      longitude: longitude,
      radiusKm: radiusKm,
    );
    if (all.isEmpty || batchSize < 1) return const [];
    final out = <List<String>>[];
    for (var i = 0; i < all.length; i += batchSize) {
      final end = math.min(i + batchSize, all.length);
      out.add(all.sublist(i, end));
    }
    return out;
  }

  /// Destino a partir de um ponto (fórmula de navegação esférica).
  static GroupLatLng destinationPoint({
    required double latitude,
    required double longitude,
    required double distanceKm,
    required double bearingDeg,
  }) {
    final angular = distanceKm / earthRadiusKm;
    final bearing = _radians(bearingDeg);
    final lat1 = _radians(latitude);
    final lng1 = _radians(longitude);

    final sinLat1 = math.sin(lat1);
    final cosLat1 = math.cos(lat1);
    final sinAng = math.sin(angular);
    final cosAng = math.cos(angular);

    final lat2 = math.asin(
      sinLat1 * cosAng + cosLat1 * sinAng * math.cos(bearing),
    );
    final lng2 = lng1 +
        math.atan2(
          math.sin(bearing) * sinAng * cosLat1,
          cosAng - sinLat1 * math.sin(lat2),
        );

    return GroupLatLng(
      _degrees(lat2).clamp(-90.0, 90.0).toDouble(),
      _wrapLongitude(_degrees(lng2)),
    );
  }

  static double _radians(double degrees) => degrees * math.pi / 180;
  static double _degrees(double radians) => radians * 180 / math.pi;

  static double _normalizeLongitudeDelta(double degrees) {
    var d = degrees;
    while (d > 180) {
      d -= 360;
    }
    while (d < -180) {
      d += 360;
    }
    return d;
  }

  static double _wrapLongitude(double longitude) {
    var lng = longitude;
    while (lng > 180) {
      lng -= 360;
    }
    while (lng < -180) {
      lng += 360;
    }
    return lng;
  }
}

class GroupLatLng {
  const GroupLatLng(this.latitude, this.longitude);
  final double latitude;
  final double longitude;
}
