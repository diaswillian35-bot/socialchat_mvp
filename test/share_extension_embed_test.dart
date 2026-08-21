import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/share_extension_session_service.dart';
import 'package:socialchat_mvp/services/share_in_service.dart';

void main() {
  test('Share Extension is enabled and embedded in Runner', () {
    expect(ShareExtensionSessionService.enabledForLaunch, isTrue);

    final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(pbx, contains('Embed App Extensions'));
    expect(pbx, contains('ShareExtension.appex in Embed App Extensions'));
    expect(pbx, contains('PRODUCT_BUNDLE_IDENTIFIER = com.remdy.app.ShareExtension'));
    expect(pbx, contains('DEVELOPMENT_TEAM = CZN2YMTU7B'));
    expect(pbx.contains('SharePayloadNormalizer.swift in Sources'), isTrue);
    expect(pbx.contains('ShareCallableClient.swift in Sources'), isTrue);
    expect(pbx.contains('ShareL10n.swift in Sources'), isTrue);
    expect(pbx.contains('ShareIncomingStore.swift in Sources'), isTrue);
    expect(pbx.contains('ShareSessionStore.swift in Sources'), isTrue);
    expect(pbx.contains('ShareTheme.swift in Sources'), isTrue);
    expect(pbx.contains('remdy_logo.png in Resources'), isTrue);
  });

  test('activation rule covers url, text and image', () {
    final plist = File('ios/ShareExtension/Info.plist').readAsStringSync();
    expect(plist, contains('com.apple.share-services'));
    expect(plist, contains('public.url'));
    expect(plist, contains('public.plain-text'));
    expect(plist, contains('public.image'));
    expect(plist, contains('ShareViewController'));
  });

  test('Runner and extension share Keychain group and App Group', () {
    for (final path in [
      'ios/Runner/Runner.entitlements',
      'ios/Runner/DebugProfile.entitlements',
      'ios/ShareExtension/ShareExtension.entitlements',
    ]) {
      final src = File(path).readAsStringSync();
      expect(src, contains('com.remdy.app.share'), reason: path);
      expect(src, contains('group.com.remdy.app'), reason: path);
    }
  });

  test('ShareExtension target exists for Debug, Profile and Release', () {
    final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(
      pbx.contains('CODE_SIGN_ENTITLEMENTS = ShareExtension/ShareExtension.entitlements'),
      isTrue,
    );
    expect(pbx, contains('ShareExtension.xcconfig'));
    expect(
      'name = Profile'.allMatches(pbx).length,
      greaterThanOrEqualTo(1),
    );
  });

  test('iOS defers Flutter ShareInPage; native extension is the iOS path', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(ShareInService.iosShareInDeferred, isTrue);
    expect(ShareInService.nativeShareInEnabled, isFalse);
  });

  test('incoming image jobs are age-gated and iOS-only', () {
    final src =
        File('lib/services/share_extension_incoming_service.dart').readAsStringSync();
    expect(src, contains('AgeAccessService.currentUserIsVerified()'));
    expect(src, contains('peekShareJobs'));
    expect(src, contains('OutgoingImageMessageService'));
  });

  test('extension UI stays light Remdy and sends on tap', () {
    final ui = File('ios/ShareExtension/ShareViewController.swift').readAsStringSync();
    expect(ui, contains('overrideUserInterfaceStyle = .light'));
    expect(ui, contains('ShareTheme.canvas'));
    expect(ui, contains('send(to:'));
    expect(ui, contains('share_need_login'));
    expect(ui, isNot(contains('extensionContext?.open')));
    expect(ui, contains('applyCachedDestinations'));
    expect(ui, contains('ShareSessionStore.load()'));
    expect(ui, contains('maxVisibleDestinations'));
    expect(ui, contains('heightAnchor.constraint(equalToConstant: 280)'));
    expect(ui, contains('finishSuccessfully'));
    expect(ui, contains('ShareDiag.log'));
  });

  test('extension cells do not download remote avatars', () {
    final cell = File('ios/ShareExtension/ShareDestinationCell.swift').readAsStringSync();
    expect(cell, isNot(contains('URLSession.shared')));
    expect(cell, isNot(contains('dataTask')));
    expect(cell, contains('No remote photo downloads'));
  });

  test('destination cache is capped for extension memory', () {
    final client = File('ios/ShareExtension/ShareCallableClient.swift').readAsStringSync();
    expect(client, contains('maxCachedItems = 30'));
    final dart = File('lib/services/share_extension_destinations_service.dart')
        .readAsStringSync();
    expect(dart, contains('maxItems = 30'));
    expect(dart, contains("'photoUrl': ''"));
  });

  test('login message is the official Portuguese copy', () {
    final l10n = File('ios/ShareExtension/ShareL10n.swift').readAsStringSync();
    expect(
      l10n,
      contains(
        'Abra a Remdy e entre na sua conta para ativar o compartilhamento.',
      ),
    );
  });

  test('session is mirrored to App Group, never logged as raw token', () {
    final store = File('ios/ShareExtension/ShareSessionStore.swift').readAsStringSync();
    expect(store, contains('ShareAppGroupSession.save'));
    expect(store, contains('saveAndReport'));
    final group = File('ios/ShareExtension/ShareAppGroupSession.swift').readAsStringSync();
    expect(group, contains('destinations_v1.json'));
    expect(group, contains('containerURL'));
    final dart = File('lib/services/share_extension_session_service.dart')
        .readAsStringSync();
    expect(dart, contains('ShareExtensionDestinationsService'));
    expect(dart, isNot(contains('debugPrint(token')));
    expect(dart, isNot(contains("debugPrint('ShareExtSession: issued sid=")));
    expect(dart, contains('static const bool enabledForLaunch = true'));
    expect(dart, contains("MethodChannel('remdy/share_session')"));
    expect(dart, contains('authStateChanges()'));
    expect(dart, contains('currentUser'));
    expect(dart, contains('_saveNativeWithRetry'));
    expect(dart, contains('static void start()'));
  });

  test('Runner registers share channel on implicit engine and restored auth', () {
    final appDelegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(appDelegate, contains('FlutterImplicitEngineDelegate'));
    expect(appDelegate, contains('didInitializeImplicitFlutterEngine'));
    expect(appDelegate, contains('registerNativeChannels'));
    expect(appDelegate, contains('promoteIfNeeded'));
    expect(appDelegate, contains('saveDestinations'));
    expect(appDelegate, contains('peekShareDiag'));
    expect(appDelegate, contains('peekShareJobs'));
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('ShareExtensionSessionService.start()'));
    final keychain = File('ios/ShareExtension/ShareSessionKeychain.swift')
        .readAsStringSync();
    expect(keychain, contains('NSNumber(value: session.expiresAtMs)'));
    expect(keychain, isNot(contains('print(session.token')));
  });
}
