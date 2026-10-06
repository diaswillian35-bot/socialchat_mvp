import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

enum AppleSignInResultKind {
  success,
  cancelled,
  error,
}

class AppleSignInOutcome {
  const AppleSignInOutcome._({
    required this.kind,
    this.userCredential,
    this.userMessage,
  });

  const AppleSignInOutcome.cancelled()
      : this._(kind: AppleSignInResultKind.cancelled);

  const AppleSignInOutcome.error(String message)
      : this._(kind: AppleSignInResultKind.error, userMessage: message);

  const AppleSignInOutcome.success(UserCredential credential)
      : this._(
          kind: AppleSignInResultKind.success,
          userCredential: credential,
        );

  final AppleSignInResultKind kind;
  final UserCredential? userCredential;
  final String? userMessage;

  bool get isSuccess => kind == AppleSignInResultKind.success;
  bool get isCancelled => kind == AppleSignInResultKind.cancelled;
}

/// Firebase Auth + Sign in with Apple. Vínculo só após conta já existente
/// (account-exists-with-different-credential) e login explícito no outro método.
class AppleSignInService {
  AppleSignInService({FirebaseAuth? firebaseAuth})
      : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  /// Só preenchido quando o Firebase recusa Apple porque o e-mail já tem outro provedor.
  @visibleForTesting
  static AuthCredential? pendingLinkCredential;

  static const String emptyIdentityTokenCode = 'apple-empty-identity-token';

  static const String _nonceCharset =
      '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';

  @visibleForTesting
  static String generateNonce([int length = 32, Random? random]) {
    final rng = random ?? Random.secure();
    return List.generate(
      length,
      (_) => _nonceCharset[rng.nextInt(_nonceCharset.length)],
    ).join();
  }

  @visibleForTesting
  static String sha256Of(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  @visibleForTesting
  static String sanitizeAuthMessage(String? raw) {
    if (raw == null) return '';
    var s = raw.trim();
    if (s.isEmpty) return '';
    s = s.replaceAll(RegExp(r'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9._\-]+'), '<jwt>');
    s = s.replaceAll(
      RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}'),
      '<email>',
    );
    return s;
  }

  static OAuthCredential firebaseCredential({
    required String idToken,
    required String rawNonce,
    String? givenName,
    String? familyName,
  }) {
    return AppleAuthProvider.credentialWithIDToken(
      idToken,
      rawNonce,
      AppleFullPersonName(
        givenName: givenName,
        familyName: familyName,
      ),
    );
  }

  Future<AppleSignInOutcome> signIn() async {
    try {
      final oauth = await _appleOAuthCredential();
      if (oauth == null) {
        return const AppleSignInOutcome.cancelled();
      }

      final userCredential =
          await _firebaseAuth.signInWithCredential(oauth.credential);
      final user = userCredential.user;
      if (user == null) {
        return const AppleSignInOutcome.error(
          'Erro: usuário da Apple veio vazio.',
        );
      }

      await _applyAppleDisplayName(user, oauth.givenName, oauth.familyName);
      pendingLinkCredential = null;
      return AppleSignInOutcome.success(userCredential);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return const AppleSignInOutcome.cancelled();
      }
      return AppleSignInOutcome.error(friendlyAppleException(e));
    } on SignInWithAppleNotSupportedException {
      return const AppleSignInOutcome.error(
        'Entrar com Apple não está disponível neste dispositivo.',
      );
    } on FirebaseAuthException catch (e) {
      if (e.code == emptyIdentityTokenCode) {
        return AppleSignInOutcome.error(friendlyFirebaseAuthMessage(e));
      }
      if (e.code == 'account-exists-with-different-credential') {
        if (e.credential != null) {
          pendingLinkCredential = e.credential;
        }
        return AppleSignInOutcome.error(friendlyFirebaseAuthMessage(e));
      }
      return AppleSignInOutcome.error(friendlyFirebaseAuthMessage(e));
    } catch (e) {
      return AppleSignInOutcome.error(friendlyGenericMessage(e));
    }
  }

  Future<void> reauthenticate(User user) async {
    final oauth = await _appleOAuthCredential();
    if (oauth == null) {
      throw FirebaseAuthException(
        code: 'aborted-by-user',
        message: 'Apple sign-in cancelled.',
      );
    }
    await user.reauthenticateWithCredential(oauth.credential);
  }

  /// Vínculo explícito depois do utilizador entrar no método original (e-mail/Google/Facebook).
  static Future<AppleSignInOutcome> linkPendingIfAny(User user) async {
    final pending = pendingLinkCredential;
    if (pending == null) {
      return const AppleSignInOutcome.cancelled();
    }
    try {
      final linked = await user.linkWithCredential(pending);
      pendingLinkCredential = null;
      if (linked.user == null) {
        return const AppleSignInOutcome.error(
          'Não foi possível vincular a conta Apple.',
        );
      }
      return AppleSignInOutcome.success(linked);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'provider-already-linked' ||
          e.code == 'credential-already-in-use') {
        pendingLinkCredential = null;
      }
      return AppleSignInOutcome.error(friendlyFirebaseAuthMessage(e));
    } catch (e) {
      return AppleSignInOutcome.error(friendlyGenericMessage(e));
    }
  }

  Future<_AppleOAuthParts?> _appleOAuthCredential() async {
    final rawNonce = generateNonce();
    final hashedNonce = sha256Of(rawNonce);

    final apple = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );

    final idToken = apple.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw FirebaseAuthException(
        code: emptyIdentityTokenCode,
        message: 'Apple did not return an identity token.',
      );
    }

    return _AppleOAuthParts(
      credential: firebaseCredential(
        idToken: idToken,
        rawNonce: rawNonce,
        givenName: apple.givenName,
        familyName: apple.familyName,
      ),
      givenName: apple.givenName,
      familyName: apple.familyName,
    );
  }

  static Future<void> _applyAppleDisplayName(
    User user,
    String? givenName,
    String? familyName,
  ) async {
    if ((user.displayName ?? '').trim().isNotEmpty) return;
    final name = [givenName, familyName]
        .map((p) => (p ?? '').trim())
        .where((p) => p.isNotEmpty)
        .join(' ');
    if (name.isEmpty) return;
    try {
      await user.updateDisplayName(name);
    } catch (_) {}
  }

  static String friendlyFirebaseAuthMessage(FirebaseAuthException e) {
    switch (e.code) {
      case emptyIdentityTokenCode:
        return 'A Apple não devolveu o token de identidade. Tente novamente.';
      case 'account-exists-with-different-credential':
        return 'Já existe uma conta Remdy com este e-mail. '
            'Entre com e-mail e senha, Google ou Facebook para vincular o Apple. '
            'Não criamos nem unimos outra conta automaticamente.';
      case 'credential-already-in-use':
        return 'Esta conta Apple já está vinculada a outro perfil Remdy.';
      case 'provider-already-linked':
        return 'O Apple já está vinculado a esta conta.';
      case 'operation-not-allowed':
        return 'Login com Apple não está habilitado. Tente outro método.';
      case 'user-disabled':
        return 'Esta conta foi desativada.';
      case 'invalid-credential':
        return 'Credencial Apple inválida ou expirada. Tente novamente.';
      case 'network-request-failed':
        return 'Sem conexão. Verifique a internet e tente novamente.';
      default:
        final m = sanitizeAuthMessage(e.message);
        return m.isNotEmpty ? m : 'Erro no Apple (${e.code}).';
    }
  }

  static String friendlyAppleException(
    SignInWithAppleAuthorizationException e,
  ) {
    switch (e.code) {
      case AuthorizationErrorCode.canceled:
        return '';
      case AuthorizationErrorCode.failed:
        return 'Login Apple falhou. Tente novamente.';
      case AuthorizationErrorCode.invalidResponse:
        return 'Resposta inválida da Apple. Tente novamente.';
      case AuthorizationErrorCode.notHandled:
      case AuthorizationErrorCode.notInteractive:
        return 'Não foi possível concluir o login Apple neste momento.';
      case AuthorizationErrorCode.unknown:
        return 'Erro no Apple. Tente novamente.';
    }
  }

  static String friendlyGenericMessage(Object error) {
    final msg = error.toString();
    if (msg.contains('SignInWithAppleNotSupportedException') ||
        msg.contains('not available')) {
      return 'Entrar com Apple não está disponível neste dispositivo.';
    }
    return 'Erro no Apple. Tente novamente.';
  }
}

class _AppleOAuthParts {
  const _AppleOAuthParts({
    required this.credential,
    this.givenName,
    this.familyName,
  });

  final OAuthCredential credential;
  final String? givenName;
  final String? familyName;
}
