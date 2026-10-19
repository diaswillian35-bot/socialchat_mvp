import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Garante que nenhuma língua fique sem texto (o app mostraria a chave crua).
/// pt-PT é carregado por cima do pt-BR (fallback intencional), então aqui só
/// é relatado, não reprovado.
Map<String, dynamic> _load(String code) =>
    jsonDecode(File('lib/l10n/$code.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  final ptBr = _load('pt-BR');
  final full = ['en', 'es', 'fr'];

  for (final code in full) {
    test('$code tem todas as chaves do pt-BR', () {
      final other = _load(code);
      final missing = ptBr.keys.where((k) => !other.containsKey(k)).toList()
        ..sort();
      expect(missing, isEmpty, reason: '$code sem: $missing');
    });

    test('pt-BR tem todas as chaves do $code', () {
      final other = _load(code);
      final missing = other.keys.where((k) => !ptBr.containsKey(k)).toList()
        ..sort();
      expect(missing, isEmpty, reason: 'pt-BR sem: $missing');
    });
  }

  test('nenhum texto vazio em nenhuma língua', () {
    for (final code in [...full, 'pt-BR', 'pt-PT']) {
      final m = _load(code);
      final empty = m.entries
          .where((e) => e.value is String && (e.value as String).trim().isEmpty)
          .map((e) => e.key)
          .toList();
      expect(empty, isEmpty, reason: '$code vazio: $empty');
    }
  });

  test('pt-PT: chaves que usam o texto do pt-BR (só relatório)', () {
    final ptPt = _load('pt-PT');
    final fallback = ptBr.keys.where((k) => !ptPt.containsKey(k)).length;
    // ignore: avoid_print
    print('pt-PT usa o texto pt-BR em $fallback de ${ptBr.length} chaves.');
    expect(fallback, lessThan(ptBr.length));
  });
}
