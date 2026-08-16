import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  const advertisingPermissions = <String>[
    'com.google.android.gms.permission.AD_ID',
    'android.permission.ACCESS_ADSERVICES_AD_ID',
    'android.permission.ACCESS_ADSERVICES_ATTRIBUTION',
    'android.permission.ACCESS_ADSERVICES_CUSTOM_AUDIENCE',
    'android.permission.ACCESS_ADSERVICES_TOPICS',
  ];

  test('source manifest removes every advertising permission via merger', () {
    final manifest = source('android/app/src/main/AndroidManifest.xml');

    for (final permission in advertisingPermissions) {
      final removal = RegExp(
        '<uses-permission\\s+(?=[^>]*android:name="$permission")'
        '(?=[^>]*tools:node="remove")[^>]*/>',
        dotAll: true,
      );
      expect(removal.hasMatch(manifest), isTrue, reason: permission);
    }
  });

  test('generated release merged manifest has no advertising permissions', () {
    final merged = File(
      'build/app/intermediates/merged_manifest/release/'
      'processReleaseMainManifest/AndroidManifest.xml',
    );
    expect(merged.existsSync(), isTrue);

    final manifest = merged.readAsStringSync();
    for (final permission in advertisingPermissions) {
      expect(manifest, isNot(contains(permission)), reason: permission);
    }
  });

  test('Meta automatic events and advertiser ID collection are disabled', () {
    final manifest = source('android/app/src/main/AndroidManifest.xml');

    for (final setting in <String>[
      'com.facebook.sdk.AutoLogAppEventsEnabled',
      'com.facebook.sdk.AdvertiserIDCollectionEnabled',
    ]) {
      final disabled = RegExp(
        '<meta-data\\s+(?=[^>]*android:name="$setting")'
        '(?=[^>]*android:value="false")[^>]*/>',
        dotAll: true,
      );
      expect(disabled.hasMatch(manifest), isTrue, reason: setting);
    }

    final applicationSources = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    expect(applicationSources, isNot(contains('AppEventsLogger')));
    expect(applicationSources, isNot(contains('FacebookAppEvents')));
  });

  test('Facebook Login contract remains present', () {
    final manifest = source('android/app/src/main/AndroidManifest.xml');
    final pubspec = source('pubspec.yaml');
    final login = source('lib/pages/login_page.dart');
    final deletion = source('lib/services/account_deletion_service.dart');

    expect(pubspec, contains('flutter_facebook_auth:'));
    expect(manifest, contains('com.facebook.sdk.ApplicationId'));
    expect(manifest, contains('com.facebook.FacebookActivity'));
    expect(login, contains('FacebookAuth.instance.login'));
    expect(login, contains('FacebookAuthProvider.credential'));
    expect(deletion, contains('FacebookAuth.instance.login'));
  });

  test('privacy wording is consistent with no advertising ID use', () {
    final privacy = source('lib/l10n/pt-BR.json');
    expect(
      privacy,
      contains('Não compartilhamos dados pessoais para publicidade '
          'comportamental de terceiros'),
    );
    expect(privacy, isNot(contains('Advertising ID')));
    expect(privacy, isNot(contains('ID de publicidade')));
  });

  test('application version is 1.0.3+13', () {
    expect(source('pubspec.yaml'), contains('version: 1.0.3+13'));
  });
}
