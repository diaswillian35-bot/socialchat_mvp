import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Info.plist adopts UIScene required by Xcode 27 / iOS 27 SDK', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('<key>UIApplicationSceneManifest</key>'));
    expect(plist, contains('<key>UISceneDelegateClassName</key>'));
    expect(plist, contains('SceneDelegate'));
    expect(plist, contains('<string>Main</string>'));
    expect(plist, isNot(contains('_UIApplicationSceneManifest')));
  });

  test('AppDelegate registers plugins on implicit engine, not via window', () {
    final app = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(app, contains('FlutterImplicitEngineDelegate'));
    expect(
      app,
      contains('GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)'),
    );
    expect(app, contains('didInitializeImplicitFlutterEngine'));
    expect(app, isNot(contains('window?.rootViewController as! FlutterViewController')));
    expect(app, isNot(contains('setupNativeChannelsIfNeeded')));

    final launch = app.indexOf('didFinishLaunchingWithOptions');
    final implicit = app.indexOf('didInitializeImplicitFlutterEngine');
    final pluginReg = app.indexOf('GeneratedPluginRegistrant.register');
    expect(launch, greaterThan(-1));
    expect(implicit, greaterThan(launch));
    expect(pluginReg, greaterThan(implicit));
  });

  test('SceneDelegate subclasses FlutterSceneDelegate and keeps share-in URLs', () {
    final scene = File('ios/Runner/SceneDelegate.swift').readAsStringSync();
    expect(scene, contains('class SceneDelegate: FlutterSceneDelegate'));
    expect(scene, contains('openURLContexts'));
    expect(scene, contains('RemdyLaunchURL.handleShareInIfNeeded'));
    final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(pbx, contains('SceneDelegate.swift in Sources'));
  });
}
