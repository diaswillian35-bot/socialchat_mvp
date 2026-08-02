import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/events_country_scope.dart';
import 'package:socialchat_mvp/services/events_brasil_explore_logic.dart';
import 'package:socialchat_mvp/services/iso_country_names.dart';

void main() {
  String t(String key) {
    const map = {
      'events_country': 'País',
      'events_subdivisions_back_states': 'Estados',
      'events_subdivisions_back_provinces': 'Províncias',
      'events_subdivisions_back_regions': 'Regiões',
      'events_empty_subdivisions_states': 'Nenhum estado',
      'events_empty_subdivisions_provinces': 'Nenhuma província',
      'events_empty_subdivisions_regions': 'Nenhuma região',
      'events_empty_subdivision_state': 'vazio estado',
      'events_empty_subdivision_province': 'vazio província',
      'events_empty_subdivision_region': 'vazio região',
    };
    return map[key] ?? key;
  }

  group('normalizeCountryCode', () {
    test('trim + lower ISO', () {
      expect(EventsCountryScope.normalizeCountryCode(' CA '), 'ca');
      expect(EventsCountryScope.normalizeCountryCode('BR'), 'br');
    });

    test('rejeita nome ou vazio (sem fallback BR/CA)', () {
      expect(EventsCountryScope.normalizeCountryCode('Canada'), '');
      expect(EventsCountryScope.normalizeCountryCode('Brasil'), '');
      expect(EventsCountryScope.normalizeCountryCode(null), '');
      expect(EventsCountryScope.normalizeCountryCode(''), '');
      expect(EventsCountryScope.normalizeCountryCode('c'), '');
    });
  });

  group('perfil ca', () {
    const code = 'ca';

    test('aba e título mostram Canadá (pt)', () {
      final label = EventsCountryScope.scopeLabel(
        countryCode: code,
        languageCode: 'pt-BR',
        t: t,
      );
      expect(label, 'Canadá');
      expect(label.toLowerCase().contains('brasil'), isFalse);
      expect(EventsCountryScope.canQueryCountry(code), isTrue);
      expect(code, 'ca');
    });

    test('Ontario como província (não catalogo BR)', () {
      final events = [
        BrasilEventRef(
          id: '1',
          title: 'Show',
          city: 'Mississauga',
          stateName: 'Ontario',
          stateCode: 'ON',
          startAt: DateTime(2026, 8, 8),
          sponsored: false,
        ),
        BrasilEventRef(
          id: '2',
          title: 'SC',
          city: 'Florianópolis',
          stateName: 'Santa Catarina',
          stateCode: 'SC',
          startAt: DateTime(2026, 8, 9),
          sponsored: false,
        ),
      ];
      final summaries = EventsBrasilExploreLogic.buildStateSummaries(
        events: events.where((e) => true),
        userStateRaw: 'Ontario',
        preferBrazilCatalog: EventsCountryScope.isBrazil(code),
      );
      // Em produção a query já filtra countryCode==ca; aqui só o agrupamento.
      final names = summaries.map((s) => s.name).toList();
      expect(names, contains('Ontario'));
      expect(EventsCountryScope.isBrazil(code), isFalse);
      expect(
        EventsCountryScope.subdivisionsBackLabel(countryCode: code, t: t),
        'Províncias',
      );
    });

    test('consulta usa o mesmo código do rótulo', () {
      final normalized = EventsCountryScope.normalizeCountryCode('ca');
      final label = EventsCountryScope.displayName(normalized, 'pt');
      expect(normalized, 'ca');
      expect(label, 'Canadá');
    });
  });

  group('perfil br', () {
    const code = 'br';

    test('aba e título mostram Brasil', () {
      final label = EventsCountryScope.scopeLabel(
        countryCode: code,
        languageCode: 'pt-BR',
        t: t,
      );
      expect(label, 'Brasil');
      expect(label.toLowerCase().contains('canadá'), isFalse);
      expect(label.toLowerCase().contains('canada'), isFalse);
    });

    test('Santa Catarina como estado do catálogo BR', () {
      final events = [
        BrasilEventRef(
          id: '1',
          title: 'Floripa',
          city: 'Florianópolis',
          stateName: 'Santa Catarina',
          stateCode: 'SC',
          startAt: DateTime(2026, 8, 8),
          sponsored: false,
        ),
      ];
      final summaries = EventsBrasilExploreLogic.buildStateSummaries(
        events: events,
        userStateRaw: 'Santa Catarina',
        preferBrazilCatalog: EventsCountryScope.isBrazil(code),
      );
      expect(summaries.single.name, 'Santa Catarina');
      expect(summaries.single.uf, 'SC');
      expect(
        EventsCountryScope.subdivisionsBackLabel(countryCode: code, t: t),
        'Estados',
      );
    });
  });

  group('idioma', () {
    test('nome localizado sem mudar o código da query', () {
      const code = 'ca';
      expect(EventsCountryScope.displayName(code, 'en'), 'Canada');
      expect(EventsCountryScope.displayName(code, 'pt'), 'Canadá');
      expect(EventsCountryScope.displayName(code, 'fr'), 'Canada');
      expect(EventsCountryScope.displayName(code, 'es'), 'Canadá');
      expect(EventsCountryScope.normalizeCountryCode(code), 'ca');
    });

    test('IsoCountryNames alinhado ao helper', () {
      expect(
        EventsCountryScope.displayName('br', 'en'),
        IsoCountryNames.displayName('br', 'en'),
      );
    });
  });

  group('sem país', () {
    test('fallback seguro sem crash e sem query', () {
      expect(EventsCountryScope.normalizeCountryCode(null), '');
      expect(EventsCountryScope.canQueryCountry(''), isFalse);
      expect(
        EventsCountryScope.scopeLabel(
          countryCode: '',
          languageCode: 'pt',
          t: t,
        ),
        'País',
      );
    });
  });
}
