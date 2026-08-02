import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const requiredKeys = <String>[
    'share_in_title',
    'share_in_choose_destination',
    'share_in_search',
    'share_in_private',
    'share_in_groups',
    'share_in_preview',
    'share_in_send',
    'share_in_cancel',
    'share_in_invalid',
    'share_in_unsupported_type',
    'share_in_empty_destinations',
    'share_in_sending',
    'share_in_sent',
    'share_in_failed',
    'share_in_login_needed',
    'share_in_no_permission',
  ];

  Map<String, dynamic> load(String name) {
    final file = File('lib/l10n/$name');
    return Map<String, dynamic>.from(jsonDecode(file.readAsStringSync()) as Map);
  }

  test('chaves share_in presentes em en, pt-BR, es, fr', () {
    for (final locale in ['en.json', 'pt-BR.json', 'es.json', 'fr.json']) {
      final map = load(locale);
      for (final key in requiredKeys) {
        expect(map.containsKey(key), isTrue, reason: '$locale missing $key');
        expect((map[key] as String).trim(), isNotEmpty, reason: '$locale empty $key');
      }
    }
  });

  test('pt-PT sobrescreve chaves share_in', () {
    final map = load('pt-PT.json');
    for (final key in requiredKeys) {
      expect(map.containsKey(key), isTrue, reason: 'pt-PT missing $key');
    }
  });
}
