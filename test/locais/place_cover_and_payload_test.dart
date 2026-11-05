import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/data/place_submission_service.dart';
import 'package:socialchat_mvp/features/locais/logic/place_hours_logic.dart';

const _p =
    'https://firebasestorage.googleapis.com/v0/b/x/o/places%2Fjb%2Fphotos%2F';

void main() {
  group('Logo / Capa', () {
    test('editar: capa sai da grade e volta como 1ª foto, sem duplicar', () {
      final d = PlaceDraft(
        id: 'jb',
        photoUrls: ['${_p}a', '${_p}b', '${_p}c'],
        coverUrl: '${_p}b',
      )..extractCover();
      expect(d.photoUrls, ['${_p}a', '${_p}c']);
      expect(d.coverUrl, '${_p}b');
      expect(d.photoCount, 3);
      final m = d.mediaFields(const []);
      expect(m['photoUrls'], ['${_p}b', '${_p}a', '${_p}c']);
      expect(m['coverUrl'], '${_p}b');
    });
    test('logo nova enviada vira a capa e a 1ª foto', () {
      final d = PlaceDraft(photoUrls: ['${_p}a'], coverUrl: '${_p}a')
        ..extractCover()
        ..coverUrl = ''
        ..pendingCoverPath = '/tmp/logo.jpg';
      expect(d.photoCount, 1);
      final m = d.mediaFields(['${_p}n'], uploadedCover: '${_p}logo');
      expect(m['photoUrls'], ['${_p}logo', '${_p}n']);
      expect(m['coverUrl'], '${_p}logo');
    });
    test('remover a logo: capa = 1ª foto restante', () {
      final d = PlaceDraft(photoUrls: ['${_p}a', '${_p}b'], coverUrl: '${_p}a')
        ..extractCover()
        ..coverUrl = '';
      final m = d.mediaFields(const []);
      expect(m['photoUrls'], ['${_p}b']);
      expect(m['coverUrl'], '${_p}b');
    });
    test('limite de 6 conta a capa', () {
      final d = PlaceDraft(
        photoUrls: [for (var i = 0; i < 5; i++) '$_p$i'],
        pendingCoverPath: '/tmp/logo.jpg',
      );
      expect(d.photoCount, 6);
      final m = d.mediaFields(['${_p}extra'], uploadedCover: '${_p}logo');
      expect((m['photoUrls'] as List).length, 6);
      expect((m['photoUrls'] as List).first, '${_p}logo');
    });
    test('capa fora das fotos é descartada (como no backend)', () {
      final d = PlaceDraft(photoUrls: ['${_p}a'], coverUrl: 'https://x/y.jpg')
        ..extractCover();
      expect(d.coverUrl, '');
      expect(d.mediaFields(const [])['coverUrl'], '${_p}a');
    });
  });

  test('payload de edição (hours + timeZone + hoursNote) é JSON válido', () {
    final d = PlaceDraft(
      id: 'jb',
      name: 'John Burger',
      cityName: 'Toronto',
      stateName: 'Ontario',
      countryCode: 'CA',
      deliveryOnly: true,
      photoUrls: ['${_p}a'],
      coverUrl: '${_p}a',
    )
      ..extractCover()
      ..hours = PlaceHoursLogic.fromGroups([
        PlaceHoursGroup(days: {4, 5, 6}, opens: '15:00', closes: '21:00'),
      ]);
    final payload = {
      ...d.toFields(),
      'placeId': 'jb',
      ...d.mediaFields(const []),
      'menuPhotoUrls': <String>[],
    };
    final encoded = jsonEncode(payload);
    // Grava para o teste do backend validar o mesmo payload.
    final out = Platform.environment['REMDY_PAYLOAD_OUT'];
    if (out != null && out.isNotEmpty) File(out).writeAsStringSync(encoded);
    final back = jsonDecode(encoded) as Map<String, dynamic>;
    expect(back['timeZone'], 'America/Toronto');
    expect((back['hours'] as Map)['v'], 1);
    expect(back['hoursNote'], contains('Qui: 15:00-21:00'));
    expect(back['coverUrl'], '${_p}a');
  });

  test('texto que o Willian salvou no build 40 antigo é lido', () {
    const note = 'Thursday 15:00 - 21:00\nFriday.     15:00 - 21:00\n'
        'Saturday. 15:00 - 21:00';
    final s = PlaceHoursLogic.parseLegacy(note)!;
    expect(s.map((e) => e.weekday), [4, 5, 6]);
    expect(s.every((e) => e.opens == '15:00' && e.closes == '21:00'), isTrue);
  });

  test('hours estruturado vazio não esconde o texto antigo', () {
    expect(PlaceHoursLogic.fromJson(PlaceHoursLogic.toJson(const [])), isNull);
  });
}
