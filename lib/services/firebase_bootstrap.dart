import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

/// Single shared Firebase bootstrap for the Dart isolate.
///
/// Android may already create `[DEFAULT]` via `google-services.json` before
/// Dart runs. Calling [Firebase.initializeApp] again with mismatched options
/// (e.g. `databaseURL` present only on the Dart side) throws
/// `[core/duplicate-app]`. Hot restart re-enters [main] while the native app
/// still exists.
///
/// This helper:
/// - runs at most one in-flight init per isolate ([_initFuture]);
/// - skips when [Firebase.apps] already has `[DEFAULT]`;
/// - on the narrow `duplicate-app` race (native app registered during core
///   init), returns the existing [Firebase.app] without masking other errors.
Future<FirebaseApp>? _initFuture;

Future<FirebaseApp> ensureFirebaseInitialized() {
  return _initFuture ??= _initializeFirebase();
}

Future<FirebaseApp> _initializeFirebase() async {
  if (Firebase.apps.isNotEmpty) {
    return Firebase.app();
  }

  try {
    return await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } on FirebaseException catch (e) {
    if (e.code == 'duplicate-app') {
      return Firebase.app();
    }
    rethrow;
  }
}
