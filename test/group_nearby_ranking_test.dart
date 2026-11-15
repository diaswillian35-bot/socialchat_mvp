import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/device_location_service.dart';
import 'package:socialchat_mvp/services/group_discovery_logic.dart';
import 'package:socialchat_mvp/services/group_nearby_logic.dart';
import 'package:socialchat_mvp/services/group_state_codes.dart';

void main() {
  // Centros de cidade (Places).
  const cm = [-24.0459, -52.3831]; // Campo Mourão-PR
  const maringa = [-23.4205, -51.9333]; // 83 km
  const curitiba = [-25.4284, -49.2733]; // 350 km
  const campinas = [-22.9099, -47.0626];
  const floripa = [-27.5954, -48.5480];

  var seq = 0;
  Map<String, dynamic> g(
    String id, {
    String scope = 'city',
    String cityKey = '',
    String state = 'PR',
    List<double>? at,
    String country = 'br',
    List<String> members = const ['owner'],
    Map<String, dynamic> extra = const {},
  }) {
    seq++;
    return {
      'id': id,
      'name': id,
      'scope': scope,
      'countryCode': country,
      'cityKey': cityKey,
      'stateName': scope == 'country' ? '' : state,
      if (at != null) 'latitude': at[0],
      if (at != null) 'longitude': at[1],
      if (scope == 'region' && at != null) ...{
        'regionCenterLat': at[0],
        'regionCenterLng': at[1],
        'regionRadiusKm': 110,
        'regionCenterCountryCode': country,
      },
      'deleted': false,
      'ownerId': 'owner',
      'members': members,
      'updatedAt': DateTime(2026, 11, 1).add(Duration(minutes: seq)),
      ...extra,
    };
  }

  GroupDiscoveryItem item(Map<String, dynamic> d, {String uid = 'me'}) =>
      GroupDiscoveryItem(
        id: d['id'] as String,
        data: d,
        isMember: GroupDiscoveryLogic.isParticipating(data: d, uid: uid),
      );

  const viewer = NearbyViewer(
    countryCode: 'br',
    cityKey: 'campo mourao',
    latitude: -24.0459,
    longitude: -52.3831,
    stateCode: 'PR',
    cityLabel: 'Campo Mourão',
    source: NearbyLocationSource.profile,
  );

  final docs = [
    g('amigos-cm', cityKey: 'campo mourao', at: cm, members: ['owner', 'me']),
    g('eventos-cm', cityKey: 'campo mourao', at: cm),
    g('boteco-maringa', scope: 'region', cityKey: 'maringa', at: maringa),
    g('curitiba', cityKey: 'curitiba', at: curitiba),
    g('nacional', scope: 'country'),
    g('campinas', cityKey: 'campinas', state: 'SP', at: campinas),
    g('floripa', cityKey: 'florianopolis', state: 'SC', at: floripa),
  ];

  test('seções na ordem cidade > região; estado, nacionais e outros ficam fora',
      () {
    final sections = GroupNearbyLogic.sections(
      items: docs.map(item).toList(),
      viewer: viewer,
    );
    expect(sections.map((s) => s.kind).toList(), [
      NearbySectionKind.city,
      NearbySectionKind.region,
    ]);
    expect(sections[0].items.map((e) => e.id).toSet(),
        {'amigos-cm', 'eventos-cm'});
    expect(sections[1].items.single.id, 'boteco-maringa');
    expect(
        GroupNearbyLogic.classify(docs[3], viewer), isNull); // Curitiba ~350 km
    expect(GroupNearbyLogic.classify(docs[4], viewer), isNull); // nacional
    expect(GroupNearbyLogic.classify(docs[5], viewer), isNull); // Campinas-SP
    expect(GroupNearbyLogic.classify(docs[6], viewer), isNull); // Floripa-SC
  });

  test('membro continua na seção, com isMember', () {
    final sections = GroupNearbyLogic.sections(
      items: docs.map(item).toList(),
      viewer: viewer,
    );
    final amigos = sections[0].items.firstWhere((e) => e.id == 'amigos-cm');
    expect(amigos.isMember, isTrue);
  });

  test('cada grupo aparece uma vez só', () {
    final list = [...docs.map(item), item(docs.first)];
    final sections = GroupNearbyLogic.sections(items: list, viewer: viewer);
    final ids = [for (final s in sections) ...s.items.map((e) => e.id)];
    expect(ids.length, ids.toSet().length);
  });

  test('Maringá (83 km) é região; cidade a 25 km é a mesma cidade', () {
    expect(
      GroupNearbyLogic.classify(docs[2], viewer),
      NearbySectionKind.region,
    );
    final vizinho = g('vizinho', cityKey: 'outra', at: [-24.15, -52.38]);
    expect(GroupNearbyLogic.classify(vizinho, viewer), NearbySectionKind.city);
    final cidade100 = g('c100', cityKey: 'x', at: [-24.95, -52.38]);
    expect(
      GroupNearbyLogic.classify(cidade100, viewer),
      NearbySectionKind.region,
    );
  });

  test('sem coordenadas no perfil: só entra a mesma cidade (cityKey/placeId)',
      () {
    const noPoint = NearbyViewer(
      countryCode: 'br',
      cityKey: 'campo mourao',
      stateCode: 'PR',
      source: NearbyLocationSource.profile,
    );
    expect(GroupNearbyLogic.classify(docs[0], noPoint), NearbySectionKind.city);
    expect(GroupNearbyLogic.classify(docs[2], noPoint), isNull);
    expect(GroupNearbyLogic.classify(docs[5], noPoint), isNull);
  });

  test('outro país, apagado, oculto e opt-out ficam fora', () {
    bool ok(Map<String, dynamic> d) => GroupNearbyLogic.eligible(
          data: d,
          uid: 'me',
          viewerCountryCode: 'br',
        );
    expect(ok(docs.first), isTrue);
    expect(ok(g('toronto', country: 'ca', state: 'ON', at: [43.65, -79.38])),
        isFalse);
    expect(ok(g('del', at: cm, extra: {'deleted': true})), isFalse);
    expect(
        ok(g('hid', at: cm, extra: {
          'hiddenFor': ['me']
        })),
        isFalse);
    expect(ok(g('opt', at: cm, extra: {'discoverable': false})), isFalse);
    expect(ok({'id': 'legacy', 'countryCode': 'br'}), isFalse);
  });

  test('grupo de cidade a mais de 110 km não entra em Perto de você', () {
    expect(GroupNearbyLogic.classify(docs[3], viewer), isNull);
    expect(GroupNearbyLogic.includedInNearby(docs[3], viewer), isFalse);
  });

  test('stateKey novo tem prioridade; sem ele deriva de stateName', () {
    expect(GroupStateCodes.groupStateKey({'stateKey': 'br-pr'}, 'br'), 'br-pr');
    expect(
        GroupStateCodes.groupStateKey({'stateName': 'Paraná'}, 'br'), 'br-pr');
    expect(GroupStateCodes.groupStateKey({'stateName': 'Araranguá - SC'}, 'br'),
        'br-sc');
    expect(GroupStateCodes.groupStateKey({'stateName': 'Brasil'}, 'br'), '');
    expect(GroupStateCodes.normalize('ca', 'Québec'), 'QC');
    expect(GroupStateCodes.normalize('br', 'State of São Paulo'), 'SP');
  });

  test('PR, Paraná e br-pr são o mesmo estado; HHA8NM só com stateName PR', () {
    expect(GroupStateCodes.canonicalStateCode('br', stateName: 'PR'), 'PR');
    expect(GroupStateCodes.canonicalStateCode('br', stateName: 'Paraná'), 'PR');
    expect(GroupStateCodes.canonicalStateCode('br', stateKey: 'br-pr'), 'PR');
    expect(GroupStateCodes.canonicalStateCode('br', stateKey: 'PR'), 'PR');
    expect(GroupStateCodes.canonicalStateCode('br', stateCode: 'pr'), 'PR');
    expect(
      GroupStateCodes.canonicalStateCodeFromData({'stateName': 'PR'}, 'br'),
      'PR',
    );
    expect(
      GroupStateCodes.sameStateOrUndetermined(
        countryCode: 'br',
        groupData: {'stateName': 'PR'},
        viewerStateCode: 'Paraná',
      ),
      isTrue,
    );
    expect(
      GroupStateCodes.sameStateOrUndetermined(
        countryCode: 'br',
        groupData: {'stateKey': 'br-pr'},
        viewerStateCode: 'PR',
        viewerStateKey: 'br-pr',
      ),
      isTrue,
    );
    expect(
      GroupStateCodes.sameStateOrUndetermined(
        countryCode: 'br',
        groupData: {'stateName': 'Santa Catarina'},
        viewerStateCode: 'PR',
      ),
      isFalse,
    );
    // Estado indeterminado: não esconde.
    expect(
      GroupStateCodes.sameStateOrUndetermined(
        countryCode: 'br',
        groupData: {'stateName': ''},
        viewerStateCode: 'PR',
      ),
      isTrue,
    );
  });

  test('raio 110 km, mesmo estado e cidade sem coordenadas', () {
    const origin = NearbyViewer(
      countryCode: 'br',
      cityKey: 'campo mourao',
      latitude: -24.044,
      longitude: -52.381,
      stateCode: 'PR',
      source: NearbyLocationSource.profile,
    );

    final bc = g(
      'balneario',
      cityKey: 'balneario camboriu',
      state: 'SC',
      at: [-26.998, -48.633],
    );
    expect(GroupNearbyLogic.distanceToViewer(bc, origin)!, closeTo(499, 8));
    expect(GroupNearbyLogic.classify(bc, origin), isNull);

    // ~80 km ao norte do centro de Campo Mourão.
    const at80 = [-23.32518, -52.381];
    final pr80 = g('pr80', cityKey: 'cidade 80', state: 'PR', at: at80);
    expect(GroupNearbyLogic.distanceToViewer(pr80, origin)!, closeTo(80, 2));
    expect(GroupNearbyLogic.classify(pr80, origin), NearbySectionKind.region);
    expect(GroupNearbyLogic.includedInNearby(pr80, origin), isTrue);

    final sc80 = g('sc80', cityKey: 'cidade sc 80', state: 'SC', at: at80);
    expect(GroupNearbyLogic.distanceToViewer(sc80, origin)!, closeTo(80, 2));
    expect(GroupNearbyLogic.classify(sc80, origin), isNull);

    const at120 = [-22.96482, -52.381];
    final pr120 = g('pr120', cityKey: 'cidade 120', state: 'PR', at: at120);
    expect(GroupNearbyLogic.distanceToViewer(pr120, origin)!, closeTo(120, 2));
    expect(GroupNearbyLogic.classify(pr120, origin), isNull);

    final sameCityNoCoords = g(
      'cm-sem-coords',
      cityKey: 'campo mourao',
      state: 'PR',
    );
    expect(
      GroupNearbyLogic.classify(sameCityNoCoords, origin),
      NearbySectionKind.city,
    );

    final otherNoCoords = g(
      'cwb-sem-coords',
      cityKey: 'curitiba',
      state: 'PR',
    );
    expect(GroupNearbyLogic.classify(otherNoCoords, origin), isNull);

    // Sem estado no grupo: usa só o raio de 110 km.
    final noState80 = g('sem-uf-80', cityKey: 'x', state: '', at: at80);
    expect(
      GroupNearbyLogic.classify(noState80, origin),
      NearbySectionKind.region,
    );

    // Nacional não entra, mesmo perto.
    final nationalNear = g(
      'nacional-perto',
      scope: 'country',
      state: '',
      at: at80,
    );
    expect(GroupNearbyLogic.classify(nationalNear, origin), isNull);
  });

  test('vazio de Perto de você reutiliza o texto da região', () {
    expect(
      GroupDiscoveryLogic.emptyMessageKey(GroupDiscoveryTab.nearby),
      'groups_empty_region',
    );
  });

  test('nomes de estado e província nos idiomas', () {
    expect(
      GroupStateCodes.displayName(countryCode: 'br', stateCode: 'PR'),
      'Paraná',
    );
    expect(
      GroupStateCodes.displayName(
          countryCode: 'ca', stateCode: 'QC', languageCode: 'fr'),
      'Québec',
    );
    expect(
      GroupStateCodes.displayName(
          countryCode: 'ca', stateCode: 'BC', languageCode: 'pt-BR'),
      'Colúmbia Britânica',
    );
    expect(GroupStateCodes.usesProvince('ca'), isTrue);
    expect(GroupStateCodes.usesProvince('br'), isFalse);
  });

  group('decisão GPS x perfil', () {
    const profile = NearbyViewer(
      countryCode: 'br',
      cityKey: 'campo mourao',
      latitude: -24.0459,
      longitude: -52.3831,
      stateCode: 'PR',
      cityLabel: 'Campo Mourão',
      source: NearbyLocationSource.profile,
    );

    test('primeira vez mostra o cartão e usa o perfil', () {
      final r = NearbyLocationDecision.decide(
        profile: profile,
        access: DeviceLocationAccess.notAsked,
        snoozed: false,
      );
      expect(r.banner, NearbyBanner.prompt);
      expect(r.viewer.source, NearbyLocationSource.profile);
    });

    test('"Agora não" por 30 dias vira a linha do perfil', () {
      final r = NearbyLocationDecision.decide(
        profile: profile,
        access: DeviceLocationAccess.notAsked,
        snoozed: true,
      );
      expect(r.banner, NearbyBanner.usingProfile);
    });

    test('negado usa o perfil com "Ativar localização"', () {
      for (final a in [
        DeviceLocationAccess.denied,
        DeviceLocationAccess.deniedForever,
        DeviceLocationAccess.serviceOff,
      ]) {
        final r = NearbyLocationDecision.decide(
          profile: profile,
          access: a,
          snoozed: false,
        );
        expect(r.banner, NearbyBanner.usingProfile, reason: a.name);
        expect(r.viewer.cityKey, 'campo mourao');
      }
    });

    test('GPS no país de cadastro manda no ponto, cidade e estado', () {
      final r = NearbyLocationDecision.decide(
        profile: profile,
        access: DeviceLocationAccess.granted,
        snoozed: false,
        fix: const DeviceLocationFix(
          latitude: -23.42,
          longitude: -51.93,
          countryCode: 'BR',
          cityName: 'Maringá',
          stateCode: 'PR',
        ),
      );
      expect(r.banner, NearbyBanner.none);
      expect(r.viewer.source, NearbyLocationSource.gps);
      expect(r.viewer.cityKey, 'maringa');
      expect(r.viewer.countryCode, 'br');
      expect(r.viewer.latitude, -23.42);
    });

    test('GPS fora do país é ignorado (isolamento do lançamento)', () {
      final r = NearbyLocationDecision.decide(
        profile: profile,
        access: DeviceLocationAccess.granted,
        snoozed: false,
        fix: const DeviceLocationFix(
          latitude: 43.65,
          longitude: -79.38,
          countryCode: 'ca',
          cityName: 'Toronto',
          stateCode: 'ON',
        ),
      );
      expect(r.banner, NearbyBanner.abroad);
      expect(r.viewer.countryCode, 'br');
      expect(r.viewer.source, NearbyLocationSource.profile);
    });

    test('geocoder sem país: fica com o perfil, sem aviso', () {
      final r = NearbyLocationDecision.decide(
        profile: profile,
        access: DeviceLocationAccess.granted,
        snoozed: false,
        fix: const DeviceLocationFix(latitude: -23.42, longitude: -51.93),
      );
      expect(r.banner, NearbyBanner.none);
      expect(r.viewer.source, NearbyLocationSource.profile);
    });

    test('admin vendo outro país não usa GPS nem cidade', () {
      final r = NearbyLocationDecision.decide(
        profile: const NearbyViewer(countryCode: 'ca'),
        access: DeviceLocationAccess.granted,
        snoozed: false,
        adminOtherCountry: true,
      );
      expect(r.banner, NearbyBanner.none);
      expect(r.viewer.cityKey, '');
    });

    test('sem cidade no perfil e negado: sem linha', () {
      final r = NearbyLocationDecision.decide(
        profile: const NearbyViewer(countryCode: 'br'),
        access: DeviceLocationAccess.denied,
        snoozed: false,
      );
      expect(r.banner, NearbyBanner.none);
    });
  });

  test('chip Perto de você é o primeiro e o padrão', () {
    expect(GroupDiscoveryTab.values.first, GroupDiscoveryTab.nearby);
    expect(GroupDiscoveryLogic.tabLabelKey(GroupDiscoveryTab.nearby),
        'groups_tab_nearby');
    final page = File('lib/pages/groups_list_page.dart').readAsStringSync();
    expect(
        page, contains('GroupDiscoveryTab _tab = GroupDiscoveryTab.nearby;'));
    expect(
      GroupDiscoveryLogic.locationComplete(
        tab: GroupDiscoveryTab.nearby,
        countryCode: 'br',
        cityKey: '',
        cityLatitude: null,
        cityLongitude: null,
      ),
      isTrue,
    );
  });

  test('textos novos existem e não estão vazios nos 5 idiomas', () {
    const keys = [
      'groups_tab_nearby',
      'groups_tab_nearby_a11y',
      'groups_section_city',
      'groups_section_region',
      'groups_section_your_state',
      'groups_section_your_province',
      'groups_section_national',
      'groups_section_other_states',
      'groups_section_other_provinces',
      'groups_section_count_one',
      'groups_section_count_many',
      'groups_near_city',
      'groups_location_prompt_title',
      'groups_location_prompt_body',
      'groups_location_prompt_allow',
      'groups_location_prompt_later',
      'groups_location_using_profile',
      'groups_location_meanwhile_profile',
      'groups_location_enable',
      'groups_location_abroad',
      'create_group_city_helper',
    ];
    for (final l in ['pt-BR', 'pt-PT', 'en', 'es', 'fr']) {
      final map = jsonDecode(File('lib/l10n/$l.json').readAsStringSync())
          as Map<String, dynamic>;
      for (final k in keys) {
        expect((map[k] ?? '').toString().trim(), isNotEmpty, reason: '$l $k');
      }
      expect(map['groups_section_count_many'], contains('{n}'), reason: l);
      for (final k in [
        'groups_near_city',
        'groups_location_using_profile',
        'groups_location_meanwhile_profile',
        'groups_location_abroad',
      ]) {
        expect(map[k], contains('{city}'), reason: '$l $k');
      }
    }
  });
}
