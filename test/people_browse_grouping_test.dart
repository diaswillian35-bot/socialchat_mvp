import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/people_browse_grouping.dart';
import 'package:socialchat_mvp/utils/comcam_region.dart';

PeopleBrowseProfile _p({
  required String uid,
  required String city,
  required String state,
  String name = 'User',
}) {
  return PeopleBrowseProfile(
    uid: uid,
    name: name,
    city: city,
    state: state,
  );
}

void main() {
  group('PeopleBrowseGrouping hierarchy', () {
    test('two SC cities under 30 → single Santa Catarina + other cities', () {
      final profiles = [
        _p(uid: '1', city: 'Araranguá', state: 'SC', name: 'Adriana'),
        _p(uid: '2', city: 'Navegantes', state: 'SC', name: 'Bruno'),
        _p(uid: '3', city: 'Navegantes', state: 'Santa Catarina', name: 'Carla'),
      ];
      final groups = PeopleBrowseGrouping.group(
        profiles: profiles,
        citySectionMinProfiles: 30,
        otherCitiesLabel: 'Outras cidades do estado',
      );
      expect(groups, hasLength(1));
      expect(groups.single.stateLabel, 'Santa Catarina');
      expect(groups.single.sections, hasLength(1));
      expect(groups.single.sections.single.isOtherCitiesBucket, isTrue);
      expect(groups.single.sections.single.title, 'Outras cidades do estado');
      expect(groups.single.sections.single.profiles, hasLength(3));
      // No duplicate state / no city as top-level state.
      expect(groups.map((g) => g.stateLabel).toList(), ['Santa Catarina']);
      expect(
        PeopleBrowseGrouping.displayCityUnderName(profiles.first),
        'Araranguá, SC',
      );
    });

    test('Araranguá ≥30 nests under Santa Catarina; others stay in bucket', () {
      final profiles = [
        ...List.generate(
          30,
          (i) => _p(uid: 'a$i', city: 'Araranguá', state: 'SC'),
        ),
        _p(uid: 'n1', city: 'Navegantes', state: 'SC'),
      ];
      final groups = PeopleBrowseGrouping.group(
        profiles: profiles,
        citySectionMinProfiles: 30,
        otherCitiesLabel: 'Outras cidades do estado',
      );
      expect(groups, hasLength(1));
      expect(groups.single.stateLabel, 'Santa Catarina');
      expect(groups.single.sections, hasLength(2));
      expect(groups.single.sections.first.title, 'Araranguá');
      expect(groups.single.sections.first.isOtherCitiesBucket, isFalse);
      expect(groups.single.sections.first.profiles, hasLength(30));
      expect(groups.single.sections.last.isOtherCitiesBucket, isTrue);
      expect(groups.single.sections.last.profiles, hasLength(1));
    });

    test('Araranguá <30 stays in other cities (no promote with 1 profile)', () {
      final profiles = [
        _p(
          uid: 'legacy',
          name: 'Adriana Medeiros',
          city: 'Araranguá sc - Rua Asteróide Arantes - Vila Sao Jose',
          state: 'Araranguá - SC',
        ),
      ];
      final groups = PeopleBrowseGrouping.group(
        profiles: profiles,
        citySectionMinProfiles: 30,
        otherCitiesLabel: 'Outras cidades do estado',
      );
      expect(groups, hasLength(1));
      expect(groups.single.stateLabel, 'Santa Catarina');
      expect(groups.single.sections.single.isOtherCitiesBucket, isTrue);
      expect(
        groups.any((g) => g.stateLabel.contains('Araranguá')),
        isFalse,
      );
      expect(
        PeopleBrowseGrouping.displayCityUnderName(profiles.first),
        'Araranguá, SC',
      );
    });

    test('COMCAM nests under Paraná, not as sibling state of PR', () {
      final profiles = [
        _p(uid: '1', city: 'Peabiru', state: 'PR'),
        _p(uid: '2', city: 'Campo Mourão', state: 'Paraná'),
        _p(uid: '3', city: 'Curitiba', state: 'PR'),
      ];
      final groups = PeopleBrowseGrouping.group(
        profiles: profiles,
        citySectionMinProfiles: 30,
        otherCitiesLabel: 'Outras cidades do estado',
      );
      expect(groups, hasLength(1));
      expect(groups.single.stateLabel, 'Paraná');
      expect(
        groups.any((g) => g.stateLabel == ComcamRegion.unifiedRegionLabel),
        isFalse,
      );
      final titles = groups.single.sections.map((s) => s.title).toList();
      expect(titles.first, ComcamRegion.unifiedRegionLabel);
      expect(titles.last, 'Outras cidades do estado');
      expect(
        groups.single.sections
            .firstWhere((s) => s.title == ComcamRegion.unifiedRegionLabel)
            .profiles,
        hasLength(2),
      );
      expect(
        groups.single.sections
            .firstWhere((s) => s.isOtherCitiesBucket)
            .profiles
            .single
            .city,
        'Curitiba',
      );
    });

    test('no duplicate state headers for SC + legacy Araranguá - SC', () {
      final profiles = [
        _p(uid: '1', city: 'Navegantes', state: 'SC'),
        _p(
          uid: '2',
          city: 'Araranguá sc - Rua X',
          state: 'Araranguá - SC',
        ),
        _p(uid: '3', city: 'Florianópolis', state: 'Santa Catarina'),
      ];
      final groups = PeopleBrowseGrouping.group(
        profiles: profiles,
        citySectionMinProfiles: 30,
      );
      expect(groups.map((g) => g.stateLabel).toList(), ['Santa Catarina']);
    });

    test('titles never include public counts', () {
      final profiles = List.generate(
        30,
        (i) => _p(uid: '$i', city: 'Joinville', state: 'SC'),
      );
      final groups = PeopleBrowseGrouping.group(
        profiles: profiles,
        citySectionMinProfiles: 30,
      );
      for (final g in groups) {
        expect(g.stateLabel.contains(RegExp(r'\d')), isFalse);
        for (final s in g.sections) {
          expect(s.title.contains(RegExp(r'\d')), isFalse);
        }
      }
    });
  });

  group('PeopleBrowseLocation normalize', () {
    test('legacy state City - UF', () {
      final loc = PeopleBrowseGrouping.normalizeLocation(
        city: 'Araranguá sc - Rua Asteróide',
        state: 'Araranguá - SC',
      );
      expect(loc.stateDisplay, 'Santa Catarina');
      expect(loc.stateUf, 'SC');
      expect(loc.cityDisplay, 'Araranguá');
      expect(loc.isComcam, isFalse);
    });
  });
}
