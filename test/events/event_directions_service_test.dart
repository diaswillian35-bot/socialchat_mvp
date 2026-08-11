import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/event_directions_service.dart';

void main() {
  group('EventDirectionsService.validCoords', () {
    test('accepts finite in-range coords', () {
      expect(EventDirectionsService.validCoords(-24.045, -52.378), isTrue);
    });

    test('rejects null, NaN, out of range and 0,0', () {
      expect(EventDirectionsService.validCoords(null, -52.0), isFalse);
      expect(EventDirectionsService.validCoords(-24.0, null), isFalse);
      expect(EventDirectionsService.validCoords(double.nan, -52.0), isFalse);
      expect(EventDirectionsService.validCoords(91, -52.0), isFalse);
      expect(EventDirectionsService.validCoords(0, 0), isFalse);
    });
  });

  group('EventDirectionsService.hasValidDestination', () {
    test('true with coords', () {
      expect(
        EventDirectionsService.hasValidDestination(lat: -24.0, lng: -52.0),
        isTrue,
      );
    });

    test('true with public address only', () {
      expect(
        EventDirectionsService.hasValidDestination(
          address: 'Parque de Exposições',
          city: 'Campo Mourão',
        ),
        isTrue,
      );
    });

    test('false without coords or address', () {
      expect(EventDirectionsService.hasValidDestination(), isFalse);
      expect(
        EventDirectionsService.hasValidDestination(lat: 0, lng: 0),
        isFalse,
      );
    });
  });

  group('EventDirectionsService.query', () {
    test('joins and dedups public parts', () {
      expect(
        EventDirectionsService.query(
          place: 'Parque',
          address: 'Parque',
          city: 'Campo Mourão',
        ),
        'Parque, Campo Mourão',
      );
    });

    test('keeps accents and spaces for encoding', () {
      final q = EventDirectionsService.query(
        place: '',
        address: 'Praça da Sé',
        city: 'São Paulo',
      );
      expect(q, 'Praça da Sé, São Paulo');
      expect(Uri.encodeComponent(q).contains('%'), isTrue);
    });

    test('includes state and country when provided', () {
      expect(
        EventDirectionsService.query(
          place: 'Pier',
          address: '',
          city: 'Navegantes',
          state: 'SC',
          country: 'Brasil',
        ),
        'Pier, Navegantes, SC, Brasil',
      );
    });
  });

  group('EventDirectionsService + legacy fields', () {
    test('hasValidDestination with place+city only', () {
      expect(
        EventDirectionsService.hasValidDestination(
          place: 'Orla',
          city: 'Navegantes',
        ),
        isTrue,
      );
    });
  });
}
