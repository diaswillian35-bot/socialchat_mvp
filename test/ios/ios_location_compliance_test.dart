import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardrails for ITMS-90683. Build 44 (aprovado pelo Willian): a aba Grupos
/// usa a posição aproximada do aparelho só "durante o uso", com geolocator
/// compilado SEM o pedido "sempre" (BYPASS_PERMISSION_LOCATION_ALWAYS=1).
/// Nada de localização em segundo plano.
void main() {
  test('geolocator only with the Always request compiled out', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('geolocator:'), isTrue);
    final podfile = File('ios/Podfile').readAsStringSync();
    expect(podfile, contains("target.name == 'geolocator_apple'"));
    expect(podfile, contains('BYPASS_PERMISSION_LOCATION_ALWAYS=1'));
    final manifest =
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(
      manifest,
      contains('com.baseflow.geolocator.GeolocatorLocationService'),
    );
    expect(manifest, contains('tools:node="remove"'));
    expect(manifest.contains('ACCESS_BACKGROUND_LOCATION'), isFalse);
  });

  test('only the Groups nearby service touches Geolocator', () {
    final hits = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.readAsStringSync().contains('Geolocator.')) hits.add(f.path);
    }
    expect(hits, ['lib/services/device_location_service.dart']);
    final src =
        File('lib/services/device_location_service.dart').readAsStringSync();
    expect(src, contains('LocationAccuracy.low'));
    expect(src.contains('getPositionStream'), isFalse);
    expect(src.contains('requestAlwaysAuthorization'), isFalse);
  });

  test('location usage text is localized in the 5 app languages', () {
    for (final l in ['pt-BR', 'pt-PT', 'en', 'es', 'fr']) {
      final s =
          File('ios/Runner/$l.lproj/InfoPlist.strings').readAsStringSync();
      expect(s, contains('NSLocationWhenInUseUsageDescription'), reason: l);
    }
  });

  test('Info.plist keeps WhenInUse and omits Always location keys', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, contains('NSLocationWhenInUseUsageDescription'));
    expect(plist, isNot(contains('NSLocationAlwaysAndWhenInUseUsageDescription')));
    expect(plist, isNot(contains('NSLocationAlwaysUsageDescription')));
    expect(plist, isNot(contains('<string>location</string>')));
  });


  test('Runner entitlements have no location background capability', () {
    final entitlements = File('ios/Runner/Runner.entitlements').readAsStringSync();
    expect(entitlements.contains('location'), isFalse);
  });

  test('nearby/events flows use profile coords, not Geolocator API', () {
    final eventsPage = File('lib/pages/events_page_new.dart').readAsStringSync();
    expect(eventsPage, contains('sem inventar localização'));
    expect(eventsPage, contains('userNeedsLocationForGeoScopes'));
    expect(eventsPage, isNot(contains('Geolocator')));

    final citySearch = File('lib/widget/city_search_dialog.dart').readAsStringSync();
    expect(citySearch, contains('maps.googleapis.com'));
    expect(citySearch, isNot(contains('geolocator')));
  });

  test('Podfile / project / ShareExtension target iOS 15.0', () {
    final podfile = File('ios/Podfile').readAsStringSync();
    expect(podfile, contains("platform :ios, '15.0'"));
    expect(podfile, contains("IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'"));

    final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(pbx.contains('IPHONEOS_DEPLOYMENT_TARGET = 13.0'), isFalse);
    expect(pbx.contains('IPHONEOS_DEPLOYMENT_TARGET = 14.0'), isFalse);
    expect(pbx.contains('IPHONEOS_DEPLOYMENT_TARGET = 15.0'), isTrue);

    final share = File('ios/ShareExtension/ShareExtension.xcconfig').readAsStringSync();
    expect(share, contains('IPHONEOS_DEPLOYMENT_TARGET = 15.0'));
  });

  /// Inspect a Profile/Release build product when present (CI or local QA).
  /// Skips cleanly when no fresh Profile/Release Runner.app has been built yet.
  /// Ignores stale xcarchives so an old TestFlight archive cannot fail the gate.
  test('Profile/Release app binary omits Always location symbols when present', () {
    final candidates = <Directory>[
      Directory('build/ios/iphoneos/Runner.app'),
      Directory('build/ios/Release-iphoneos/Runner.app'),
      Directory('build/ios/Profile-iphoneos/Runner.app'),
    ];

    final buildIos = Directory('build/ios');
    if (buildIos.existsSync()) {
      for (final entity in buildIos.listSync(recursive: true)) {
        if (entity is! Directory) continue;
        final path = entity.path;
        if (!path.endsWith('Runner.app')) continue;
        if (path.contains('.xcarchive')) continue;
        if (path.contains('/Debug-')) continue;
        candidates.add(entity);
      }
    }

    Directory? app;
    DateTime? bestMtime;
    for (final c in candidates) {
      if (!c.existsSync()) continue;
      final mtime = c.statSync().modified;
      if (bestMtime == null || mtime.isAfter(bestMtime)) {
        bestMtime = mtime;
        app = c;
      }
    }
    if (app == null) {
      // ignore: avoid_print
      print('SKIP artifact scan: no Runner.app under build/ios yet');
      return;
    }

    final binary = File('${app.path}/Runner');
    expect(binary.existsSync(), isTrue, reason: 'Runner binary missing in ${app.path}');

    final infoPlist = File('${app.path}/Info.plist');
    expect(infoPlist.existsSync(), isTrue);
    final plutil = Process.runSync('plutil', [
      '-extract',
      'MinimumOSVersion',
      'raw',
      infoPlist.path,
    ]);
    expect(plutil.exitCode, 0, reason: plutil.stderr.toString());
    final minOs = plutil.stdout.toString().trim();
    expect(double.tryParse(minOs) ?? 0, greaterThanOrEqualTo(15.0),
        reason: 'MinimumOSVersion=$minOs in ${app.path}');

    final strings = Process.runSync('strings', [binary.path]);
    expect(strings.exitCode, 0, reason: strings.stderr.toString());
    final hay = strings.stdout.toString();
    expect(hay.contains('requestAlwaysAuthorization'), isFalse);
    expect(hay.contains('NSLocationAlwaysAndWhenInUseUsageDescription'), isFalse);
    expect(hay.contains('NSLocationAlwaysUsageDescription'), isFalse);
  });
}
