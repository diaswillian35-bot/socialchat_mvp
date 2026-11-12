import 'package:firebase_auth/firebase_auth.dart';

import '../l10n/app_texts.dart';

/// Origem do erro, para textos específicos de cada método de login.
enum AuthErrorSource { password, google, apple, facebook, emailAction }

/// Normaliza códigos do Firebase Auth (ex.: INVALID_LOGIN_CREDENTIALS).
String normalizeAuthErrorCode(String? code) {
  return (code ?? '').trim().toLowerCase().replaceAll('_', '-');
}

/// Devolve a chave de l10n para o [code] do Firebase Auth.
///
/// Em login com e-mail e senha, [invalid-credential], [wrong-password] e
/// [user-not-found] usam a mesma mensagem, para não revelar se a conta existe.
String authErrorKey(
  String? code, {
  AuthErrorSource source = AuthErrorSource.password,
  String? fallbackKey,
}) {
  final c = normalizeAuthErrorCode(code);

  switch (source) {
    case AuthErrorSource.google:
      final key = _googleKey(c);
      if (key != null) return key;
      break;
    case AuthErrorSource.apple:
      final key = _appleKey(c);
      if (key != null) return key;
      break;
    case AuthErrorSource.facebook:
      final key = _facebookKey(c);
      if (key != null) return key;
      break;
    case AuthErrorSource.password:
    case AuthErrorSource.emailAction:
      break;
  }

  return _sharedKey(c, fallbackKey: fallbackKey ?? _genericKey(source));
}

/// Chave de l10n a partir de um [FirebaseAuthException] ou erro genérico.
String authErrorKeyFromError(
  Object error, {
  AuthErrorSource source = AuthErrorSource.password,
  String? fallbackKey,
}) {
  if (error is FirebaseAuthException) {
    return authErrorKey(error.code, source: source, fallbackKey: fallbackKey);
  }
  return fallbackKey ?? _genericKey(source);
}

/// Texto já traduzido no idioma atual.
///
/// Se o catálogo ainda não carregou, [AppTexts.t] devolve a própria chave.
String authErrorText(
  Object error, {
  AuthErrorSource source = AuthErrorSource.password,
  String? fallbackKey,
}) {
  return AppTexts.t(
    authErrorKeyFromError(error, source: source, fallbackKey: fallbackKey),
  );
}

/// Texto traduzido a partir só do código do Firebase Auth.
String authErrorTextForCode(
  String? code, {
  AuthErrorSource source = AuthErrorSource.password,
  String? fallbackKey,
}) {
  return AppTexts.t(
    authErrorKey(code, source: source, fallbackKey: fallbackKey),
  );
}

String _genericKey(AuthErrorSource source) {
  switch (source) {
    case AuthErrorSource.google:
      return 'auth_error_google_generic';
    case AuthErrorSource.apple:
      return 'auth_error_apple_generic';
    case AuthErrorSource.facebook:
      return 'auth_error_facebook_generic';
    case AuthErrorSource.password:
    case AuthErrorSource.emailAction:
      return 'auth_error_generic';
  }
}

String? _googleKey(String code) {
  switch (code) {
    case 'invalid-credential':
    case 'invalid-login-credentials':
      return 'auth_error_google_invalid_credential';
    case 'account-exists-with-different-credential':
      return 'auth_error_google_account_exists';
    case 'credential-already-in-use':
      return 'auth_error_google_credential_in_use';
    case 'operation-not-allowed':
      return 'auth_error_google_not_allowed';
    default:
      return null;
  }
}

String? _appleKey(String code) {
  switch (code) {
    case 'apple-empty-identity-token':
      return 'auth_error_apple_empty_token';
    case 'invalid-credential':
    case 'invalid-login-credentials':
      return 'auth_error_apple_invalid_credential';
    case 'account-exists-with-different-credential':
      return 'auth_error_apple_account_exists';
    case 'credential-already-in-use':
      return 'auth_error_apple_credential_in_use';
    case 'provider-already-linked':
      return 'auth_error_apple_already_linked';
    case 'operation-not-allowed':
      return 'auth_error_apple_not_allowed';
    default:
      return null;
  }
}

String? _facebookKey(String code) {
  switch (code) {
    case 'account-exists-with-different-credential':
      return 'auth_error_facebook_account_exists';
    default:
      return null;
  }
}

String _sharedKey(String code, {required String fallbackKey}) {
  switch (code) {
    case 'invalid-credential':
    case 'invalid-login-credentials':
    case 'wrong-password':
    case 'user-not-found':
      return 'auth_error_wrong_credentials';
    case 'invalid-email':
      return 'auth_error_invalid_email';
    case 'user-disabled':
      return 'auth_error_user_disabled';
    case 'email-already-in-use':
      return 'auth_error_email_already_in_use';
    case 'weak-password':
      return 'auth_error_weak_password';
    case 'too-many-requests':
      return 'auth_error_too_many_requests';
    case 'network-request-failed':
      return 'auth_error_network';
    case 'operation-not-allowed':
      return 'auth_error_operation_not_allowed';
    case 'requires-recent-login':
    case 'user-token-expired':
      return 'auth_error_requires_recent_login';
    case 'credential-already-in-use':
      return 'auth_error_credential_already_in_use';
    case 'account-exists-with-different-credential':
      return 'auth_error_account_exists_different';
    case 'expired-action-code':
      return 'auth_error_expired_action_code';
    case 'invalid-action-code':
      return 'auth_error_invalid_action_code';
    default:
      return fallbackKey;
  }
}
