import 'dart:io';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/locais/locais_strings.dart';

void main() {
  test('Cancelar e estrelas traduzidos nas 5 línguas', () {
    final cases = {
      const Locale('pt', 'BR'): ['Cancelar', '1 estrela', '3 estrelas'],
      const Locale('pt', 'PT'): ['Cancelar', '1 estrela', '3 estrelas'],
      const Locale('en'): ['Cancel', '1 star', '3 stars'],
      const Locale('es'): ['Cancelar', '1 estrella', '3 estrellas'],
      const Locale('fr'): ['Annuler', '1 étoile', '3 étoiles'],
    };
    cases.forEach((locale, expected) {
      final s = LocaisStrings.fromLocale(locale);
      expect([s.cancel, s.starTooltip(1), s.starTooltip(3)], expected,
          reason: '$locale');
    });
  });

  test('pt-PT usa português europeu nos textos de avaliação e contacto', () {
    final pt = LocaisStrings.fromLocale(const Locale('pt', 'PT'));
    final br = LocaisStrings.fromLocale(const Locale('pt', 'BR'));
    expect(pt.anonymous, 'Anónimo');
    expect(br.anonymous, 'Anônimo');
    expect(pt.postAnonymously, 'Publicar como anónimo');
    expect(pt.claimPhone, 'Telefone de contacto');
    expect(pt.website, 'Website');
  });

  test('sem "Cancelar" fixo no detalhe dos Locais', () {
    final src = File('lib/features/locais/ui/locais_detail_page.dart')
        .readAsStringSync();
    expect(src, isNot(contains("Text('Cancelar')")));
    expect(src, contains('strings.starTooltip(i)'));
  });
}
