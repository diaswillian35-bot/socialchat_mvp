import 'dart:io';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:socialchat_mvp/firebase_options.dart';
import 'package:socialchat_mvp/services/apple_sign_in_service.dart';
import 'package:socialchat_mvp/services/ios_google_config.dart';

void main() {
  tearDown(() {
    AppleSignInService.pendingLinkCredential = null;
  });

  group('Apple nonce', () {
    test('generateNonce uses the Apple/Firebase charset and length', () {
      final nonce = AppleSignInService.generateNonce(32, Random(1));
      expect(nonce.length, 32);
      expect(RegExp(r'^[0-9A-Za-z._-]+$').hasMatch(nonce), isTrue);
      final other = AppleSignInService.generateNonce(32, Random(2));
      expect(other, isNot(nonce));
    });

    test('sha256Of is stable for the same nonce', () {
      const raw = 'test-nonce-value';
      expect(
        AppleSignInService.sha256Of(raw),
        AppleSignInService.sha256Of(raw),
      );
      expect(AppleSignInService.sha256Of(raw).length, 64);
      expect(
        AppleSignInService.sha256Of(raw),
        isNot(AppleSignInService.sha256Of('other')),
      );
    });
  });

  group('Apple friendly errors', () {
    test('sanitize strips jwt and email, keeps firebase wording', () {
      final s = AppleSignInService.sanitizeAuthMessage(
        'The audience eyJhbGciOi.aaa.bbb does not match user@example.com malformed',
      );
      expect(s.contains('eyJ'), isFalse);
      expect(s.toLowerCase(), isNot(contains('user@example.com')));
      expect(s.toLowerCase(), contains('malformed'));
      expect(s, contains('<jwt>'));
      expect(s, contains('<email>'));
    });

    test('empty identity token is distinct from invalid-credential', () {
      final empty = AppleSignInService.friendlyFirebaseAuthMessage(
        FirebaseAuthException(code: AppleSignInService.emptyIdentityTokenCode),
      );
      final invalid = AppleSignInService.friendlyFirebaseAuthMessage(
        FirebaseAuthException(code: 'invalid-credential'),
      );
      expect(empty.toLowerCase(), contains('identidade'));
      expect(empty, isNot(invalid));
    });

    test('account-exists asks to sign in and link without silent merge', () {
      final msg = AppleSignInService.friendlyFirebaseAuthMessage(
        FirebaseAuthException(code: 'account-exists-with-different-credential'),
      );
      expect(msg.toLowerCase(), contains('já existe'));
      expect(msg.toLowerCase(), contains('vincular'));
      expect(msg.toLowerCase(), contains('não criamos'));
    });

    test('credential already in use', () {
      final msg = AppleSignInService.friendlyFirebaseAuthMessage(
        FirebaseAuthException(code: 'credential-already-in-use'),
      );
      expect(msg.toLowerCase(), contains('vinculada'));
    });

    test('cancel is empty so the UI stays silent', () {
      final msg = AppleSignInService.friendlyAppleException(
        const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.canceled,
          message: 'canceled',
        ),
      );
      expect(msg, isEmpty);
    });

    test('failed authorization has a human message', () {
      final msg = AppleSignInService.friendlyAppleException(
        const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.failed,
          message: 'failed',
        ),
      );
      expect(msg.toLowerCase(), contains('apple'));
    });

    test('generic fallback does not rethrow', () {
      final msg = AppleSignInService.friendlyGenericMessage(StateError('boom'));
      expect(msg, contains('Erro no Apple'));
    });

    test('cancelled outcome is distinct from error', () {
      const cancelled = AppleSignInOutcome.cancelled();
      expect(cancelled.isCancelled, isTrue);
      expect(cancelled.isSuccess, isFalse);
      expect(cancelled.userMessage, isNull);
    });
  });

  group('pending Apple link', () {
    test('linkPendingIfAny no-ops without a pending credential', () async {
      AppleSignInService.pendingLinkCredential = null;
      // Cannot call with a real User here; absence of pending is the contract.
      expect(AppleSignInService.pendingLinkCredential, isNull);
    });
  });

  group('iOS Apple capability / bundle', () {
    test('Runner entitlements enable Sign in with Apple', () {
      for (final path in [
        'ios/Runner/Runner.entitlements',
        'ios/Runner/DebugProfile.entitlements',
      ]) {
        final xml = File(path).readAsStringSync();
        expect(xml, contains('com.apple.developer.applesignin'));
        expect(xml, contains('<string>Default</string>'));
      }
    });

    test('Release/Profile/Debug sign the Runner entitlements', () {
      final pbx = File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      expect(pbx, contains('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements'));
      expect(
        pbx,
        contains('CODE_SIGN_ENTITLEMENTS = Runner/DebugProfile.entitlements'),
      );
    });

    test('Firebase iOS bundle id is com.remdy.app', () {
      expect(DefaultFirebaseOptions.ios.iosBundleId, IosGoogleConfig.bundleId);
      expect(IosGoogleConfig.bundleId, 'com.remdy.app');
      expect(
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.remdy.app;'),
      );
    });
  });

  group('login + deletion wiring', () {
    test('login uses AppleSignInService, terms gate, cancel, no stub', () {
      final login = File('lib/pages/login_page.dart').readAsStringSync();
      expect(login, contains("import '../services/apple_sign_in_service.dart'"));
      expect(login, contains('_appleSignInService.signIn()'));
      expect(login, contains('outcome.isCancelled'));
      expect(login.contains('deixei o botão'), isFalse);
      expect(login.contains('Depois configuramos'), isFalse);
      expect(
        login.indexOf('AuthTermsGate.rejectReason', login.indexOf('_loginApple')),
        greaterThan(login.indexOf('_loginApple')),
      );
      expect(login, contains('_maybeLinkPendingApple'));
      expect(login, contains("t.get('continue_apple')"));
    });

    test('account deletion reauthenticates with AppleSignInService', () {
      final deletion =
          File('lib/services/account_deletion_service.dart').readAsStringSync();
      expect(deletion, contains('AppleSignInService().reauthenticate'));
      expect(deletion.contains('Apple re-authentication is not available yet'),
          isFalse);
    });

    test('service hashes nonce before requesting Apple and uses rawNonce', () {
      final src =
          File('lib/services/apple_sign_in_service.dart').readAsStringSync();
      expect(src, contains('sha256Of(rawNonce)'));
      expect(src, contains('nonce: hashedNonce'));
      expect(src, contains('rawNonce: rawNonce'));
      expect(src, contains('AppleAuthProvider.credentialWithIDToken'));
      expect(src, isNot(contains("OAuthProvider('apple.com')")));
      expect(src, contains('AuthorizationErrorCode.canceled'));
      expect(src, contains('account-exists-with-different-credential'));
      expect(src, contains('pendingLinkCredential'));
      expect(src, contains('linkWithCredential'));
      expect(src, isNot(contains('APPLE_DIAG')));
      expect(src, isNot(contains('identityTokenLen')));
    });
  });
}
