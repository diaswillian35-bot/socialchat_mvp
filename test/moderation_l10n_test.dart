import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const keys = <String, Map<String, String>>{
    'chat_image_blocked': {
      'pt-BR': 'Imagem removida por violar as regras',
      'pt-PT': 'Imagem removida por violar as regras',
      'en': 'Image removed for violating the rules',
      'es': 'Imagen eliminada por infringir las normas',
      'fr': 'Image supprimée pour non-respect des règles',
    },
    'chat_message_blocked': {
      'pt-BR': 'Mensagem removida por violar as regras',
      'pt-PT': 'Mensagem removida por violar as regras',
      'en': 'Message removed for violating the rules',
      'es': 'Mensaje eliminado por infringir las normas',
      'fr': 'Message supprimé pour non-respect des règles',
    },
    'content_filter_blocked': {
      'pt-BR': 'Esta mensagem foi bloqueada porque pode conter conteúdo impróprio ou abusivo.',
      'pt-PT': 'Esta mensagem foi bloqueada porque pode conter conteúdo impróprio ou abusivo.',
      'en': 'This message was blocked because it may contain objectionable or abusive content.',
      'es': 'Este mensaje se bloqueó porque puede contener contenido inapropiado o abusivo.',
      'fr': 'Ce message a été bloqué car il peut contenir du contenu inapproprié ou abusif.',
    },
  };

  Map<String, dynamic> read(String file) {
    final raw = File('lib/l10n/$file.json').readAsStringSync();
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  test('chaves novas de moderação existem nos 5 idiomas', () {
    for (final file in ['pt-BR', 'pt-PT', 'en', 'es', 'fr']) {
      final map = read(file);
      for (final entry in keys.entries) {
        expect(map[entry.key], entry.value[file], reason: '$file ${entry.key}');
      }
    }
  });
}
