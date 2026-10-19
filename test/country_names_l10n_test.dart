import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/data/countries_data.dart';
import 'package:socialchat_mvp/data/country_names_l10n.dart';

void main() {
  test('todos os países da lista têm nome em en, es e fr', () {
    for (final lang in ['en', 'es', 'fr']) {
      for (final c in countriesData) {
        final name = localizedCountryName(c.code, '', lang);
        expect(name, isNotEmpty, reason: '$lang ${c.code}');
      }
    }
  });

  test('exemplos e fallback para o nome em português', () {
    expect(localizedCountryName('br', 'Brasil', 'en'), 'Brazil');
    expect(localizedCountryName('br', 'Brasil', 'fr'), 'Brésil');
    expect(localizedCountryName('nl', 'Holanda', 'pt-PT'), 'Países Baixos');
    expect(localizedCountryName('ca', 'Canadá', 'pt-PT'), 'Canadá');
    expect(localizedCountryName('ca', 'Canadá', 'pt-BR'), 'Canadá');
    expect(localizedCountryName('zz', 'Outro', 'en'), 'Outro');
  });
}
