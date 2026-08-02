import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:socialchat_mvp/services/android_back_navigation.dart';
import 'package:socialchat_mvp/services/app_orientation.dart';

void main() {
  test('orientações permitidas: somente portraitUp', () {
    expect(AppOrientation.preferred, [DeviceOrientation.portraitUp]);
    expect(AppOrientation.preferred, isNot(contains(DeviceOrientation.portraitDown)));
    expect(AppOrientation.preferred, isNot(contains(DeviceOrientation.landscapeLeft)));
    expect(AppOrientation.preferred, isNot(contains(DeviceOrientation.landscapeRight)));
  });

  test('voltar interno não encerra presença (rotação também não deve)', () {
    // Política de presença: mudanças de UI/orientação não chamam PresenceService.stop.
    expect(
      AndroidBackNavigation.shouldAffectPresenceOnInternalBack(),
      isFalse,
    );
  });

  test('botão/gesto Voltar na Home ainda exige duplo toque', () {
    final d = AndroidBackNavigation.decide(
      keyboardOpen: false,
      currentTabIndex: 0,
      lastExitPromptAt: null,
      now: DateTime(2026, 1, 1, 12),
    );
    expect(d, AndroidBackDecision.showExitHint);
  });

  test('main.dart: Firebase → orientação → runApp (ordem correta)', () {
    final src = File('lib/main.dart').readAsStringSync();
    final firebase = src.indexOf('ensureFirebaseInitialized()');
    final orient = src.indexOf('AppOrientation.lockToPortraitUp()');
    final runAppAt = src.indexOf('runApp(const MyApp())');
    expect(firebase, greaterThan(-1));
    expect(orient, greaterThan(firebase));
    expect(runAppAt, greaterThan(orient));
    expect(src.contains('DeviceOrientation.landscape'), isFalse);
  });
}
