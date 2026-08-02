import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'purchase_service.dart';
import 'share_extension_session_service.dart';

/// Exclusão de conta via Cloud Function (Admin SDK).
class AccountDeletionService {
  AccountDeletionService._();

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static const String confirmationWordEn = 'DELETE';
  static const String confirmationWordPt = 'EXCLUIR';

  static String expectedConfirmationWord(String languageCode) {
    final code = languageCode.toLowerCase();
    if (code == 'pt') return confirmationWordPt;
    return confirmationWordEn;
  }

  static bool matchesConfirmation(String input, String languageCode) {
    final word = input.trim().toUpperCase();
    if (word.isEmpty) return false;
    // Aceita DELETE e EXCLUIR em qualquer idioma para evitar bloqueio
    return word == confirmationWordEn || word == confirmationWordPt;
  }

  /// Provedores vinculados à conta atual.
  static List<String> currentProviderIds() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const [];
    return user.providerData
        .map((p) => p.providerId)
        .where((id) => id.isNotEmpty)
        .toList();
  }

  static bool get usesPassword =>
      currentProviderIds().contains('password');

  static bool get usesGoogle =>
      currentProviderIds().contains('google.com');

  static bool get usesFacebook =>
      currentProviderIds().contains('facebook.com');

  static bool get usesApple =>
      currentProviderIds().contains('apple.com');

  /// Reautenticação conforme o provedor principal.
  static Future<void> reauthenticate({String? password}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'Not signed in.',
      );
    }

    final providers = currentProviderIds();

    if (providers.contains('password')) {
      final email = (user.email ?? '').trim();
      final pass = (password ?? '').trim();
      if (email.isEmpty || pass.isEmpty) {
        throw FirebaseAuthException(
          code: 'wrong-password',
          message: 'Password required.',
        );
      }
      final cred = EmailAuthProvider.credential(email: email, password: pass);
      await user.reauthenticateWithCredential(cred);
      return;
    }

    if (providers.contains('google.com')) {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        throw FirebaseAuthException(
          code: 'aborted-by-user',
          message: 'Google sign-in cancelled.',
        );
      }
      final googleAuth = await googleUser.authentication;
      final cred = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await user.reauthenticateWithCredential(cred);
      return;
    }

    if (providers.contains('facebook.com')) {
      final result = await FacebookAuth.instance.login(
        permissions: const ['email', 'public_profile'],
      );
      if (result.status != LoginStatus.success ||
          result.accessToken == null) {
        throw FirebaseAuthException(
          code: 'aborted-by-user',
          message: 'Facebook sign-in cancelled.',
        );
      }
      final cred = FacebookAuthProvider.credential(
        result.accessToken!.tokenString,
      );
      await user.reauthenticateWithCredential(cred);
      return;
    }

    if (providers.contains('apple.com')) {
      // Apple Sign-In ainda não está totalmente configurado no app.
      throw FirebaseAuthException(
        code: 'operation-not-allowed',
        message: 'Apple re-authentication is not available yet.',
      );
    }

    throw FirebaseAuthException(
      code: 'unsupported-provider',
      message: 'No supported provider for reauthentication.',
    );
  }

  /// Chama a Cloud Function. UID é lido só do token no servidor.
  static Future<Map<String, dynamic>> deleteMyAccount() async {
    final callable = _functions.httpsCallable(
      'deleteMyAccount',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 300)),
    );
    // Não enviar UID — o servidor usa request.auth.uid
    final result = await callable.call(<String, dynamic>{});
    final data = result.data;
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return <String, dynamic>{'success': true};
  }

  static Future<void> clearLocalSession() async {
    try {
      await ShareExtensionSessionService.revokeLocalAndRemote();
    } catch (_) {}

    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().toList();
      for (final key in keys) {
        // Mantém preferência de idioma do aparelho
        if (key == 'app_lang') continue;
        await prefs.remove(key);
      }
    } catch (_) {}

    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
    try {
      await FacebookAuth.instance.logOut();
    } catch (_) {}
    try {
      await PurchaseService.instance.logOut();
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }

  static String manageSubscriptionsUrl() {
    if (Platform.isIOS) {
      return 'https://apps.apple.com/account/subscriptions';
    }
    if (Platform.isAndroid) {
      return 'https://play.google.com/store/account/subscriptions';
    }
    return 'https://play.google.com/store/account/subscriptions';
  }

  static String errorKey(Object error) {
    if (error is FirebaseFunctionsException) {
      switch (error.code) {
        case 'unauthenticated':
          return 'delete_account_reauth_required';
        case 'unavailable':
        case 'deadline-exceeded':
          return 'delete_account_network_error';
        default:
          return 'delete_account_failed';
      }
    }
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'requires-recent-login':
          return 'delete_account_reauth_required';
        case 'wrong-password':
        case 'invalid-credential':
        case 'invalid-login-credentials':
          return 'delete_account_wrong_password';
        case 'aborted-by-user':
          return 'delete_account_cancelled';
        case 'operation-not-allowed':
          return 'delete_account_provider_unavailable';
        default:
          return 'delete_account_reauth_required';
      }
    }
    return 'delete_account_failed';
  }
}
