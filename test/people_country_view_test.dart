import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/people_country_hierarchy.dart';
import 'package:socialchat_mvp/services/people_country_view.dart';

CountryPerson p(String uid, String city, String state, double? lat, double? lng,
        {bool online = false,
        String hometown = '',
        String hometownState = '',
        String country = 'br'}) =>
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

Map<String, dynamic> navegantesViewer({bool hometown = true}) => {
      'homeCountryCode': 'br',
      'cityName': 'Navegantes',
      'stateName': 'SC',
      'cityLat': -26.8989,
      'cityLng': -48.6542,
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
    expect(uids(v.ownStateRows), ['floripa']);
    expect(v.otherStates.map((s) => s.key).toList(),
        ['PR', 'SP', 'ES', PeopleCountryHierarchy.otherKey]);
    expect(v.otherStates.first.label, 'Paraná');
    expect(v.otherStates.first.initiallyOpen, isTrue);
    expect(v.otherStates.skip(1).every((s) => !s.initiallyOpen), isTrue);
    expect(uids(v.otherStates.first.rows), ['cwb', 'cm']);
  });

  test('cidade natal: tag e motivos reais em "Em comum com você"', () {
    final v = CountryPeopleView.build(
        people: people, viewer: navegantesViewer(), countryCode: 'br');
    final cmRow =
        v.otherStates.first.rows.firstWhere((r) => r.person.uid == 'cm');
    expect(cmRow.isViewerHometown, isTrue);
    expect(
        v.otherStates.first.rows
            .firstWhere((r) => r.person.uid == 'cwb')
            .isViewerHometown,
        isFalse);
    final reasons = {for (final m in v.common) m.person.uid: m.reason};
    expect(reasons['floripa'], CommonReason.sameHometown);
    expect(reasons['cm'], CommonReason.livesInYourHometown);
    expect(reasons['nav'], CommonReason.sameCity);
    expect(reasons.containsKey('itj'), isFalse);
    expect(v.common.first.person.uid, 'floripa');
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
      },
      countryCode: 'br',
    );
    expect(v.hasReference, isTrue);
    expect(v.referenceIsHometown, isTrue);
    expect(v.referenceCity, 'Campo Mourão');
    expect(uids(v.nearby).first, 'cm');
    expect(v.nearby.first.isViewerHometown, isTrue);
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
}
