import 'package:firebase_auth/firebase_auth.dart';

enum PasswordRecoveryStatus {
  invalidEmail,
  genericSent,
  networkError,
  retryLater,
}

/// Email reset through the app's existing Firebase Auth client.
///
/// Outcomes never carry the address, a reset link, or a token.
class PasswordRecovery {
  static final RegExp _emailPattern = RegExp(
    r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
  );

  static bool isValidEmail(String email) {
    final value = email.trim();
    if (value.isEmpty) return false;
    return _emailPattern.hasMatch(value);
  }

  static Future<PasswordRecoveryStatus> request({
    required String email,
    required Future<void> Function(String email) send,
  }) async {
    final value = email.trim();
    if (!isValidEmail(value)) return PasswordRecoveryStatus.invalidEmail;

    try {
      await send(value);
      return PasswordRecoveryStatus.genericSent;
    } on FirebaseAuthException catch (error) {
      switch (error.code) {
        case 'user-not-found':
          return PasswordRecoveryStatus.genericSent;
        case 'invalid-email':
          return PasswordRecoveryStatus.invalidEmail;
        case 'network-request-failed':
          return PasswordRecoveryStatus.networkError;
        case 'too-many-requests':
          return PasswordRecoveryStatus.retryLater;
        default:
          return PasswordRecoveryStatus.retryLater;
      }
    } catch (_) {
      return PasswordRecoveryStatus.networkError;
    }
  }
}
