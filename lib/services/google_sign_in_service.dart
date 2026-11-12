import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../firebase_options.dart';
import '../l10n/app_texts.dart';
import 'auth_error_text.dart';

enum GoogleSignInResultKind { success, cancelled, error }

class GoogleSignInOutcome {
  const GoogleSignInOutcome._({
    required this.kind,
    this.userCredential,
    this.userMessage,
  });

  const GoogleSignInOutcome.cancelled()
    : this._(kind: GoogleSignInResultKind.cancelled);

  const GoogleSignInOutcome.error(String message)
    : this._(kind: GoogleSignInResultKind.error, userMessage: message);

  const GoogleSignInOutcome.success(UserCredential credential)
    : this._(kind: GoogleSignInResultKind.success, userCredential: credential);

  final GoogleSignInResultKind kind;
  final UserCredential? userCredential;
  final String? userMessage;

  bool get isSuccess => kind == GoogleSignInResultKind.success;
  bool get isCancelled => kind == GoogleSignInResultKind.cancelled;
}

class GoogleSignInService {
  GoogleSignInService({GoogleSignIn? googleSignIn, FirebaseAuth? firebaseAuth})
    : _googleSignIn = googleSignIn ?? defaultGoogleSignIn(),
      _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final GoogleSignIn _googleSignIn;
  final FirebaseAuth _firebaseAuth;

  /// Usa o iosClientId canônico do FirebaseOptions (alinhado ao GoogleService-Info).
  static GoogleSignIn defaultGoogleSignIn() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final clientId = DefaultFirebaseOptions.ios.iosClientId;
      if (clientId != null && clientId.isNotEmpty) {
        return GoogleSignIn(
          clientId: clientId,
          scopes: const ['email', 'profile'],
        );
      }
    }
    return GoogleSignIn(scopes: const ['email', 'profile']);
  }

  Future<void> signOutSilently() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    try {
      await _firebaseAuth.signOut();
    } catch (_) {}
  }

  Future<GoogleSignInOutcome> signIn() async {
    try {
      await signOutSilently();

      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return const GoogleSignInOutcome.cancelled();
      }

      final googleAuth = await googleUser.authentication;
      if ((googleAuth.idToken ?? '').isEmpty &&
          (googleAuth.accessToken ?? '').isEmpty) {
        return GoogleSignInOutcome.error(
          AppTexts.t('auth_error_google_missing_credential'),
        );
      }

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _firebaseAuth.signInWithCredential(
        credential,
      );
      if (userCredential.user == null) {
        return GoogleSignInOutcome.error(
          AppTexts.t('auth_error_google_empty_user'),
        );
      }

      return GoogleSignInOutcome.success(userCredential);
    } on FirebaseAuthException catch (e) {
      return GoogleSignInOutcome.error(friendlyFirebaseAuthMessage(e));
    } catch (e) {
      return GoogleSignInOutcome.error(friendlyGenericMessage(e));
    }
  }

  static String friendlyFirebaseAuthMessage(FirebaseAuthException e) {
    return authErrorText(e, source: AuthErrorSource.google);
  }

  static String friendlyGenericMessage(Object error) {
    final msg = error.toString();
    if (msg.contains('ApiException: 10') ||
        msg.contains('DEVELOPER_ERROR') ||
        msg.contains('sign_in_failed')) {
      return AppTexts.t('auth_error_google_oauth_config');
    }
    return AppTexts.t('auth_error_google_generic');
  }
}

/// Password provider precisa verificar e-mail; OAuth (Google/Apple/Facebook) não.
bool authRequiresEmailVerificationFromProviders({
  required Iterable<String> providerIds,
  required bool emailVerified,
}) {
  final usesPassword = providerIds.any((id) => id == 'password');
  return usesPassword && !emailVerified;
}

bool authRequiresEmailVerification(User user) {
  return authRequiresEmailVerificationFromProviders(
    providerIds: user.providerData.map((p) => p.providerId),
    emailVerified: user.emailVerified,
  );
}
