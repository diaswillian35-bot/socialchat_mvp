import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/people_country_hierarchy.dart';
import 'package:socialchat_mvp/services/people_country_view.dart';

CountryPerson p(String uid, String city, String state, double? lat, double? lng,
        {bool online = false,
        String hometown = '',
        String hometownState = '',
        String country = 'br',
        List<String> interests = const [],
        String about = '',
        String languages = ''}) =>
    CountryPerson(
      uid: uid,
      name: uid,
      city: city,
      subdivision: state,
      countryCode: country,
      latitude: lat,
      longitude: lng,
      online: online,
      hometownCity: hometown,
      hometownSubdivision: hometownState,
      hometownCountryCode: hometown.isEmpty ? '' : 'br',
      interests: interests,
      about: about,
      languages: languages,
    );

final people = [
  p('nav', 'Navegantes', 'SC', -26.8989, -48.6542),
  p('itj', 'Itajaí', 'SC', -26.9078, -48.6619, online: true),
  p('bc', 'Balneário Camboriú', 'SC', -26.9906, -48.6348),
  p('penha', 'Penha', 'SC', -26.7700, -48.6458),
  p('bv', 'Barra Velha', 'SC', -26.6322, -48.6847),
  p('floripa', 'Florianópolis', 'SC', -27.5954, -48.5480,
      hometown: 'Campo Mourão', hometownState: 'PR'),
  p('cwb', 'Curitiba', 'PR', -25.4284, -49.2733),
  p('cm', 'Campo Mourão', 'Paraná', -24.0458, -52.3832),
  p('sp', 'São Paulo', 'SP', -23.5505, -46.6333),
  p('es', 'Cariacica', 'ES', -20.2635, -40.4165),
  p('brasil', 'Algum lugar', 'Brasil', null, null),
];

Map<String, dynamic> navegantesViewer({
  bool hometown = true,
  List<String> interests = const [],
}) =>
    {
      'homeCountryCode': 'br',
      'cityName': 'Navegantes',
      'stateName': 'SC',
      'cityLat': -26.8989,
      'cityLng': -48.6542,
      if (interests.isNotEmpty) 'interests': interests,
      if (hometown) ...{
        'hometownCity': 'Campo Mourão',
        'hometownState': 'PR',
        'hometownCountryCode': 'br',
      },
    };

List<String> uids(Iterable<CountryPeopleRow> rows) =>
    rows.map((r) => r.person.uid).toList();

void main() {
  test('Navegantes: perto de você junta cidade + região por distância', () {
    final v = CountryPeopleView.build(
        people: people, viewer: navegantesViewer(), countryCode: 'br');
    expect(v.hasReference, isTrue);
    expect(v.referenceIsHometown, isFalse);
    expect(v.referenceCity, 'Navegantes');
    expect(uids(v.nearby), ['nav', 'itj', 'bc', 'penha', 'bv']);
    expect(v.nearby.first.distanceKm, isNull); // mesma cidade: sem km
    expect(v.nearby[1].distanceKm!.round(), inInclusiveRange(1, 3));
    expect(v.ownStateLabel, 'Santa Catarina');
    // Sem interesses em comum, floripa fica no estado (não vai para Em comum).
    expect(uids(v.ownStateRows), ['floripa']);
    expect(v.otherStates.map((s) => s.key).toList(),
        ['PR', 'SP', 'ES', PeopleCountryHierarchy.otherKey]);
    expect(v.otherStates.first.label, 'Paraná');
    expect(v.otherStates.first.initiallyOpen, isTrue);
    expect(v.otherStates.skip(1).every((s) => !s.initiallyOpen), isTrue);
    expect(uids(v.otherStates.first.rows), ['cwb', 'cm']);
  });

  test('cidade natal e mesma cidade NÃO entram mais em Em comum', () {
    final v = CountryPeopleView.build(
        people: people, viewer: navegantesViewer(), countryCode: 'br');
    expect(v.common, isEmpty);
    expect(uids(v.otherStates.first.rows), containsAll(['cwb', 'cm']));
    expect(uids(v.nearby), contains('nav'));
    expect(uids(v.ownStateRows), contains('floripa'));
  });

  test('sem cidade natal e sem ninguém em comum: seção some', () {
    final v = CountryPeopleView.build(
        people: people.where((x) => x.uid != 'nav').toList(),
        viewer: navegantesViewer(hometown: false),
        countryCode: 'br');
    expect(v.common, isEmpty);
    expect(v.referenceCityEmpty, isTrue);
    expect(v.nearby.every((r) => !r.isViewerHometown), isTrue);
  });

  test('chips: estado de quem vê primeiro, depois por distância, Outros no fim',
      () {
    final v = CountryPeopleView.build(
        people: people, viewer: navegantesViewer(), countryCode: 'br');
    expect(v.chips.map((c) => c.label).toList(),
        ['SC', 'PR', 'SP', 'ES', PeopleCountryHierarchy.otherKey]);
    expect(v.chips.first.count, 6);
    expect(v.chips[1].count, 2);
  });

  test('chip PR filtra a lista e abre o estado', () {
    final v = CountryPeopleView.build(
        people: people,
        viewer: navegantesViewer(),
        countryCode: 'br',
        stateFilter: 'PR');
    expect(v.nearby, isEmpty);
    expect(v.ownStateRows, isEmpty);
    expect(v.otherStates.single.key, 'PR');
    expect(v.otherStates.single.initiallyOpen, isTrue);
    expect(v.common, isEmpty);
    // Chips continuam todos visíveis.
    expect(v.chips.length, 5);
  });

  test('quem vê do exterior com cidade natal usa a natal como referência', () {
    final v = CountryPeopleView.build(
      people: people,
      viewer: {
        'homeCountryCode': 'ca',
        'cityName': 'York',
        'stateName': 'ON',
        'cityLat': 43.69,
        'cityLng': -79.48,
        'hometownCity': 'Campo Mourão',
        'hometownState': 'PR',
        'hometownCountryCode': 'br',
        'interests': ['music'],
      },
      countryCode: 'br',
    );
    expect(v.hasReference, isTrue);
    expect(v.referenceIsHometown, isTrue);
    expect(v.referenceCity, 'Campo Mourão');
    // Chip de outro país: Em comum some, mesmo com interesses.
    expect(v.common, isEmpty);
    expect(uids(v.nearby), contains('cm'));
    expect(v.ownStateLabel, 'Paraná');
    expect(uids(v.ownStateRows), ['cwb']);
    expect(v.otherStates.first.key, 'SC');
  });

  test('exterior sem cidade natal: só estados, os 2 primeiros abertos', () {
    final v = CountryPeopleView.build(
      people: people,
      viewer: {'homeCountryCode': 'ca', 'cityName': 'York', 'stateName': 'ON'},
      countryCode: 'br',
    );
    expect(v.hasReference, isFalse);
    expect(v.nearby, isEmpty);
    expect(v.otherStates.map((s) => s.key).toList(),
        ['SC', 'PR', 'ES', 'SP', PeopleCountryHierarchy.otherKey]);
    expect(v.otherStates.map((s) => s.initiallyOpen).toList(),
        [true, true, false, false, false]);
    expect(v.otherStates.first.rows.every((r) => r.distanceKm == null), isTrue);
  });

  test('cidade natal sem coordenadas e sem ninguém de lá: layout do exterior',
      () {
    final v = CountryPeopleView.build(
      people: people,
      viewer: {
        'homeCountryCode': 'ca',
        'cityName': 'York',
        'hometownCity': 'Peabiru',
        'hometownState': 'PR',
        'hometownCountryCode': 'br',
      },
      countryCode: 'br',
    );
    expect(v.hasReference, isFalse);
    expect(v.common, isEmpty);
  });

  test('país sem ninguém: lista vazia para o cartão de convite', () {
    final v = CountryPeopleView.build(
        people: const [], viewer: navegantesViewer(), countryCode: 'br');
    expect(v.total, 0);
    expect(v.nearby, isEmpty);
    expect(v.otherStates, isEmpty);
    expect(v.chips, isEmpty);
    expect(v.referenceCityEmpty, isTrue);
  });

  test('preposição do estado em português', () {
    expect(ptStatePreposition('PR'), 'do');
    expect(ptStatePreposition('BA'), 'da');
    expect(ptStatePreposition('SC'), 'de');
    expect(ptStatePreposition('ontario'), 'de');
  });

  test('HometownInfo e chave normalizada', () {
    final h = HometownInfo.fromUserData({
      'hometownCity': 'Campo Mourão',
      'hometownState': 'Paraná',
      'hometownCountryCode': 'BR',
      'hometownLat': -24.04,
      'hometownLng': -52.38,
    })!;
    expect(h.key, 'br|PR|campo mourao');
    expect(h.latitude, -24.04);
    expect(HometownInfo.fromUserData({'hometownCity': 'X'}), isNull);
    expect(sameHometownPlace('br|PR|campo mourao', 'br||campo mourao'), isTrue);
    expect(
        sameHometownPlace('br|PR|campo mourao', 'br|SC|campo mourao'), isFalse);
  });

  test('Em comum no país da conta: só interesses reais, sem completar com cidade',
      () {
    final list = [
      ...people,
      p('ana', 'Curitiba', 'PR', -25.4284, -49.2733,
          interests: ['music', 'tech'], about: 'Olá', languages: 'pt'),
      p('bruno', 'Navegantes', 'SC', -26.8989, -48.6542,
          interests: ['music']),
    ];
    final v = CountryPeopleView.build(
      people: list,
      viewer: navegantesViewer(interests: ['music', 'tech', 'bars']),
      countryCode: 'br',
    );
    expect(v.common.map((m) => m.person.uid).toList(), ['ana', 'bruno']);
    expect(v.common.every((m) => m.reason == CommonReason.sharedInterests),
        isTrue);
    // Quem está em Em comum não se repete abaixo (exceto mesma cidade? bruno é mesma cidade)
    expect(uids(v.nearby), isNot(contains('bruno')));
    expect(uids(v.otherStates.expand((s) => s.rows)), isNot(contains('ana')));
    // vizinhos sem interesse comum continuam em Perto de você
    expect(uids(v.nearby), containsAll(['nav', 'itj']));
  });

  test('Em comum prioriza quem tem bio e idioma', () {
    final list = [
      p('sem', 'Itajaí', 'SC', -26.9078, -48.6619,
          interests: ['music', 'tech']),
      p('com', 'Itajaí', 'SC', -26.9078, -48.6619,
          interests: ['music'], about: 'Bio', languages: 'Português'),
    ];
    final v = CountryPeopleView.build(
      people: list,
      viewer: navegantesViewer(interests: ['music', 'tech']),
      countryCode: 'br',
    );
    expect(v.common.map((m) => m.person.uid).toList(), ['com', 'sem']);
    // Mesmo com menos interesses, quem tem bio+idioma vem primeiro.
    expect(v.common.first.interests, ['music']);
    expect(v.common.last.interests, ['music', 'tech']);
  });

  test('Em comum some no chip de outro país', () {
    final list = [
      p('ana', 'York', 'ON', 43.69, -79.48,
          country: 'ca', interests: ['music'], about: 'Hi', languages: 'en'),
    ];
    final v = CountryPeopleView.build(
      people: list,
      viewer: {
        'homeCountryCode': 'br',
        'countryCode': 'br',
        'cityName': 'Navegantes',
        'stateName': 'SC',
        'interests': ['music'],
      },
      countryCode: 'ca',
    );
    expect(v.common, isEmpty);
  });

  test('Em comum some quando ninguém compartilha interesse', () {
    final v = CountryPeopleView.build(
      people: [
        p('ana', 'Curitiba', 'PR', -25.42, -49.27, interests: ['football']),
      ],
      viewer: navegantesViewer(interests: ['music']),
      countryCode: 'br',
    );
    expect(v.common, isEmpty);
  });
}
