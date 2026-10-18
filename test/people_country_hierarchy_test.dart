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

void main() {
  test('BR: cidade, região, próximas e demais estados respeitam distância', () {
    final h = PeopleCountryHierarchy.build(
        viewer: viewer('Campo Mourão', 'PR', 'br', -24.04, -52.38),
        people: [
          p('same', 'Campo Mourão', 'PR', 'br', -24.04, -52.38),
          p('region', 'Peabiru', 'PR', 'br', -23.91, -52.34),
          p('near', 'Londrina', 'PR', 'br', -23.31, -51.16),
          p('far', 'São Paulo', 'SP', 'br', -23.55, -46.63),
        ]);
    expect(h.sameCity?.people.single.uid, 'same');
    expect(h.region.single.people.single.uid, 'region');
    expect(h.nearbyCities.single.people.single.uid, 'near');
    expect(h.remaining.single.label, 'SP');
  });

  test('CA: province is generic subdivision and cities are collapsible groups',
      () {
    final h = PeopleCountryHierarchy.build(
        viewer: viewer('Toronto', 'Ontario', 'ca', 43.65, -79.38),
        people: [
          p('tor', 'Toronto', 'Ontario', 'ca', 43.65, -79.38),
          p('ham', 'Hamilton', 'Ontario', 'ca', 43.25, -79.87),
          p('van', 'Vancouver', 'British Columbia', 'ca', 49.28, -123.12),
        ]);
    expect(h.sameCity?.label, 'Toronto');
    expect(h.region.single.label, 'Hamilton');
    expect(h.remaining.single.label, 'British Columbia');
  });

  test('PT: district preserved and missing coords never classified nearby', () {
    final h = PeopleCountryHierarchy.build(
        viewer: viewer('Porto', 'Porto', 'pt', 41.15, -8.61),
        people: [
          p('missing', 'Matosinhos', 'Porto', 'pt', null, null),
          p('lisbon', 'Lisboa', 'Lisboa', 'pt', 38.72, -9.14),
        ]);
    expect(h.region, isEmpty);
    expect(
        h.remaining
            .expand((s) => s.cities)
            .expand((c) => c.people)
            .map((p) => p.uid),
        contains('missing'));
  });

  test('online first then stable name and uid', () {
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

  test('viewer without coordinates falls back to subdivision/city only', () {
    final h = PeopleCountryHierarchy.build(
        viewer: viewer('York', 'Ontario', 'ca', null, null),
        people: [
          p('u', 'York', 'Ontario', 'ca', 43.7, -79.45),
        ]);
    expect(h.sameCity, isNull);
    expect(h.region, isEmpty);
    expect(h.nearbyCities, isEmpty);
    expect(h.remaining.single.cities.single.label, 'York');
  });

  test('COMCAM remains a special regional section when applicable', () {
    final h = PeopleCountryHierarchy.build(
        viewer: viewer('Campo Mourão', 'PR', 'br', -24.04, -52.38),
        people: [
          p('peabiru', 'Peabiru', 'PR', 'br', -23.91, -52.34),
          p('maringa', 'Maringá', 'PR', 'br', -23.42, -51.93),
        ]);
    expect(h.region.first.label, contains('COMCAM'));
    expect(h.region.first.people.single.uid, 'peabiru');
  });

  test('different selected country never receives cross-border proximity', () {
    final h = PeopleCountryHierarchy.build(
        viewer: viewer('Detroit', 'Michigan', 'us', 42.33, -83.05),
        people: [p('windsor', 'Windsor', 'Ontario', 'ca', 42.31, -83.04)]);
    expect(h.sameCity, isNull);
    expect(h.region, isEmpty);
    expect(h.nearbyCities, isEmpty);
    expect(h.remaining.single.cities.single.label, 'Windsor');
  });
}
