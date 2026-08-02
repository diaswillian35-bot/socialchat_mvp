import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Garante que as mensagens novas da lista de grupos existem (resolvidas) em
/// todos os 5 idiomas suportados e que os JSONs continuam válidos.
///
/// Regra do app (ver AppTexts.load): pt-PT herda pt-BR e sobrepõe. Portanto,
/// para pt-PT consideramos a mesclagem {pt-BR, ...pt-PT}.
void main() {
  const requiredKeys = <String>[
    'groups_load_error',
    'groups_error_permission',
    'groups_error_index',
    'groups_need_location',
    'groups_still_loading',
    'group_preview_join_hint',
    'group_join_network_error',
    'group_messages_load_error',
    'groups_tab_mine',
    'groups_tab_city',
    'groups_tab_region',
    'groups_tab_country',
    'groups_empty_mine',
    'groups_empty_city',
    'groups_empty_region',
    'groups_empty_country',
    'groups_request_pending',
    'groups_in_your_country',
    'user_search_retry',
    'no_groups_found',
  ];

  Map<String, dynamic> read(String file) {
    final raw = File('lib/l10n/$file.json').readAsStringSync();
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  test('todos os JSONs de idioma são válidos', () {
    for (final f in ['en', 'pt-BR', 'pt-PT', 'es', 'fr']) {
      expect(read(f), isA<Map<String, dynamic>>());
    }
  });

  test('en/pt-BR/es/fr contêm todas as chaves e não vazias', () {
    for (final f in ['en', 'pt-BR', 'es', 'fr']) {
      final map = read(f);
      for (final k in requiredKeys) {
        expect(map.containsKey(k), isTrue,
            reason: 'Falta "$k" em $f.json');
        expect((map[k] ?? '').toString().trim(), isNotEmpty,
            reason: '"$k" vazio em $f.json');
      }
    }
  });

  test('pt-PT resolve todas as chaves (herdando pt-BR)', () {
    final base = read('pt-BR');
    final override = read('pt-PT');
    final merged = <String, dynamic>{...base, ...override};
    for (final k in requiredKeys) {
      expect(merged.containsKey(k), isTrue, reason: 'Falta "$k" em pt-PT');
      expect((merged[k] ?? '').toString().trim(), isNotEmpty,
          reason: '"$k" vazio em pt-PT');
    }
  });
}
