import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/invite_share_text.dart';

void main() {
  Map<String, dynamic> lang(String code) =>
      jsonDecode(File('lib/l10n/$code.json').readAsStringSync())
          as Map<String, dynamic>;

  test('link de convite com e sem código', () {
    expect(InviteShareText.link('ABC123'),
        'https://remdy.app/invite?ref=ABC123');
    expect(InviteShareText.link(''), 'https://remdy.app');
  });

  test('texto pt-BR novo, sem idiomas, com link no fim', () {
    final msg = InviteShareText.message('ABC123',
        template: lang('pt-BR')['invite_share_message'] as String);
    expect(msg, startsWith('Bora pro Remdy comigo? 👋'));
    expect(msg, contains('eventos da cidade'));
    expect(msg,
        endsWith('Entra pelo meu link: https://remdy.app/invite?ref=ABC123'));
    expect(msg.toLowerCase(), isNot(contains('idioma')));
  });

  test('todas as línguas têm o texto, com {link} e sem idiomas', () {
    for (final code in ['pt-BR', 'pt-PT', 'en', 'es', 'fr']) {
      final m = lang(code);
      final text = m['invite_share_message'] as String;
      expect(text, contains('{link}'), reason: code);
      expect(text.toLowerCase(),
          isNot(anyOf(contains('idioma'), contains('language'),
              contains('langue'))),
          reason: code);
      expect(m.containsKey('invite_share_description'), isFalse, reason: code);
    }
  });

  test('página de convite e bandeiras usam o mesmo texto', () {
    for (final f in [
      'lib/pages/invite_page.dart',
      'lib/pages/country_people_page.dart'
    ]) {
      expect(File(f).readAsStringSync(), contains('InviteShareText.message'),
          reason: f);
    }
  });
}
