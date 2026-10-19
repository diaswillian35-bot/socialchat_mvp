import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/people_country_hierarchy.dart';

CountryPerson p(String uid, String city, String state, String country,
        double? lat, double? lng, {bool online = false, String? name}) =>
    CountryPerson(
        uid: uid,
        name: name ?? uid,
        city: city,
        subdivision: state,
        countryCode: country,
        latitude: lat,
        longitude: lng,
        online: online);

Map<String, dynamic> viewer(
        String city, String state, String country, double? lat, double? lng) =>
    {
      'cityName': city,
      'stateName': state,
      'homeCountryCode': country,
      if (lat != null) 'cityLat': lat,
      if (lng != null) 'cityLng': lng,
    };

List<String> uidsOf(Iterable<CountryCityGroup> cities) =>
    cities.expand((c) => c.people).map((e) => e.uid).toList();

void main() {
  final navegantes = viewer('Navegantes', 'SC', 'br', -26.8989, -48.6542);
  final brPeople = [
    p('nav1', 'Navegantes', 'SC', 'br', -26.8989, -48.6542),
    p('nav2', 'navegantes', 'Santa Catarina', 'br', -26.8989, -48.6542),
    p('itj', 'Itajaí', 'SC', 'br', -26.9078, -48.6619),
    p('bc', 'Balneário Camboriú', 'SC', 'br', -26.9906, -48.6348),
    p('penha', 'Penha', 'SC', 'br', -26.7700, -48.6458),
    p('bv', 'Barra Velha', 'SC', 'br', -26.6322, -48.6847),
    p('floripa', 'Florianópolis', 'SC', 'br', -27.5954, -48.5480),
    p('ararangua', 'Araranguá', 'Araranguá - SC', 'br', -28.9356, -49.4918),
    p('cwb', 'Curitiba', 'PR', 'br', -25.4284, -49.2733),
    p('sp', 'São Paulo', 'SP', 'br', -23.5505, -46.6333),
    p('nocity', '', 'SP', 'br', null, null),
    p('brasil', 'Algum lugar', 'Brasil', 'br', null, null),
  ];

  test('Navegantes: cidade, região, outras cidades de SC, demais estados', () {
    final h =
        PeopleCountryHierarchy.build(viewer: navegantes, people: brPeople);
    expect(h.viewerLocated, isTrue);
    expect(h.sameCity!.people.map((e) => e.uid).toSet(), {'nav1', 'nav2'});
    // Região aberta: Itajaí, BC, Penha e Barra Velha, por distância.
    expect(uidsOf(h.region), ['itj', 'bc', 'penha', 'bv']);
    // Outras cidades de Santa Catarina (inclui "Araranguá - SC" normalizado).
    expect(h.viewerSubdivision!.key, 'SC');
    expect(h.viewerSubdivision!.label, 'Santa Catarina');
    expect(uidsOf(h.viewerSubdivision!.cities), ['floripa', 'ararangua']);
    // Demais estados por distância: PR antes de SP, "Outros" por último.
    expect(h.remaining.map((s) => s.key).toList(),
        ['PR', 'SP', PeopleCountryHierarchy.otherKey]);
    expect(h.remaining.first.label, 'Paraná');
    // Sem cidade fica no fim do estado.
    expect(uidsOf(h.remaining[1].cities), ['sp', 'nocity']);
    expect(uidsOf(h.remaining.last.cities), ['brasil']);
  });

  test('ninguém some: todas as pessoas recebidas aparecem em alguma seção', () {
    final h =
        PeopleCountryHierarchy.build(viewer: navegantes, people: brPeople);
    final shown = <String>[
      ...uidsOf([if (h.sameCity != null) h.sameCity!]),
      ...uidsOf(h.region),
      ...uidsOf(h.viewerSubdivision?.cities ?? const []),
      ...uidsOf(h.remaining.expand((s) => s.cities)),
    ];
    expect(shown.toSet(), brPeople.map((e) => e.uid).toSet());
    expect(shown.length, brPeople.length);
  });

  test('quem vê do exterior: só estados, por quantidade e nome', () {
    final h = PeopleCountryHierarchy.build(
        viewer: viewer('York', 'ON', 'ca', 43.69, -79.48), people: brPeople);
    expect(h.viewerLocated, isFalse);
    expect(h.sameCity, isNull);
    expect(h.region, isEmpty);
    expect(h.viewerSubdivision, isNull);
    expect(h.remaining.map((s) => s.key).toList(),
        ['SC', 'SP', 'PR', PeopleCountryHierarchy.otherKey]);
    // Cidades por nome, sem cidade por último.
    expect(h.remaining.first.cities.map((c) => c.label).toList(), [
      'Araranguá',
      'Balneário Camboriú',
      'Barra Velha',
      'Florianópolis',
      'Itajaí',
      'Navegantes',
      'Penha',
    ]);
    expect(h.remaining[1].cities.last.label, '—');
  });

  test('normalização de estado', () {
    String k(String s) => PeopleCountryHierarchy.subdivisionKey(s, 'br');
    expect(k('SC'), 'SC');
    expect(k('Santa Catarina'), 'SC');
    expect(k('santa catarina'), 'SC');
    expect(k('Araranguá - SC'), 'SC');
    expect(k('Paraná'), 'PR');
    expect(k('Brasil'), PeopleCountryHierarchy.otherKey);
    expect(k(''), PeopleCountryHierarchy.otherKey);
    expect(PeopleCountryHierarchy.subdivisionKey('Ontario', 'ca'), 'ontario');
  });

  test('limpeza do nome da cidade', () {
    String c(String s) => PeopleCountryHierarchy.cleanCity(s, 'br');
    expect(c('Itajaí - SC'), 'Itajaí');
    expect(c('Araranguá sc - Rua Asteróide Arantes'), 'Araranguá');
    expect(c('Embu-Guaçu'), 'Embu-Guaçu');
    expect(c('Campo Mourão, PR'), 'Campo Mourão');
    expect(c('Mogi das Cruzes'), 'Mogi das Cruzes');
    final h = PeopleCountryHierarchy.build(
        viewer: viewer('Navegantes', 'SC', 'br', -26.8989, -48.6542),
        people: [
          p('a', 'Itajaí - SC', 'SC', 'br', -26.9078, -48.6619),
          p('b', 'Itajaí', 'SC', 'br', -26.9078, -48.6619),
        ]);
    expect(h.region.single.label, 'Itajaí');
    expect(h.region.single.people.length, 2);
  });

  test('COMCAM unificado para quem está na COMCAM', () {
    final h = PeopleCountryHierarchy.build(
        viewer: viewer('Campo Mourão', 'PR', 'br', -24.0458, -52.3832),
        people: [
          p('cm', 'Campo Mourao', 'PR', 'br', -24.0458, -52.3832),
          p('peabiru', 'Peabiru', 'PR', 'br', -23.91, -52.34),
          p('moreira', 'Moreira Sales', 'PR', 'br', -24.06, -53.01),
          p('maringa', 'Maringá', 'PR', 'br', -23.42, -51.93),
          p('nav', 'Navegantes', 'SC', 'br', -26.8989, -48.6542),
        ]);
    expect(h.sameCity!.people.single.uid, 'cm');
    expect(h.region.first.label, contains('COMCAM'));
    expect(uidsOf([h.region.first]).toSet(), {'peabiru', 'moreira'});
    expect(uidsOf(h.viewerSubdivision!.cities), ['maringa']);
    expect(h.remaining.single.key, 'SC');
  });

  test('online primeiro, depois nome e uid', () {
    final h = PeopleCountryHierarchy.build(
        viewer: viewer('Toronto', 'Ontario', 'ca', 43.65, -79.38),
        people: [
          p('2', 'Toronto', 'Ontario', 'ca', 43.65, -79.38, name: 'Ana'),
          p('3', 'Toronto', 'Ontario', 'ca', 43.65, -79.38,
              online: true, name: 'Zoe'),
          p('1', 'Toronto', 'Ontario', 'ca', 43.65, -79.38, name: 'Ana'),
        ]);
    expect(h.sameCity!.people.map((e) => e.uid).toList(), ['3', '1', '2']);
  });

  test('viewer sem coordenadas: cidade pelo nome, resto pelo estado', () {
    final h = PeopleCountryHierarchy.build(
        viewer: viewer('York', 'Ontario', 'ca', null, null),
        people: [
          p('u', 'York', 'Ontario', 'ca', 43.7, -79.45),
          p('h', 'Hamilton', 'Ontario', 'ca', 43.25, -79.87),
          p('v', 'Vancouver', 'British Columbia', 'ca', 49.28, -123.12),
        ]);
    expect(h.sameCity!.people.single.uid, 'u');
    expect(h.region, isEmpty);
    expect(uidsOf(h.viewerSubdivision!.cities), ['h']);
    expect(h.remaining.single.label, 'British Columbia');
  });

  test('país diferente nunca recebe proximidade entre fronteiras', () {
    final h = PeopleCountryHierarchy.build(
        viewer: viewer('Detroit', 'Michigan', 'us', 42.33, -83.05),
        people: [p('windsor', 'Windsor', 'Ontario', 'ca', 42.31, -83.04)]);
    expect(h.sameCity, isNull);
    expect(h.region, isEmpty);
    expect(h.viewerSubdivision, isNull);
    expect(h.remaining.single.cities.single.label, 'Windsor');
  });
}
