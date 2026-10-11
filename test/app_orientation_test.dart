import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:socialchat_mvp/services/android_back_navigation.dart';
import 'package:socialchat_mvp/services/app_orientation.dart';
import 'package:socialchat_mvp/widgets/home_body_scroll_layout.dart';

void main() {
  test('celular: somente portraitUp', () {
    expect(AppOrientation.phonePreferred, [DeviceOrientation.portraitUp]);
    expect(AppOrientation.preferred, AppOrientation.phonePreferred);
    expect(
      AppOrientation.preferredFor(ios: false),
      [DeviceOrientation.portraitUp],
    );
    expect(
      AppOrientation.preferredFor(ios: false),
      isNot(contains(DeviceOrientation.landscapeLeft)),
    );
    expect(
      AppOrientation.preferredFor(ios: false),
      isNot(contains(DeviceOrientation.landscapeRight)),
    );
    expect(
      AppOrientation.preferredFor(ios: false),
      isNot(contains(DeviceOrientation.portraitDown)),
    );
  });

  test('iOS deixa o iPad girar; o plist do iPhone continua só retrato', () {
    expect(AppOrientation.iosPreferred, [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    expect(AppOrientation.preferredFor(ios: true), AppOrientation.iosPreferred);
    expect(
      AppOrientation.preferredFor(ios: true),
      isNot(equals(AppOrientation.phonePreferred)),
    );

    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final iphone = plist.indexOf('<key>UISupportedInterfaceOrientations</key>');
    final ipad = plist.indexOf('<key>UISupportedInterfaceOrientations~ipad</key>');
    expect(iphone, greaterThan(-1));
    expect(ipad, greaterThan(iphone));
    final iphoneBlock = plist.substring(iphone, ipad);
    expect(iphoneBlock, contains('UIInterfaceOrientationPortrait'));
    expect(iphoneBlock, isNot(contains('Landscape')));
    expect(iphoneBlock, isNot(contains('PortraitUpsideDown')));

    final ipadBlock = plist.substring(ipad);
    expect(ipadBlock, contains('UIInterfaceOrientationPortrait</string>'));
    expect(ipadBlock, contains('UIInterfaceOrientationPortraitUpsideDown'));
    expect(ipadBlock, contains('UIInterfaceOrientationLandscapeLeft'));
    expect(ipadBlock, contains('UIInterfaceOrientationLandscapeRight'));
  });

  test('Android permanece travado em retrato no manifesto', () {
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:screenOrientation="portrait"'));
    expect(manifest, isNot(contains('android:screenOrientation="fullUser"')));
    expect(manifest, isNot(contains('android:screenOrientation="sensor"')));
  });

  test('Home responsiva continua distinta em retrato e paisagem', () {
    expect(
      HomeBodyScrollLayout.countryGridChildAspectRatio(
        HomeBodyScrollLayout.ipadAir11Portrait,
      ),
      HomeBodyScrollLayout.portraitCountryAspect,
    );
    expect(
      HomeBodyScrollLayout.countryGridChildAspectRatio(
        HomeBodyScrollLayout.ipadAir11Landscape,
      ),
      HomeBodyScrollLayout.landscapeCountryAspect,
    );
  });

  test('voltar interno não encerra presença (rotação também não deve)', () {
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

  test('main.dart: Firebase → orientação por aparelho → runApp', () {
    final src = File('lib/main.dart').readAsStringSync();
    final firebase = src.indexOf('ensureFirebaseInitialized()');
    final orient = src.indexOf('AppOrientation.apply()');
    final runAppAt = src.indexOf('runApp(const MyApp())');
    expect(firebase, greaterThan(-1));
    expect(orient, greaterThan(firebase));
    expect(runAppAt, greaterThan(orient));
    expect(src.contains('lockToPortraitUp'), isFalse);
    expect(src.contains('DeviceOrientation.landscape'), isFalse);
  });
}
