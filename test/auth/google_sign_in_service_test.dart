import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/firebase_options.dart';
import 'package:socialchat_mvp/services/google_sign_in_service.dart';
import 'package:socialchat_mvp/services/ios_google_config.dart';

void main() {
  group('GoogleSignInService friendly errors', () {
    test('account already linked / different credential', () {
      final msg = GoogleSignInService.friendlyFirebaseAuthMessage(
        FirebaseAuthException(code: 'account-exists-with-different-credential'),
      );
      expect(msg.toLowerCase(), contains('já existe'));
    });

    test('credential already in use', () {
      final msg = GoogleSignInService.friendlyFirebaseAuthMessage(
        FirebaseAuthException(code: 'credential-already-in-use'),
      );
      expect(msg.toLowerCase(), contains('vinculada'));
    });

    test('network error', () {
      final msg = GoogleSignInService.friendlyFirebaseAuthMessage(
        FirebaseAuthException(code: 'network-request-failed'),
      );
      expect(msg.toLowerCase(), contains('conexão'));
    });

    test('SDK / DEVELOPER_ERROR generic', () {
      final msg = GoogleSignInService.friendlyGenericMessage(
        Exception('PlatformException(sign_in_failed, ApiException: 10, null)'),
      );
      expect(msg.toLowerCase(), contains('oauth'));
    });

    test('unknown error does not rethrow', () {
      final msg =
          GoogleSignInService.friendlyGenericMessage(StateError('boom'));
      expect(msg, contains('Erro no Google'));
    });

    test('cancelled outcome is distinct from error', () {
      const cancelled = GoogleSignInOutcome.cancelled();
      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.isSuccess, isFalse);
      expect(cancelled.userMessage, isNull);
    });
  });

  group('authRequiresEmailVerificationFromProviders', () {
    test('password unverified → true', () {
      expect(
        authRequiresEmailVerificationFromProviders(
          providerIds: const ['password'],
          emailVerified: false,
        ),
        isTrue,
      );
    });

    test('google only → false even if emailVerified false', () {
      expect(
        authRequiresEmailVerificationFromProviders(
          providerIds: const ['google.com'],
          emailVerified: false,
        ),
        isFalse,
      );
    });

    test('google + password verified → false', () {
      expect(
        authRequiresEmailVerificationFromProviders(
          providerIds: const ['password', 'google.com'],
          emailVerified: true,
        ),
        isFalse,
      );
    });

    test('multiple providers with password unverified → true', () {
      expect(
        authRequiresEmailVerificationFromProviders(
          providerIds: const ['google.com', 'password'],
          emailVerified: false,
        ),
        isTrue,
      );
    });

    test('master/common: splash has no isMaster fork', () {
      final splash = File('lib/pages/splash_page.dart').readAsStringSync();
      expect(splash.contains('isMaster'), isFalse);
      expect(splash.contains('authRequiresEmailVerification'), isTrue);
    });
  });

  group('iOS Google OAuth artifact alignment', () {
    test('GoogleService-Info.plist matches canonical client + app id', () {
      expect(
        IosGoogleConfig.readPlistValue('CLIENT_ID'),
        IosGoogleConfig.clientId,
      );
      expect(
        IosGoogleConfig.readPlistValue('REVERSED_CLIENT_ID'),
        IosGoogleConfig.reversedClientId,
      );
      expect(
        IosGoogleConfig.readPlistValue('GOOGLE_APP_ID'),
        IosGoogleConfig.firebaseAppId,
      );
      expect(
        IosGoogleConfig.readPlistValue('BUNDLE_ID'),
        IosGoogleConfig.bundleId,
      );
    });

    test('Info.plist URL scheme + GIDClientID match REVERSED/CLIENT', () {
      expect(
        IosGoogleConfig.readInfoPlistUrlScheme(),
        IosGoogleConfig.reversedClientId,
      );
      expect(
        IosGoogleConfig.readInfoPlistGidClientId(),
        IosGoogleConfig.clientId,
      );
    });

    test('firebase_options ios aligns with GoogleService-Info', () {
      final ios = DefaultFirebaseOptions.ios;
      expect(ios.appId, IosGoogleConfig.firebaseAppId);
      expect(ios.iosClientId, IosGoogleConfig.clientId);
      expect(ios.iosBundleId, IosGoogleConfig.bundleId);
    });

    test('no hyphenated GoogleService-Info-.plist in Runner', () {
      expect(File('ios/Runner/GoogleService-Info-.plist').existsSync(), isFalse);
      expect(File('ios/Runner/GoogleService-Info.plist').existsSync(), isTrue);
    });

    test('login page never lets Google errors escape uncaught', () {
      final src = File('lib/pages/login_page.dart').readAsStringSync();
      expect(src.contains('GoogleSignInService'), isTrue);
      expect(src.contains('outcome.isCancelled'), isTrue);
      expect(src.contains('Erro no Google. Tente novamente.'), isTrue);
    });

    test('post-login navigation uses SplashPage then AuthGate', () {
      final login = File('lib/pages/login_page.dart').readAsStringSync();
      expect(login.contains('SplashPage()'), isTrue);
      final splash = File('lib/pages/splash_page.dart').readAsStringSync();
      expect(splash.contains('AuthGate()'), isTrue);
    });
  });
}
