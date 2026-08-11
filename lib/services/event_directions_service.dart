import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'event_location_resolver.dart';

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
    String state = '',
    String country = '',
  }) {
    if (EventLocationResolver.validCoords(lat, lng)) return true;
    final q = query(
      place: place,
      address: address,
      city: city,
      state: state,
      country: country,
    );
    return q.isNotEmpty;
  }

  /// Atalho a partir do destino já resolvido pelo [EventLocationResolver].
  static bool hasValidResolvedDestination(EventPublicDestination dest) =>
      dest.hasValidDestination;

  static Future<bool> open({
    double? lat,
    double? lng,
    String place = '',
    String address = '',
    String city = '',
    String state = '',
    String country = '',
  }) async {
    final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

    if (EventLocationResolver.validCoords(lat, lng)) {
      final uris = <Uri>[
        if (isIos)
          Uri.parse(
            'https://maps.apple.com/?daddr=${lat!.toStringAsFixed(6)},${lng!.toStringAsFixed(6)}',
          )
        else ...[
          Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=${lat!.toStringAsFixed(6)},${lng!.toStringAsFixed(6)}',
          ),
          Uri.parse('geo:$lat,$lng?q=$lat,$lng'),
        ],
      ];
      if (await _launchFirst(uris)) return true;
    }

    final q = query(
      place: place,
      address: address,
      city: city,
      state: state,
      country: country,
    );
    if (q.isEmpty) return false;

    final encoded = Uri.encodeComponent(q);
    final uris = <Uri>[
      if (isIos)
        Uri.parse('https://maps.apple.com/?daddr=$encoded')
      else ...[
        Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$encoded',
        ),
        Uri.parse('geo:0,0?q=$encoded'),
      ],
    ];
    return _launchFirst(uris);
  }

  static Future<bool> openResolved(EventPublicDestination dest) {
    return open(
      lat: dest.lat,
      lng: dest.lng,
      place: dest.placeName,
      address: dest.address,
      city: dest.city,
      state: dest.stateName,
      country: dest.countryName.isNotEmpty
          ? dest.countryName
          : dest.countryCode,
    );
  }

  /// Coordenadas públicas confiáveis do evento (não residência do organizador).
  static bool validCoords(double? lat, double? lng) =>
      EventLocationResolver.validCoords(lat, lng);

  static String query({
    required String place,
    required String address,
    required String city,
    String state = '',
    String country = '',
  }) {
    final parts = <String>[
      place.trim(),
      address.trim(),
      city.trim(),
      state.trim(),
      country.trim(),
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

  /// Não depende de [canLaunchUrl] como gate duro: no Android 11+ isso falha
  /// sem `<queries>` para https/geo mesmo com Maps instalado.
  static Future<bool> _launchFirst(List<Uri> uris) async {
    for (final uri in uris) {
      try {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return true;
      } catch (_) {
        // tenta o próximo fallback
      }
    }
    return false;
  }
}
