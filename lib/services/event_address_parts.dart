/// Validação e composição do endereço público estruturado do evento.
class EventAddressParts {
  const EventAddressParts({
    this.street = '',
    this.streetNumber = '',
    this.noStreetNumber = false,
    this.addressComplement = '',
    this.district = '',
    this.city = '',
    this.stateName = '',
    this.postalCode = '',
    this.countryCode = '',
    this.countryName = '',
    this.legacyAddress = '',
  });

  final String street;
  final String streetNumber;
  final bool noStreetNumber;
  final String addressComplement;
  final String district;
  final String city;
  final String stateName;
  final String postalCode;
  final String countryCode;
  final String countryName;
  final String legacyAddress;

  static const int streetNumberMaxLen = 20;
  static final RegExp streetNumberPattern = RegExp(
    r"^[0-9A-Za-zÀ-ÿ][0-9A-Za-zÀ-ÿ.\-\/ ]{0,19}$",
  );

  static String firstNonEmpty(Iterable<dynamic> values) {
    for (final v in values) {
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  /// Número válido (125, 125A, 10-123) ou vazio.
  static bool isValidStreetNumber(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return true;
    if (t.length > streetNumberMaxLen) return false;
    if (t.contains('<') || t.contains('>') || t.contains('\n')) return false;
    return streetNumberPattern.hasMatch(t);
  }

  /// Erro de validação ou null se ok.
  String? validationErrorKey() {
    if (street.trim().isNotEmpty &&
        !noStreetNumber &&
        streetNumber.trim().isEmpty) {
      return 'event_wizard_street_number_required';
    }
    if (!noStreetNumber &&
        streetNumber.trim().isNotEmpty &&
        !isValidStreetNumber(streetNumber)) {
      return 'event_wizard_street_number_invalid';
    }
    return null;
  }

  /// Endereço público formatado (compatível com campo legado `address`).
  String composePublicAddress() {
    final streetLine = <String>[];
    final s = street.trim();
    if (s.isNotEmpty) {
      streetLine.add(s);
      if (!noStreetNumber && streetNumber.trim().isNotEmpty) {
        streetLine.add(streetNumber.trim());
      }
    }
    final line1 = streetLine.join(', ');
    final parts = <String>[
      line1,
      addressComplement.trim(),
      district.trim(),
      city.trim(),
      stateName.trim(),
      postalCode.trim(),
      if (countryName.trim().isNotEmpty)
        countryName.trim()
      else
        countryCode.trim().toUpperCase(),
    ].where((e) => e.isNotEmpty).toList();

    if (parts.isEmpty) {
      return firstNonEmpty([legacyAddress]);
    }

    final out = <String>[];
    for (final p in parts) {
      if (out.isEmpty || out.last.toLowerCase() != p.toLowerCase()) {
        out.add(p);
      }
    }
    return out.join(', ');
  }

  factory EventAddressParts.fromEventMap(Map<String, dynamic> data) {
    final nested = data['location'] is Map
        ? Map<String, dynamic>.from(data['location'] as Map)
        : null;
    bool asBool(dynamic v) => v == true || v == 'true' || v == 1;

    return EventAddressParts(
      street: firstNonEmpty([
        data['street'],
        data['route'],
        nested?['street'],
        nested?['route'],
      ]),
      streetNumber: firstNonEmpty([
        data['streetNumber'],
        data['street_number'],
        nested?['streetNumber'],
        nested?['street_number'],
      ]),
      noStreetNumber:
          asBool(data['noStreetNumber'] ?? nested?['noStreetNumber']),
      addressComplement: firstNonEmpty([
        data['addressComplement'],
        data['complement'],
        data['subpremise'],
        nested?['addressComplement'],
      ]),
      district: firstNonEmpty([
        data['district'],
        data['neighborhood'],
        data['bairro'],
        nested?['district'],
      ]),
      city: firstNonEmpty([
        data['city'],
        data['cityName'],
        nested?['city'],
      ]),
      stateName: firstNonEmpty([
        data['stateName'],
        data['state'],
        data['province'],
      ]),
      postalCode: firstNonEmpty([
        data['postalCode'],
        data['zipCode'],
        nested?['postalCode'],
      ]),
      countryCode: firstNonEmpty([
        data['countryCode'],
      ]).toLowerCase(),
      countryName: firstNonEmpty([
        data['country'],
        data['countryName'],
      ]),
      legacyAddress: firstNonEmpty([
        data['address'],
        data['fullAddress'],
        data['publicAddress'],
        data['placeDisplay'],
      ]),
    );
  }

  /// Extrai componentes de `address_components` do Places API (legado).
  factory EventAddressParts.fromPlacesComponents(
    List<dynamic> components, {
    String legacyAddress = '',
    String cityFallback = '',
    String stateFallback = '',
    String countryCodeFallback = '',
    String countryNameFallback = '',
    String postalFallback = '',
  }) {
    String byType(String type, {bool short = false}) {
      for (final raw in components) {
        if (raw is! Map) continue;
        final types = raw['types'];
        if (types is! List || !types.contains(type)) continue;
        final long = (raw['long_name'] ?? raw['longText'] ?? '').toString();
        final shortName =
            (raw['short_name'] ?? raw['shortText'] ?? '').toString();
        final v = short ? (shortName.isNotEmpty ? shortName : long) : long;
        if (v.trim().isNotEmpty) return v.trim();
      }
      return '';
    }

    final streetNumber = byType('street_number');
    final street = byType('route');
    final complement = byType('subpremise');
    final district = firstNonEmpty([
      byType('sublocality_level_1'),
      byType('sublocality'),
      byType('neighborhood'),
    ]);
    final city = firstNonEmpty([
      byType('locality'),
      byType('administrative_area_level_2'),
      cityFallback,
    ]);
    final stateName = firstNonEmpty([
      byType('administrative_area_level_1'),
      stateFallback,
    ]);
    final postalCode = firstNonEmpty([
      byType('postal_code'),
      postalFallback,
    ]);
    final countryName = firstNonEmpty([
      byType('country'),
      countryNameFallback,
    ]);
    final countryCode = firstNonEmpty([
      byType('country', short: true),
      countryCodeFallback,
    ]).toLowerCase();

    return EventAddressParts(
      street: street,
      streetNumber: streetNumber,
      noStreetNumber: street.isNotEmpty && streetNumber.isEmpty,
      addressComplement: complement,
      district: district,
      city: city,
      stateName: stateName,
      postalCode: postalCode,
      countryCode: countryCode,
      countryName: countryName,
      legacyAddress: legacyAddress,
    );
  }
}
