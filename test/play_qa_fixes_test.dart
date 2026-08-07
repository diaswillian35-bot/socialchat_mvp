import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';
import 'package:socialchat_mvp/services/presence_rtdb_logic.dart';
import 'package:socialchat_mvp/services/remi_ui_labels.dart';

Future<void> _loadPtBr() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // AppTexts reads via rootBundle; in tests load asset path from disk into
  // the same API by calling load with a Locale after registering a mock is
  // heavier — use the public load with asset bundle from Flutter test.
  await AppTexts.load(const Locale('pt', 'BR'));
}

void main() {
  group('RemiUiLabels (UI locale ≠ target)', () {
    setUpAll(() async {
      // Ensure l10n JSON is available as Flutter assets in test.
      final file = File('lib/l10n/pt-BR.json');
      expect(file.existsSync(), isTrue);
      final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      // Sanity: keys we rely on exist in catalog.
      expect(map['remi_chip_travel'], 'Viagem');
      expect(map['remi_choose_language_headline'], contains('idioma'));
      await _loadPtBr();
    });

    test('goal titles follow app locale when AppTexts loaded', () {
      expect(RemiUiLabels.goalTitle('Travel'), 'Viagem');
      expect(RemiUiLabels.goalTitle('Friends'), 'Amigos');
      expect(RemiUiLabels.goalTitle('Events'), 'Eventos');
    });

    test('lesson titles follow app locale', () {
      expect(RemiUiLabels.lessonTitle('Airport'), 'Aeroporto');
      expect(RemiUiLabels.lessonTitle('Coffee Shop'), 'Cafeteria');
    });
  });

  group('PresenceRtdbLogic.parseCounter', () {
    test('accepts int, num, map.count and string', () {
      expect(PresenceRtdbLogic.parseCounter(3), 3);
      expect(PresenceRtdbLogic.parseCounter(4.0), 4);
      expect(PresenceRtdbLogic.parseCounter({'count': 7}), 7);
      expect(PresenceRtdbLogic.parseCounter('9'), 9);
      expect(PresenceRtdbLogic.parseCounter(null), 0);
    });
  });

  group('PresenceRtdbLogic.worldMinusCountry', () {
    test('waits until both sides arrive (no flash of raw world)', () {
      expect(
        PresenceRtdbLogic.worldMinusCountry(world: 4, country: null),
        isNull,
      );
      expect(
        PresenceRtdbLogic.worldMinusCountry(world: null, country: 3),
        isNull,
      );
      expect(
        PresenceRtdbLogic.worldMinusCountry(world: 4, country: 3),
        1,
      );
      expect(
        PresenceRtdbLogic.worldMinusCountry(world: 2, country: 5),
        0,
      );
    });
  });

  group('static regressions', () {
    test('messages_page uses RTDB OnlineDot, not Firestore OnlineStatus', () {
      final src = File('lib/pages/messages_page.dart').readAsStringSync();
      expect(src.contains('AvatarWithOnlineDot'), isTrue);
      expect(src.contains('OnlineStatus.isOnline'), isFalse);
    });

    test('event share has link fallback when image fails', () {
      final src =
          File('lib/services/event_share_image_service.dart').readAsStringSync();
      expect(src.contains('Share.share(text'), isTrue);
      expect(src.contains('image share failed'), isTrue);
    });

    test('remi languages page uses AppTexts (not hardcoded English)', () {
      final src = File('lib/pages/remi_languages_page.dart').readAsStringSync();
      expect(src.contains("AppTexts.t('remi_choose_language_title')"), isTrue);
      expect(src.contains("'Choose language'"), isFalse);
    });
  });
}
