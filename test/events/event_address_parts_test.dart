import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/event_address_parts.dart';
import 'package:socialchat_mvp/services/event_location_resolver.dart';

void main() {
  group('EventAddressParts', () {
    test('accepts numeric and alphanumeric numbers', () {
      expect(EventAddressParts.isValidStreetNumber('125'), isTrue);
      expect(EventAddressParts.isValidStreetNumber('125A'), isTrue);
      expect(EventAddressParts.isValidStreetNumber('10-123'), isTrue);
      expect(EventAddressParts.isValidStreetNumber('s/n'), isTrue);
      expect(EventAddressParts.isValidStreetNumber('<script>'), isFalse);
      expect(EventAddressParts.isValidStreetNumber('x' * 21), isFalse);
    });

    test('requires number when street set without noStreetNumber', () {
      final err = const EventAddressParts(
        street: 'Av. Atlântica',
        streetNumber: '',
      ).validationErrorKey();
      expect(err, 'event_wizard_street_number_required');
    });

    test('allows noStreetNumber for parks', () {
      final parts = const EventAddressParts(
        street: 'Parque Central',
        noStreetNumber: true,
        city: 'Navegantes',
        stateName: 'SC',
      );
      expect(parts.validationErrorKey(), isNull);
      expect(parts.composePublicAddress(), contains('Parque Central'));
      expect(parts.composePublicAddress(), isNot(contains('null')));
    });

    test('compose includes number and complement', () {
      final a = const EventAddressParts(
        street: 'Rua das Flores',
        streetNumber: '125A',
        addressComplement: 'Sala 2',
        district: 'Centro',
        city: 'São Paulo',
        stateName: 'SP',
        postalCode: '01000-000',
        countryName: 'Brasil',
      ).composePublicAddress();
      expect(a, contains('125A'));
      expect(a, contains('Sala 2'));
      expect(a, contains('São Paulo'));
    });

    test('Places components with street_number', () {
      final parts = EventAddressParts.fromPlacesComponents([
        {
          'long_name': '333',
          'short_name': '333',
          'types': ['street_number'],
        },
        {
          'long_name': 'Rua José Bernardo Pinto',
          'short_name': 'R. José Bernardo Pinto',
          'types': ['route'],
        },
        {
          'long_name': 'São Paulo',
          'short_name': 'São Paulo',
          'types': ['locality'],
        },
      ]);
      expect(parts.streetNumber, '333');
      expect(parts.street, 'Rua José Bernardo Pinto');
      expect(parts.composePublicAddress(), contains('333'));
    });

    test('Places without street_number leaves number empty', () {
      final parts = EventAddressParts.fromPlacesComponents([
        {
          'long_name': 'Orla de Navegantes',
          'short_name': 'Orla',
          'types': ['route'],
        },
        {
          'long_name': 'Navegantes',
          'short_name': 'Navegantes',
          'types': ['locality'],
        },
      ]);
      expect(parts.streetNumber, isEmpty);
      expect(parts.street, isNotEmpty);
    });

    test('international address accents', () {
      final a = const EventAddressParts(
        street: 'Rue Saint-Denis',
        streetNumber: '10',
        city: 'Montréal',
        stateName: 'Québec',
        countryName: 'Canada',
      ).composePublicAddress();
      expect(a, contains('Montréal'));
      expect(a, contains('Québec'));
    });
  });

  group('EventPlaceDetailsMerge', () {
    test('complete Places payload fills all structured fields', () {
      final parts = EventAddressParts.fromPlacesComponents([
        {'long_name': '100', 'short_name': '100', 'types': ['street_number']},
        {
          'long_name': 'Avenida das Américas',
          'short_name': 'Av. das Américas',
          'types': ['route'],
        },
        {
          'long_name': 'Barra da Tijuca',
          'short_name': 'Barra',
          'types': ['sublocality_level_1'],
        },
        {
          'long_name': 'Rio de Janeiro',
          'short_name': 'Rio de Janeiro',
          'types': ['locality'],
        },
        {
          'long_name': 'Rio de Janeiro',
          'short_name': 'RJ',
          'types': ['administrative_area_level_1'],
        },
        {
          'long_name': '22640-100',
          'short_name': '22640-100',
          'types': ['postal_code'],
        },
        {
          'long_name': 'Brasil',
          'short_name': 'BR',
          'types': ['country'],
        },
      ]);
      final merged = EventPlaceDetailsMerge.apply(
        parts: parts,
        existingPlaceName: '',
        existingStreet: '',
        existingStreetNumber: '',
        existingNoStreetNumber: false,
        existingComplement: '',
        existingDistrict: '',
        existingCity: '',
        existingStateName: '',
        existingPostalCode: '',
        existingCountryCode: '',
        existingCountryName: '',
        existingAddress: '',
        apiPlaceName: 'Parque Olímpico',
        formattedAddress: 'Av. das Américas, 100 - Barra, Rio de Janeiro',
        lat: -22.983,
        lng: -43.365,
      );
      expect(merged.placeName, 'Parque Olímpico');
      expect(merged.street, 'Avenida das Américas');
      expect(merged.streetNumber, '100');
      expect(merged.noStreetNumber, isFalse);
      expect(merged.district, 'Barra da Tijuca');
      expect(merged.city, 'Rio de Janeiro');
      expect(merged.postalCode, '22640-100');
      expect(merged.countryCode, 'br');
      expect(merged.lat, -22.983);
      expect(merged.lng, -43.365);
      expect(merged.publicAddress, contains('100'));
    });

    test('partial Places payload preserves valid existing fields', () {
      final parts = EventAddressParts.fromPlacesComponents([
        {
          'long_name': 'Parque Olímpico',
          'short_name': 'Parque Olímpico',
          'types': ['route'],
        },
        {
          'long_name': 'Rio de Janeiro',
          'short_name': 'Rio de Janeiro',
          'types': ['locality'],
        },
      ]);
      final merged = EventPlaceDetailsMerge.apply(
        parts: parts,
        existingPlaceName: 'Nome antigo',
        existingStreet: 'Rua já preenchida',
        existingStreetNumber: '42',
        existingNoStreetNumber: false,
        existingComplement: 'Bloco A',
        existingDistrict: 'Centro',
        existingCity: 'Niterói',
        existingStateName: 'RJ',
        existingPostalCode: '24000-000',
        existingCountryCode: 'br',
        existingCountryName: 'Brasil',
        existingAddress: 'legado',
        apiPlaceName: 'Parque Olímpico',
        formattedAddress: '',
        lat: null,
        lng: null,
        existingLat: -22.9,
        existingLng: -43.1,
      );
      // Rua da API sobrescreve; número/CEP/bairro/coords ausentes preservam.
      expect(merged.placeName, 'Parque Olímpico');
      expect(merged.street, 'Parque Olímpico');
      expect(merged.streetNumber, '42');
      expect(merged.noStreetNumber, isFalse);
      expect(merged.district, 'Centro');
      expect(merged.postalCode, '24000-000');
      expect(merged.city, 'Rio de Janeiro');
      expect(merged.addressComplement, 'Bloco A');
      expect(merged.lat, -22.9);
      expect(merged.lng, -43.1);
      expect(merged.address, 'legado');
    });

    test('empty API place name keeps existing place name', () {
      final merged = EventPlaceDetailsMerge.apply(
        parts: const EventAddressParts(city: 'Toronto'),
        existingPlaceName: 'CN Tower',
        existingStreet: '',
        existingStreetNumber: '',
        existingNoStreetNumber: true,
        existingComplement: '',
        existingDistrict: '',
        existingCity: '',
        existingStateName: '',
        existingPostalCode: '',
        existingCountryCode: 'ca',
        existingCountryName: 'Canada',
        existingAddress: '',
        apiPlaceName: '  ',
      );
      expect(merged.placeName, 'CN Tower');
      expect(merged.city, 'Toronto');
      expect(merged.noStreetNumber, isTrue);
      expect(merged.countryCode, 'ca');
    });
  });

  group('Resolver + street number', () {
    test('structured street+number preferred over legacy', () {
      final d = EventLocationResolver.fromEventMap({
        'street': 'Av. Beira Mar',
        'streetNumber': '100',
        'city': 'Navegantes',
        'stateName': 'SC',
        'address': 'legacy only',
        'lat': -26.9,
        'lng': -48.6,
      });
      expect(d.address, contains('100'));
      expect(d.address, isNot(contains('legacy only')));
      expect(d.hasValidCoords, isTrue);
    });

    test('legacy address-only still works', () {
      final d = EventLocationResolver.fromEventMap({
        'address': 'Centro / Orla de Navegantes, Navegantes',
        'placeName': 'Orla',
      });
      expect(d.hasValidDestination, isTrue);
      expect(d.mapsQuery, contains('Orla'));
    });

    test('coords priority over address for destination validity', () {
      final d = EventLocationResolver.fromEventMap({
        'lat': -26.8986,
        'lng': -48.6542,
        'street': 'Av. X',
        'streetNumber': '1',
      });
      expect(d.hasValidCoords, isTrue);
      expect(d.hasValidDestination, isTrue);
    });

    test('no destination', () {
      expect(
        EventLocationResolver.fromEventMap({'title': 'X'}).hasValidDestination,
        isFalse,
      );
    });
  });
}
