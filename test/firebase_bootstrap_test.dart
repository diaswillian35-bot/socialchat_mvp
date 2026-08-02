import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:socialchat_mvp/firebase_options.dart';
import 'package:socialchat_mvp/services/presence_rtdb_config.dart';

void main() {
  test('Android DefaultFirebaseOptions aponta para socialchatmvp + RTDB', () {
    final opts = DefaultFirebaseOptions.android;
    expect(opts.projectId, 'socialchatmvp');
    expect(
      opts.databaseURL,
      'https://socialchatmvp-default-rtdb.firebaseio.com',
    );
    expect(opts.databaseURL, PresenceRtdbConfig.databaseURL);
    expect(opts.storageBucket, 'socialchatmvp.firebasestorage.app');
  });

  test(
    'google-services.json declara firebase_url igual ao Dart (evita duplicate-app)',
    () {
      final file = File('android/app/google-services.json');
      expect(file.existsSync(), isTrue);
      final json = file.readAsStringSync();
      expect(
        json,
        contains(
          '"firebase_url": "https://socialchatmvp-default-rtdb.firebaseio.com"',
        ),
      );
      expect(json, contains('"project_id": "socialchatmvp"'));
    },
  );
}
