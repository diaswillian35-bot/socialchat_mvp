import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/group_discovery_logic.dart';
import 'package:socialchat_mvp/services/iso_country_names.dart';

void main() {
  test('ISO global: BR resolve nos idiomas Remdy', () {
    expect(IsoCountryNames.displayName('br', 'pt-BR'), 'Brasil');
    expect(IsoCountryNames.displayName('BR', 'en'), 'Brazil');
    expect(IsoCountryNames.displayName('br', 'es'), isNotEmpty);
    expect(IsoCountryNames.displayName('br', 'fr'), isNotEmpty);
    expect(IsoCountryNames.displayName('br', 'pt-PT'), 'Brasil');
  });

  test('ISO global: países além de BR/CA/PT têm nome', () {
    expect(IsoCountryNames.displayName('us', 'pt'), isNotEmpty);
    expect(IsoCountryNames.displayName('jp', 'en'), isNotEmpty);
    expect(IsoCountryNames.displayName('de', 'es'), isNotEmpty);
    expect(IsoCountryNames.displayName('ar', 'fr'), isNotEmpty);
    expect(IsoCountryNames.displayName('mx', 'pt-BR'), isNotEmpty);
  });

  test('cardLocation usa ISO; Places English é ignorado', () {
    final loc = GroupDiscoveryLogic.cardLocation({
      'scope': 'city',
      'country': 'Brazil',
      'countryCode': 'br',
      'city': 'Navegantes',
    });
    expect(loc.country, 'br');
    expect(
      'Navegantes · ${IsoCountryNames.displayName(loc.country, 'pt-BR')}',
      'Navegantes · Brasil',
    );
    expect(
      'Região de Itajaí · ${IsoCountryNames.displayName('br', 'pt')}',
      'Região de Itajaí · Brasil',
    );
    expect(IsoCountryNames.displayName('br', 'pt'), 'Brasil');
  });

  test('tabelas cobrem dezenas de códigos ISO (não só 3 países)', () {
    expect(IsoCountryNames.byLanguage['en']!.length, greaterThan(100));
    expect(IsoCountryNames.byLanguage['pt']!.length, greaterThan(100));
    expect(IsoCountryNames.byLanguage['es']!.length, greaterThan(100));
    expect(IsoCountryNames.byLanguage['fr']!.length, greaterThan(100));
  });
}
