import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/data/firestore_place_mapper.dart';
import 'package:socialchat_mvp/features/locais/data/place_submission_service.dart';
import 'package:socialchat_mvp/features/locais/logic/place_query.dart';
import 'package:socialchat_mvp/features/locais/models/place_listing.dart';

import 'firestore_place_mapper_test.dart' show approvedPlace;

Map<String, dynamic> deliveryPlace() => {
      ...approvedPlace(),
      'name': 'Burger Delivery',
      'cityName': 'Toronto',
      'countryCode': 'ca',
      'addressLine': '',
      'deliveryOnly': true,
      'deliveryArea': 'Downtown Toronto',
    }
      ..remove('latitude')
      ..remove('longitude');

void main() {
  group('Só delivery', () {
    test('mapper mantém local só delivery sem coordenadas', () {
      final place = FirestorePlaceMapper.tryParse('d1', deliveryPlace());
      expect(place, isNotNull);
      expect(place!.deliveryOnly, isTrue);
      expect(place.deliveryArea, 'Downtown Toronto');
      expect(place.address.latitude, isNull);
      expect(place.hasPhysicalLocation, isFalse);
      expect(place.address.city, 'Toronto');
    });

    test('mapper ainda descarta local normal sem coordenadas', () {
      final data = deliveryPlace()..remove('deliveryOnly');
      expect(FirestorePlaceMapper.tryParse('d2', data), isNull);
    });

    test('cidade continua obrigatória', () {
      final data = deliveryPlace()..['cityName'] = '';
      expect(FirestorePlaceMapper.tryParse('d3', data), isNull);
    });

    test('local normal: deliveryOnly false e com mapa', () {
      final place = FirestorePlaceMapper.tryParse('n1', approvedPlace())!;
      expect(place.deliveryOnly, isFalse);
      expect(place.deliveryArea, isNull);
      expect(place.hasPhysicalLocation, isTrue);
    });

    test('filtro Delivery e busca por cidade/área sem lat/lng', () {
      final d = FirestorePlaceMapper.tryParse('d1', deliveryPlace())!;
      final n = FirestorePlaceMapper.tryParse('n1', approvedPlace())!;
      const engine = PlaceQueryEngine();
      final now = DateTime(2026, 11, 4, 12);
      expect(
        engine.apply(
            source: [d, n],
            query: const PlaceQuery(deliveryOnly: true),
            now: now).map((p) => p.id),
        ['d1'],
      );
      expect(
        engine.apply(
            source: [d, n],
            query: const PlaceQuery(search: 'toronto'),
            now: now).map((p) => p.id),
        ['d1'],
      );
      expect(
        engine.apply(
            source: [d, n],
            query: const PlaceQuery(search: 'downtown'),
            now: now).length,
        1,
      );
      expect(
          const PlaceQuery().copyWith(deliveryOnly: true).deliveryOnly, isTrue);
    });

    test('contrato portal aceita só delivery sem coordenadas', () {
      final json = {
        'contract': PlaceContract.version,
        'id': 'burger_1',
        'slug': 'burger-1',
        'name': 'Burger',
        'category': 'restaurant',
        'description': 'Só delivery',
        'photos': [
          {'id': 'p', 'alt': 'a', 'color': 1}
        ],
        'rating': 0,
        'ratingCount': 0,
        'address': {'city': 'Toronto', 'countryCode': 'CA'},
        'contact': <String, dynamic>{},
        'hours': [],
        'accessibility': {
          'wheelchairEntrance': false,
          'stepFree': false,
          'accessibleRestroom': false,
        },
        'deliveryOnly': true,
        'deliveryArea': 'Downtown',
      };
      final place = PlaceListing.fromPortalJson(json);
      expect(place.deliveryOnly, isTrue);
      expect(place.address.singleLine, 'Toronto');
      expect(PlaceListing.fromPortalJson(place.toPortalJson()).deliveryArea,
          'Downtown');
      expect(
        () => PlaceListing.fromPortalJson({...json, 'deliveryOnly': false}),
        throwsA(isA<PlaceContractException>()),
      );
    });

    test('rascunho: só delivery exige só a cidade', () {
      final draft = PlaceDraft(
          cityName: 'Toronto', deliveryOnly: true, deliveryArea: ' Downtown ');
      expect(draft.locationValid, isTrue);
      expect(draft.toFields()['deliveryArea'], 'Downtown');
      expect(draft.toFields()['deliveryOnly'], isTrue);
      expect(PlaceDraft(cityName: 'Toronto').locationValid, isFalse);
      final back = PlaceDraft.fromSummary(
          {'deliveryOnly': true, 'deliveryArea': 'X', 'cityName': 'T'});
      expect(back.deliveryOnly, isTrue);
      expect(back.deliveryArea, 'X');
    });
  });
}
