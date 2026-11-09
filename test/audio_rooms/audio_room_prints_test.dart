import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/features/audio_rooms/audio_room_controller.dart';
import 'package:socialchat_mvp/features/audio_rooms/audio_room_page.dart';
import 'package:socialchat_mvp/features/audio_rooms/audio_room_service.dart';
import 'package:socialchat_mvp/features/audio_rooms/group_live_card.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';

// Prints de aprovação das telas da sala de áudio (dados de exemplo).
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
    await (FontLoader('MaterialIcons')
          ..addFont(
              Future.value(ByteData.sublistView(icons.readAsBytesSync()))))
        .load();
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
        ),
      ),
      home: RepaintBoundary(key: const Key('shot'), child: home),
    );

const _peers = [
  AudioRoomPeer(
      uid: 'own',
      name: 'Willian',
      isLocal: true,
      canSpeak: true,
      micOn: true,
      speaking: true),
  AudioRoomPeer(
      uid: 'mod',
      name: 'Carla',
      isLocal: false,
      canSpeak: true,
      micOn: false,
      speaking: false),
  AudioRoomPeer(
      uid: 'spk',
      name: 'Rafael',
      isLocal: false,
      canSpeak: true,
      micOn: true,
      speaking: false),
  AudioRoomPeer(
      uid: 'l1',
      name: 'Juliana',
      isLocal: false,
      canSpeak: false,
      micOn: false,
      speaking: false),
  AudioRoomPeer(
      uid: 'l2',
      name: 'Pedro',
      isLocal: false,
      canSpeak: false,
      micOn: false,
      speaking: false),
  AudioRoomPeer(
      uid: 'l3',
      name: 'Marina',
      isLocal: false,
      canSpeak: false,
      micOn: false,
      speaking: false),
];

AudioRoomView _room(
        {required bool moderator,
        List<AudioRoomPeer> peers = _peers,
        bool raised = false}) =>
    AudioRoomView(
      groupName: 'Papo De BUTECO',
      peers: peers,
      roleLabelOf: (uid) => uid == 'own'
          ? AppTexts.current.get('audio_room_owner')
          : uid == 'mod'
              ? AppTexts.current.get('audio_room_moderator')
              : '',
      isModerator: moderator,
      loading: false,
      hands: moderator
          ? const [AudioRoomHand('l1', 'Juliana'), AudioRoomHand('l2', 'Pedro')]
          : const [],
      myHandRaised: raised,
      canSpeak: moderator,
      micOn: moderator,
      busy: false,
      onApprove: (_) {},
      onRevoke: (_) {},
      canMuteOf: (uid) => uid != 'own',
      onMute: (_) {},
      onMuteAll: () {},
      onToggleHand: (_) {},
      onToggleMic: () {},
      onMessage: () {},
      onLeave: () {},
      onClose: () {},
    );

void main() {
  setUpAll(_fonts);

  for (final lang in ['pt-BR', 'en']) {
    testWidgets('prints $lang', (tester) async {
      AppTexts.loadFromMap(
          jsonDecode(File('lib/l10n/$lang.json').readAsStringSync())
              as Map<String, dynamic>);
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      Future<void> shot(Widget w, String name) async {
        await tester.pumpWidget(_app(w));
        await tester.pumpAndSettle();
        await expectLater(
            find.byKey(const Key('shot')),
            matchesGoldenFile(
                '../../docs/audio_rooms/prints/${lang}_$name.png'));
      }

      await shot(_room(moderator: true), '1_sala_moderador');
      // Moderador tocou em quem está falando: opções de mutar e tirar a palavra.
      await tester.pumpWidget(_app(_room(moderator: true)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rafael'));
      await tester.pumpAndSettle();
      await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile(
              '../../docs/audio_rooms/prints/${lang}_4_sala_mutar_pessoa.png'));
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      final listenerPeers = [
        for (final p in _peers)
          AudioRoomPeer(
              uid: p.uid,
              name: p.uid == 'l1' ? 'Juliana' : p.name,
              isLocal: p.uid == 'l1',
              canSpeak: p.canSpeak,
              micOn: p.micOn,
              speaking: p.speaking),
      ];
      await shot(_room(moderator: false, peers: listenerPeers, raised: true),
          '2_sala_ouvinte');

      await shot(
        Scaffold(
          backgroundColor: Colors.white,
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
            iconTheme: const IconThemeData(color: Color(0xFF6B7280)),
            title: const Text('Papo De BUTECO',
                style: TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
            actions: [
              IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.headset_mic_outlined,
                      color: Color(0xFF6B7280))),
              IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.flag_outlined,
                      color: Color(0xFF6B7280))),
              IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.search, color: Color(0xFF6B7280))),
            ],
          ),
          body: Column(children: [
            GroupLiveCardView(
              room: const AudioRoomInfo(
                id: 'r',
                openedBy: 'own',
                openedByName: 'Willian',
                participantCount: 6,
                presentUids: ['own', 'mod', 'spk', 'l1'],
                speakerUids: ['spk'],
              ),
              inside: false,
              enabled: true,
              onEnter: () {},
            ),
            const Spacer(),
          ]),
        ),
        '3_grupo_card_ao_vivo',
      );
    });
  }
}
