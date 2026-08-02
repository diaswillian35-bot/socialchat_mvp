import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Abre mapas com coordenadas do evento ou endereço público.
/// Nunca usa localização residencial do organizador.
class EventDirectionsService {
  EventDirectionsService._();

  static bool hasValidDestination({
    double? lat,
    double? lng,
    String place = '',
    String address = '',
    String city = '',
  }) {
    if (validCoords(lat, lng)) return true;
    final q = query(place: place, address: address, city: city);
    return q.isNotEmpty;
  }

  static Future<bool> open({
    double? lat,
    double? lng,
    String place = '',
    String address = '',
    String city = '',
  }) async {
    if (validCoords(lat, lng)) {
      final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
      final uri = isIos
          ? Uri.parse(
              'https://maps.apple.com/?daddr=${lat!.toStringAsFixed(6)},${lng!.toStringAsFixed(6)}',
            )
          : Uri.parse(
              'https://www.google.com/maps/dir/?api=1&destination=${lat!.toStringAsFixed(6)},${lng!.toStringAsFixed(6)}',
            );
      if (await canLaunchUrl(uri)) {
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }

    final q = query(place: place, address: address, city: city);
    if (q.isEmpty) return false;

    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}',
    );
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// Coordenadas públicas confiáveis do evento (não residência do organizador).
  static bool validCoords(double? lat, double? lng) {
    if (lat == null || lng == null) return false;
    if (!lat.isFinite || !lng.isFinite) return false;
    if (lat < -90 || lat > 90) return false;
    if (lng < -180 || lng > 180) return false;
    // (0,0) costuma ser placeholder inválido.
    if (lat.abs() < 0.000001 && lng.abs() < 0.000001) return false;
    return true;
  }

  static String query({
    required String place,
    required String address,
    required String city,
  }) {
    final parts = <String>[
      place.trim(),
      address.trim(),
      city.trim(),
    ].where((e) => e.isNotEmpty).toList();
    // Dedup consecutivos.
    final out = <String>[];
    for (final p in parts) {
      if (out.isEmpty || out.last.toLowerCase() != p.toLowerCase()) {
        out.add(p);
      }
    }
    return out.join(', ');
  }
}
