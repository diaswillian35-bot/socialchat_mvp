import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pt-BR: rótulo e legendas do "Aparecer para pessoas perto de mim"', () {
    final m = jsonDecode(File('lib/l10n/pt-BR.json').readAsStringSync())
        as Map<String, dynamic>;
    expect(m['show_people_near_me'], 'Aparecer para pessoas perto de mim');
    expect(m['people_nearby_visible_caption'],
        'Você aparece para quem está perto');
    expect(m['people_nearby_hidden_caption'],
        'Você não aparece para quem está perto');
  });

  test('todas as línguas têm rótulo, legendas e confirmações', () {
    for (final code in ['pt-BR', 'pt-PT', 'en', 'es', 'fr']) {
      final m = jsonDecode(File('lib/l10n/$code.json').readAsStringSync())
          as Map<String, dynamic>;
      for (final k in [
        'show_people_near_me',
        'people_nearby_visible_caption',
        'people_nearby_hidden_caption',
        'people_nearby_now_visible',
        'people_nearby_now_hidden',
      ]) {
        expect((m[k] ?? '').toString(), isNotEmpty, reason: '$code $k');
      }
    }
  });
}
