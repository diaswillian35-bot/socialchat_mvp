import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/data/firestore_place_mapper.dart';

Map<String, dynamic> approvedPlace() => {
      'contractVersion': 'remdy.places.v1',
      'moderationStatus': 'published',
      'active': true,
      'deleted': false,
      'slug': 'cafe-campo-mourao',
      'name': 'Café Campo Mourão',
      'category': 'cafe',
      'description': 'Café e encontros.',
      'countryCode': 'br',
      'stateCode': 'PR',
      'stateName': 'Paraná',
      'cityName': 'Campo Mourão',
      'addressLine': 'Avenida Irmãos Pereira, 100',
      'latitude': -24.04,
      'longitude': -52.38,
      'phone': '+554400000000',
      'whatsapp': '+5544999999999',
      'websiteUrl': 'https://remdy.app/locais',
      'coverUrl': 'https://cdn.example.com/cover.jpg',
      'photoUrls': [
        'https://cdn.example.com/cover.jpg',
        'https://cdn.example.com/gallery.jpg',
      ],
      'hoursNote': '08:00-20:00',
      'rating': {'average': 4.5, 'count': 8},
      'upcomingEvents': [],
      'menu': {
        'enabled': true,
        'photoUrls': ['https://cdn.example.com/menu.jpg'],
        'pdfUrl': 'https://cdn.example.com/menu.pdf',
        'notice': 'Confirme os preços.',
        'items': [
          {
            'name': 'Café',
            'description': 'Coado',
            'price': r'R$ 8',
            'available': true
          },
        ],
      },
    };

void main() {
  test('mapeia o mesmo contrato público do portal e do Admin', () {
    final place = FirestorePlaceMapper.tryParse('plc-cm-1', approvedPlace());

    expect(place, isNotNull);
    expect(place!.name, 'Café Campo Mourão');
    expect(place.address.city, 'Campo Mourão');
    expect(place.contact.whatsapp, '+5544999999999');
    expect(place.photos, hasLength(2));
    expect(place.rating, 4.5);
    expect(place.ratingCount, 8);
    expect(place.hours, hasLength(7));
    expect(place.menu.enabled, isTrue);
    expect(place.menu.items.single.name, 'Café');
    expect(place.menu.pdfUrl, 'https://cdn.example.com/menu.pdf');
  });

  test('cardápio só aparece em restaurante, bar ou café e recusa URL insegura',
      () {
    final hotel = approvedPlace()..['category'] = 'hotel';
    final unsafe = approvedPlace()
      ..['menu'] = {
        'enabled': true,
        'photoUrls': ['javascript:alert(1)'],
        'pdfUrl': 'http://example.com/menu.pdf',
        'items': [],
      };
    expect(
        FirestorePlaceMapper.tryParse('hotel-1', hotel)!.menu.enabled, isFalse);
    expect(
        FirestorePlaceMapper.tryParse('cafe-2', unsafe)!.menu.enabled, isFalse);
  });

  test('recusa rascunho, suspenso, inativo, apagado e contrato estranho', () {
    for (final change in <Map<String, dynamic>>[
      {'moderationStatus': 'draft'},
      {'moderationStatus': 'suspended'},
      {'active': false},
      {'deleted': true},
      {'contractVersion': 'parallel.places.v2'},
    ]) {
      final data = approvedPlace()..addAll(change);
      expect(FirestorePlaceMapper.tryParse('plc-cm-1', data), isNull);
    }
  });

  test('recusa foto insegura e coordenadas ausentes sem quebrar a lista', () {
    final unsafe = approvedPlace()
      ..['coverUrl'] = 'http://inseguro.example/cover.jpg'
      ..['photoUrls'] = ['javascript:alert(1)'];
    final noCoordinates = approvedPlace()..remove('latitude');

    expect(FirestorePlaceMapper.tryParse('unsafe', unsafe), isNull);
    expect(
        FirestorePlaceMapper.tryParse('no-coordinates', noCoordinates), isNull);
  });
}
