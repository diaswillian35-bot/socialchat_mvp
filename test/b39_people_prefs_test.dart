import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';
import 'package:socialchat_mvp/pages/welcome_choice_page.dart';
import 'package:socialchat_mvp/services/explore_only.dart';
import 'package:socialchat_mvp/services/interest_push_pref.dart';
import 'package:socialchat_mvp/services/nearby_visibility.dart';
import 'package:socialchat_mvp/services/people_country_hierarchy.dart';
import 'package:socialchat_mvp/services/people_country_view.dart';
import 'package:socialchat_mvp/services/profile_about.dart';
import 'package:socialchat_mvp/services/profile_photo.dart';
import 'package:socialchat_mvp/widgets/profile_photo_picker.dart';
import 'package:socialchat_mvp/services/user_interests.dart';
import 'package:socialchat_mvp/services/welcome_choice.dart';
import 'package:socialchat_mvp/widgets/explore_only_bar.dart';
import 'package:socialchat_mvp/widgets/hide_in_city_tile.dart';
import 'package:socialchat_mvp/widgets/interest_chips.dart';

Map<String, dynamic> _load(String code) =>
    jsonDecode(File('lib/l10n/$code.json').readAsStringSync())
        as Map<String, dynamic>;

String _src(String p) => File(p).readAsStringSync();

Future<void> _fonts() async {
  final dir =
      '${Platform.environment['FLUTTER_ROOT'] ?? '${Platform.environment['HOME']}/Downloads/flutter'}'
      '/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in [
    'Roboto-Regular',
    'Roboto-Medium',
    'Roboto-Bold',
    'Roboto-Black'
  ]) {
    final file = File('$dir/$f.ttf');
    if (file.existsSync()) {
      roboto
          .addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    }
  }
  await roboto.load();
  final icons = File('$dir/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await l.load();
  }
}

Widget _app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF313A5F),
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: Color(0xFF111827),
          onSurfaceVariant: Color(0xFF6B7280),
          primaryContainer: Color(0xFFE8EAF0),
          surfaceContainerHighest: Color(0xFFF1F5F9),
          outline: Color(0xFFE5E7EB),
        ),
      ),
      home: RepaintBoundary(key: const Key('shot'), child: home),
    );

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await expectLater(
      find.byKey(const Key('shot')), matchesGoldenFile('goldens/$name.png'));
}

CountryPerson _p(String uid, String city, List<String> interests,
        {String state = 'PR'}) =>
    CountryPerson(
      uid: uid,
      name: uid,
      city: city,
      subdivision: state,
      countryCode: 'br',
      interests: interests,
    );

void main() {
  final ptBr = _load('pt-BR');
  setUp(() => AppTexts.loadFromMap(ptBr, const Locale('pt', 'BR')));

  group('chaves novas nos 5 idiomas', () {
    final keys = <String>[
      'people_explore_only_switch',
      'people_explore_only_on_caption',
      'people_explore_only_off_caption',
      'menu_hide_in_city',
      'hide_in_city_info',
      'menu_interest_push',
      'welcome_title',
      'welcome_meet_title',
      'welcome_explore_title',
      'welcome_launch_free',
      'welcome_change_later',
      'interests_title',
      'interests_helper',
      'interests_max_reached',
      'people_reason_interest_one',
      'people_reason_interest_more',
      'about_you_hint',
      ...UserInterests.keys.map(UserInterests.l10nKey),
    ];
    for (final code in ['pt-BR', 'en', 'es', 'fr']) {
      test(code, () {
        final m = _load(code);
        final missing =
            keys.where((k) => (m[k] ?? '').toString().trim().isEmpty);
        expect(missing, isEmpty, reason: '$code sem: ${missing.toList()}');
      });
    }
    test('pt-PT: override só quando difere (resto cai no pt-BR)', () {
      final pt = _load('pt-PT');
      for (final k in keys) {
        if (pt.containsKey(k)) expect(pt[k], isNot(ptBr[k]), reason: k);
      }
      expect(pt['people_explore_only_switch'],
          'Não quero conhecer ninguém, só usar a app');
    });
    test('textos pedidos', () {
      expect(ptBr['people_explore_only_switch'],
          'Não quero conhecer ninguém, só usar o app');
      expect(ptBr['menu_hide_in_city'], 'Não aparecer na minha cidade');
      expect(ptBr['menu_interest_push'],
          'Avisos de pessoas com interesses em comum');
      expect(ptBr['welcome_meet_title'], 'Quero conhecer pessoas');
      expect(ptBr['welcome_explore_title'], 'Só explorar locais e eventos');
    });
  });

  group('switch Só explorar (barra de Conheça Pessoas)', () {
    testWidgets('mostra o texto novo e liga o modo', (tester) async {
      bool? got;
      await tester.pumpWidget(_app(Scaffold(
          bottomNavigationBar:
              ExploreOnlyBar(value: false, onChanged: (v) => got = v))));
      expect(find.text('Não quero conhecer ninguém, só usar o app'),
          findsOneWidget);
      expect(find.text('Aparecer para pessoas perto de mim'), findsNothing);
      await tester.tap(find.byKey(const Key('explore_only_switch')));
      expect(got, isTrue);
    });
    test('página usa a barra nova e a mesma lógica do Editar perfil', () {
      final s = _src('lib/pages/country_people_page.dart');
      expect(s.contains('ExploreOnlyBar('), isTrue);
      expect(s.contains('ExploreOnly.setMode(uid, value)'), isTrue);
      expect(s.contains("t.get('show_people_near_me')"), isFalse);
      final e = _src('lib/services/explore_only.dart');
      expect(e.contains('PresenceService.instance.stop()'), isTrue);
      expect(e.contains('PresenceService.instance.start()'), isTrue);
    });
  });

  group('switch Não aparecer na minha cidade (Menu)', () {
    test('lógica invertida de nearbyEnabled', () {
      expect(NearbyVisibility.payloadForHide(true), {'nearbyEnabled': false});
      expect(NearbyVisibility.payloadForHide(false), {'nearbyEnabled': true});
      expect(NearbyVisibility.hideInCityFromData({'nearbyEnabled': true}),
          isFalse);
      expect(NearbyVisibility.hideInCityFromData({}), isTrue);
      expect(InterestPushPref.enabledFromData({}), isTrue);
      expect(InterestPushPref.enabledFromData({'interestPushEnabled': false}),
          isFalse);
    });
    testWidgets('linha no Menu liga/desliga', (tester) async {
      bool? got;
      await tester.pumpWidget(_app(Scaffold(
          body: MenuSwitchTile(
              tileKey: const Key('t'),
              switchKey: const Key('s'),
              icon: Icons.location_off_rounded,
              title: AppTexts.current.get('menu_hide_in_city'),
              value: false,
              onChanged: (v) => got = v))));
      await tester.tap(find.byKey(const Key('s')));
      expect(got, isTrue);
    });
    test('Menu tem os dois switches no card de Idioma/Notificações', () {
      final s = _src('lib/pages/menu_page.dart');
      final n = s.indexOf("t.get('notifications')");
      expect(s.indexOf("t.get('menu_hide_in_city')"), greaterThan(n));
      expect(s.indexOf("t.get('menu_interest_push')"), greaterThan(n));
      expect(s.contains('NearbyVisibility.saveHideInCity'), isTrue);
    });
  });

  group('boas-vindas (uma vez só)', () {
    test('needsChoice', () {
      expect(WelcomeChoice.needsChoice({'profileComplete': true}), isTrue);
      expect(
          WelcomeChoice.needsChoice(
              {'profileComplete': true, 'welcomeChoiceDone': true}),
          isFalse);
      expect(WelcomeChoice.needsChoice({'profileComplete': false}), isFalse);
      expect(WelcomeChoice.needsChoice(null), isFalse);
    });
    testWidgets('aparece uma vez e ativa o modo Só explorar', (tester) async {
      // Simula o AuthGate: o doc ganha welcomeChoiceDone e exploreOnly.
      final doc = <String, dynamic>{'profileComplete': true};
      var shows = 0;
      Widget gate() => StatefulBuilder(builder: (context, setState) {
            if (!WelcomeChoice.needsChoice(doc)) {
              return const Scaffold(body: Text('HOME'));
            }
            shows++;
            return WelcomeChoicePage(onChoose: (explore) async {
              setState(() {
                doc[ExploreOnly.field] = explore;
                doc[WelcomeChoice.field] = true;
              });
            });
          });
      await tester.pumpWidget(_app(gate()));
      expect(find.text('Só explorar locais e eventos'), findsOneWidget);
      expect(find.text('Tudo grátis no lançamento'), findsOneWidget);
      await tester.tap(find.byKey(const Key('welcome_explore_only')));
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      expect(doc['exploreOnly'], isTrue);
      await tester.pumpWidget(_app(gate()));
      expect(find.text('HOME'), findsOneWidget);
      expect(shows, 1);
    });
    test('AuthGate grava via WelcomeChoice.complete', () {
      final s = _src('lib/pages/auth_gate.dart');
      expect(s.contains('WelcomeChoice.needsChoice'), isTrue);
      expect(s.contains('WelcomeChoice.complete'), isTrue);
      expect(
          _src('lib/services/welcome_choice.dart')
              .contains('ExploreOnly.setMode'),
          isTrue);
    });
  });

  group('interesses', () {
    test('lista fixa, limite 20 e só chaves', () {
      expect(UserInterests.keys.length, greaterThanOrEqualTo(16));
      expect(UserInterests.sanitize(['music', 'x', 'music', 'cars']),
          ['music', 'cars']);
      var sel = <String>[];
      for (final k in UserInterests.keys.take(20)) {
        sel = UserInterests.toggle(sel, k)!;
      }
      expect(sel.length, 20);
      expect(UserInterests.toggle(sel, UserInterests.keys.last), isNull);
      expect(UserInterests.toggle(sel, 'music')!.contains('music'), isFalse);
    });
    testWidgets('chips: seleção múltipla', (tester) async {
      var sel = <String>['music'];
      await tester.pumpWidget(_app(Scaffold(
          body: SingleChildScrollView(
              child: StatefulBuilder(
                  builder: (c, set) => InterestChips(
                      selected: sel, onChanged: (v) => set(() => sel = v)))))));
      await tester.tap(find.byKey(const Key('interest_chip_hiking')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('interest_chip_music')));
      await tester.pump();
      expect(sel, ['hiking']);
    });
    test('legenda', () {
      expect(UserInterests.reasonText(['cars']), 'Também curte carros');
      expect(UserInterests.reasonText(['music', 'beach', 'art']),
          'Também curte música e mais 2');
    });
    test(
        'Em comum: qualquer cidade, ordem por nº de iguais, sem repetir abaixo',
        () {
      final viewer = {
        'homeCountryCode': 'br',
        'cityName': 'Campo Mourão',
        'stateName': 'PR',
        'interests': ['music', 'beach', 'art', 'cars'],
      };
      final people = [
        _p('um', 'Campo Mourão', ['music']),
        _p('tres', 'Salvador', ['music', 'beach', 'art'], state: 'BA'),
        _p('dois', 'Maringá', ['beach', 'cars']),
        _p('nada', 'Campo Mourão', ['games']),
        _p('outro', 'Recife', [], state: 'PE'),
      ];
      final v = CountryPeopleView.build(
          people: people, viewer: viewer, countryCode: 'br');
      expect(v.common.map((m) => m.person.uid), ['tres', 'dois', 'um']);
      expect(v.common.every((m) => m.reason == CommonReason.sharedInterests),
          isTrue);
      final below = {
        ...v.nearby.map((r) => r.person.uid),
        ...v.ownStateRows.map((r) => r.person.uid),
        ...v.otherStates.expand((s) => s.rows).map((r) => r.person.uid),
      };
      expect(below.intersection({'tres', 'dois', 'um'}), isEmpty);
      expect(v.nearby.map((r) => r.person.uid), contains('nada'));
    });
    test('Sobre mim não entra no cruzamento e tem limite 300', () {
      expect(ProfileAbout.maxLength, 300);
      expect(ProfileAbout.clamp('a' * 400).length, 300);
      expect(_src('lib/services/people_country_view.dart').contains("'about'"),
          isFalse);
    });
  });

  group('foto de perfil obrigatória', () {
    test('needsPhoto: perfil completo sem foto volta ao completar perfil', () {
      expect(ProfilePhoto.needsPhoto({'profileComplete': true}), isTrue);
      expect(
          ProfilePhoto.needsPhoto(
              {'profileComplete': true, 'photoUrl': 'https://x/y.jpg'}),
          isFalse);
      expect(
          ProfilePhoto.needsPhoto(
              {'profileComplete': true, 'profilePhotoUrl': 'https://x/y.jpg'}),
          isFalse);
      expect(ProfilePhoto.needsPhoto({'profileComplete': false}), isFalse);
      expect(ProfilePhoto.hasPhoto({'photoUrl': '  '}), isFalse);
    });
    testWidgets('picker mostra o aviso e chama a escolha', (tester) async {
      var picked = 0;
      await tester.pumpWidget(_app(Scaffold(
          body: Center(
              child: ProfilePhotoPicker(
                  photoUrl: '', showError: true, onPick: () => picked++)))));
      expect(find.text('Adicione uma foto de perfil para continuar.'),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('profile_photo_pick')));
      expect(picked, 1);
    });
    test('cadastro bloqueia sem foto; gates mandam conta antiga sem foto', () {
      final e = _src('lib/pages/edit_profile_page.dart');
      expect(e.contains('ProfilePhotoPicker('), isTrue);
      expect(
          e.contains("_err = AppTexts.current.get('profile_photo_required')"),
          isTrue);
      expect(
          _src('lib/pages/splash_page.dart')
              .contains('ProfilePhoto.needsPhoto'),
          isTrue);
      expect(
          _src('lib/pages/auth_gate.dart').contains('ProfilePhoto.needsPhoto'),
          isTrue);
      for (final code in ['pt-BR', 'en', 'es', 'fr']) {
        expect(_load(code)['profile_photo_required'], isNotNull, reason: code);
      }
    });
  });

  group('screenshots', () {
    setUpAll(_fonts);
    testWidgets('13 pessoas switch', (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final t = AppTexts.current;
      await tester.pumpWidget(_app(Scaffold(
        appBar: AppBar(title: const Text('🇧🇷 Brasil')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Text(t.get('people_in_common'),
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          Container(
            width: 128,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFFE8EAF0),
                borderRadius: BorderRadius.circular(16)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const CircleAvatar(radius: 22),
              const SizedBox(height: 8),
              const Text('Ana', style: TextStyle(fontWeight: FontWeight.w800)),
              Text(UserInterests.reasonText(['music', 'beach', 'art']),
                  style: const TextStyle(
                      color: Color(0xFF313A5F),
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        bottomNavigationBar: ExploreOnlyBar(value: true, onChanged: (_) {}),
      )));
      await _shot(tester, '13_pessoas_switch');
    });
    testWidgets('14 menu cidade', (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 600 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final t = AppTexts.current;
      ListTile item(IconData i, String k) => ListTile(
          leading: Icon(i, color: const Color(0xFF6B7280)),
          title: Text(t.get(k),
              style: const TextStyle(
                  color: Color(0xFF111827), fontWeight: FontWeight.w800)));
      await tester.pumpWidget(_app(Scaffold(
        backgroundColor: const Color(0xFFF6F7FB),
        appBar: AppBar(title: Text(t.get('menu'))),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
            decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFE5E7EB)),
                borderRadius: BorderRadius.circular(16)),
            child: Material(
                type: MaterialType.transparency,
                child: Column(children: [
                  item(Icons.person, 'profile'),
                  const Divider(height: 1),
                  item(Icons.language, 'language'),
                  const Divider(height: 1),
                  item(Icons.notifications, 'notifications'),
                  const Divider(height: 1),
                  MenuSwitchTile(
                      tileKey: const Key('a'),
                      switchKey: const Key('b'),
                      icon: Icons.location_off_rounded,
                      title: t.get('menu_hide_in_city'),
                      value: true,
                      onChanged: (_) {}),
                  const Divider(height: 1),
                  MenuSwitchTile(
                      tileKey: const Key('c'),
                      switchKey: const Key('d'),
                      icon: Icons.favorite_border_rounded,
                      title: t.get('menu_interest_push'),
                      value: true,
                      onChanged: (_) {}),
                ])),
          ),
        ]),
      )));
      await _shot(tester, '14_menu_cidade');
    });
    testWidgets('15 boas-vindas', (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 844 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(WelcomeChoicePage(onChoose: (_) async {})));
      await _shot(tester, '15_boas_vindas');
    });
    testWidgets('16 interesses', (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 600 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(Scaffold(
          body: Padding(
              padding: const EdgeInsets.all(16),
              child: InterestChips(
                  selected: const ['music', 'hiking', 'beach', 'cars'],
                  onChanged: (_) {})))));
      await _shot(tester, '16_interesses');
    });
    testWidgets('17 sobre mim', (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 400 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final t = AppTexts.current;
      final c = TextEditingController(
          text:
              'Amo filmes do Studio Ghibli, trilhas no fim de semana e um bom café.');
      await tester.pumpWidget(_app(Scaffold(
          body: Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: c,
                maxLines: 4,
                maxLength: ProfileAbout.maxLength,
                decoration: InputDecoration(
                  labelText: t.get('about_you'),
                  hintText: t.get('about_you_hint'),
                  helperText: t.get('about_you_helper'),
                  helperMaxLines: 2,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              )))));
      await _shot(tester, '17_sobre_mim');
    });
    testWidgets('19 foto de perfil', (tester) async {
      tester.view.physicalSize = const Size(390 * 2, 360 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(Scaffold(
          body: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                  child: ProfilePhotoPicker(
                      photoUrl: '', showError: true, onPick: () {}))))));
      await _shot(tester, '19_foto_perfil');
    });
  });
}
