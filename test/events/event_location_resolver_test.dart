import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/models/event_presentation.dart';
import 'package:socialchat_mvp/services/event_directions_service.dart';
import 'package:socialchat_mvp/services/event_location_resolver.dart';

void main() {
  group('EventLocationResolver', () {
    test('coords as double lat/lng', () {
      final d = EventLocationResolver.fromEventMap({
        'lat': -26.8986,
        'lng': -48.6542,
        'placeName': 'Orla',
      });
      expect(d.hasValidCoords, isTrue);
      expect(d.lat, -26.8986);
      expect(d.lng, -48.6542);
    });

    test('coords as string latitude/longitude', () {
      final d = EventLocationResolver.fromEventMap({
        'latitude': '-26,8986',
        'longitude': '-48.6542',
      });
      expect(d.hasValidCoords, isTrue);
      expect(d.lat, closeTo(-26.8986, 0.0001));
    });

    test('Firestore GeoPoint', () {
      final d = EventLocationResolver.fromEventMap({
        'geoPoint': const GeoPoint(-26.8986, -48.6542),
      });
      expect(d.hasValidCoords, isTrue);
      expect(d.lat, -26.8986);
      expect(d.lng, -48.6542);
    });

    test('nested location map', () {
      final d = EventLocationResolver.fromEventMap({
        'location': {
          'lat': -23.5,
          'lng': -46.6,
          'placeName': 'Expo',
          'city': 'São Paulo',
        },
      });
      expect(d.hasValidCoords, isTrue);
      expect(d.placeName, 'Expo');
      expect(d.city, 'São Paulo');
    });

    test('public address aliases fullAddress/publicAddress', () {
      final d = EventLocationResolver.fromEventMap({
        'placeName': '',
        'address': '',
        'fullAddress': 'Av. Atlântica, 100',
        'cityName': 'Navegantes',
      });
      expect(d.address, 'Av. Atlântica, 100');
      expect(d.city, 'Navegantes');
      expect(d.hasValidDestination, isTrue);
    });

    test('empty placeName does not shadow placeDisplay', () {
      final d = EventLocationResolver.fromEventMap({
        'placeName': '',
        'placeDisplay': 'Centro / Orla de Navegantes',
        'city': 'Navegantes',
      });
      expect(d.placeName, 'Centro / Orla de Navegantes');
      expect(d.mapsQuery.contains('Navegantes'), isTrue);
    });

    test('place + city + state + country without coords', () {
      final d = EventLocationResolver.fromEventMap({
        'placeName': 'Pier',
        'city': 'Navegantes',
        'state': 'Santa Catarina',
        'country': 'Brasil',
      });
      expect(d.hasValidCoords, isFalse);
      expect(d.hasValidDestination, isTrue);
      expect(
        d.mapsQuery,
        'Pier, Navegantes, Santa Catarina, Brasil',
      );
    });

    test('accents preserved in query', () {
      final d = EventLocationResolver.fromEventMap({
        'address': 'Praça da Sé',
        'city': 'São Paulo',
        'stateName': 'São Paulo',
      });
      expect(d.mapsQuery, contains('Praça'));
      expect(d.mapsQuery, contains('São Paulo'));
    });

    test('rejects 0,0 and out of range', () {
      expect(
        EventLocationResolver.fromEventMap({'lat': 0, 'lng': 0})
            .hasValidCoords,
        isFalse,
      );
      expect(
        EventLocationResolver.fromEventMap({'lat': 91, 'lng': 0})
            .hasValidCoords,
        isFalse,
      );
      expect(
        EventLocationResolver.fromEventMap({
          'lat': -26.0,
          'lng': 200.0,
        }).hasValidCoords,
        isFalse,
      );
    });

    test('event without location', () {
      final d = EventLocationResolver.fromEventMap({'title': 'X'});
      expect(d.hasValidDestination, isFalse);
    });

    test('portal-style document (latitude + fullAddress)', () {
      final d = EventLocationResolver.fromEventMap({
        'title': 'Festival Remdy Navegantes',
        'placeName': 'Centro / Orla de Navegantes',
        'fullAddress':
            'Centro / Orla de Navegantes, Navegantes, Santa Catarina',
        'address':
            'Centro / Orla de Navegantes, Navegantes, Santa Catarina',
        'city': 'Navegantes',
        'cityName': 'Navegantes',
        'stateName': 'Santa Catarina',
        'latitude': -26.8986,
        'longitude': -48.6542,
        'lat': -26.8986,
        'lng': -48.6542,
      });
      expect(d.hasValidDestination, isTrue);
      expect(d.hasValidCoords, isTrue);
      expect(
        EventDirectionsService.hasValidDestination(
          lat: d.lat,
          lng: d.lng,
          place: d.placeName,
          address: d.address,
          city: d.city,
          state: d.stateName,
        ),
        isTrue,
      );
    });

    test('app-style document (lat/lng + placeName)', () {
      final d = EventLocationResolver.fromEventMap({
        'placeName': 'Parque',
        'address': 'Av. QA, 100',
        'city': 'Campo Mourão',
        'lat': -24.045,
        'lng': -52.378,
      });
      expect(d.hasValidCoords, isTrue);
    });

    test('EventPresentation.fromMap uses resolver (legacy latitude)', () {
      final e = EventPresentation.fromMap('ev1', {
        'title': 'Legacy',
        'latitude': -26.8986,
        'longitude': -48.6542,
        'placeName': '',
        'fullAddress': 'Orla de Navegantes',
        'cityName': 'Navegantes',
      });
      expect(e.lat, -26.8986);
      expect(e.lng, -48.6542);
      expect(e.address, 'Orla de Navegantes');
      expect(e.city, 'Navegantes');
      expect(
        EventDirectionsService.hasValidDestination(
          lat: e.lat,
          lng: e.lng,
          place: e.placeName,
          address: e.address,
          city: e.city,
        ),
        isTrue,
      );
    });
  });
}
