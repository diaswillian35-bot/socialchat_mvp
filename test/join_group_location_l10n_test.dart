import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/pages/join_group_page.dart';
import 'package:socialchat_mvp/services/iso_country_names.dart';

void main() {
  Map<String, dynamic> cityGroup({
    String countryCode = 'br',
    String country = 'Brazil',
    String city = 'Navegantes',
  }) =>
      {
        'scope': 'city',
        'countryCode': countryCode,
        'country': country,
        'city': city,
        'cityName': city,
      };

  test('JoinGroupPage pt-BR: Brasil • Navegantes (ignora Places English)', () {
    final label = JoinGroupLocationLabel.format(
      cityGroup(),
      languageCode: 'pt-BR',
    );
    expect(label, 'Brasil • Navegantes');
    expect(label.contains('Brazil'), isFalse);
  });

  test('JoinGroupPage pt-PT: Brasil • Navegantes', () {
    expect(
      JoinGroupLocationLabel.format(cityGroup(), languageCode: 'pt-PT'),
      'Brasil • Navegantes',
    );
  });

  test('JoinGroupPage en: Brazil • Navegantes', () {
    expect(
      JoinGroupLocationLabel.format(cityGroup(), languageCode: 'en'),
      'Brazil • Navegantes',
    );
  });

  test('JoinGroupPage es e fr resolvem BR via ISO', () {
    final es = JoinGroupLocationLabel.format(cityGroup(), languageCode: 'es');
    final fr = JoinGroupLocationLabel.format(cityGroup(), languageCode: 'fr');
    expect(es.endsWith('• Navegantes'), isTrue);
    expect(fr.endsWith('• Navegantes'), isTrue);
    expect(es.contains('Brazil'), isFalse);
    expect(fr.toLowerCase().contains('brazil'), isFalse);
    expect(IsoCountryNames.displayName('br', 'es'), isNotEmpty);
    expect(IsoCountryNames.displayName('br', 'fr'), isNotEmpty);
  });

  test('JoinGroupPage ISO global: US JP DE AR MX BR nos 5 idiomas', () {
    const codes = ['us', 'jp', 'de', 'ar', 'mx', 'br'];
    const langs = ['pt-BR', 'pt-PT', 'en', 'es', 'fr'];
    for (final code in codes) {
      for (final lang in langs) {
        final label = JoinGroupLocationLabel.format(
          cityGroup(countryCode: code, country: 'IGNORE_PLACES_ENGLISH'),
          languageCode: lang,
        );
        expect(label, isNotEmpty, reason: '$code/$lang');
        expect(label.contains('IGNORE'), isFalse);
        // País traduzido a partir do ISO, nunca string Places.
        final translated = IsoCountryNames.displayName(code, lang);
        expect(label.startsWith(translated), isTrue, reason: '$code/$lang');
      }
    }
  });

  test('JoinGroupPage país-only não inclui cidade', () {
    final label = JoinGroupLocationLabel.format(
      {
        'scope': 'country',
        'countryCode': 'br',
        'country': 'Brazil',
        'city': 'Navegantes',
      },
      languageCode: 'pt-BR',
    );
    expect(label, 'Brasil');
    expect(label.contains('Navegantes'), isFalse);
  });
}
