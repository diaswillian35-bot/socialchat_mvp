import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';
import 'package:socialchat_mvp/services/auth_error_text.dart';

Map<String, dynamic> _loadJson(String code) =>
    jsonDecode(File('lib/l10n/$code.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  late Map<String, dynamic> ptBr;

  setUpAll(() {
    ptBr = _loadJson('pt-BR');
    AppTexts.loadFromMap(ptBr, const Locale('pt', 'BR'));
  });

  setUp(() {
    AppTexts.loadFromMap(ptBr, const Locale('pt', 'BR'));
  });

  group('authErrorKey', () {
    test('normaliza INVALID_LOGIN_CREDENTIALS e equivalentes', () {
      const same = 'auth_error_wrong_credentials';
      expect(authErrorKey('invalid-credential'), same);
      expect(authErrorKey('INVALID_LOGIN_CREDENTIALS'), same);
      expect(authErrorKey('invalid-login-credentials'), same);
      expect(authErrorKey('wrong-password'), same);
      expect(authErrorKey('user-not-found'), same);
      expect(authErrorKey('WRONG_PASSWORD'), same);
      expect(authErrorKey('USER_NOT_FOUND'), same);
    });

    test('mapeia os códigos pedidos para chaves conhecidas', () {
      expect(authErrorKey('invalid-email'), 'auth_error_invalid_email');
      expect(authErrorKey('user-disabled'), 'auth_error_user_disabled');
      expect(
        authErrorKey('email-already-in-use'),
        'auth_error_email_already_in_use',
      );
      expect(authErrorKey('weak-password'), 'auth_error_weak_password');
      expect(authErrorKey('too-many-requests'), 'auth_error_too_many_requests');
      expect(authErrorKey('network-request-failed'), 'auth_error_network');
      expect(
        authErrorKey('operation-not-allowed'),
        'auth_error_operation_not_allowed',
      );
      expect(
        authErrorKey('requires-recent-login'),
        'auth_error_requires_recent_login',
      );
      expect(
        authErrorKey('credential-already-in-use'),
        'auth_error_credential_already_in_use',
      );
      expect(
        authErrorKey('account-exists-with-different-credential'),
        'auth_error_account_exists_different',
      );
      expect(
        authErrorKey('expired-action-code'),
        'auth_error_expired_action_code',
      );
      expect(
        authErrorKey('invalid-action-code'),
        'auth_error_invalid_action_code',
      );
    });

    test('código desconhecido cai no fallback genérico', () {
      expect(authErrorKey('something-weird'), 'auth_error_generic');
      expect(authErrorKey(null), 'auth_error_generic');
      expect(authErrorKey(''), 'auth_error_generic');
      expect(
        authErrorKey('x', fallbackKey: 'auth_error_verify_email'),
        'auth_error_verify_email',
      );
    });

    test('Google e Apple não usam "e-mail ou senha" em invalid-credential', () {
      expect(
        authErrorKey('invalid-credential', source: AuthErrorSource.google),
        'auth_error_google_invalid_credential',
      );
      expect(
        authErrorKey(
          'INVALID_LOGIN_CREDENTIALS',
          source: AuthErrorSource.apple,
        ),
        'auth_error_apple_invalid_credential',
      );
      expect(
        authErrorKey(
          'apple-empty-identity-token',
          source: AuthErrorSource.apple,
        ),
        'auth_error_apple_empty_token',
      );
      expect(
        authErrorKey(
          'apple-empty-identity-token',
          source: AuthErrorSource.apple,
        ),
        isNot(
          authErrorKey('invalid-credential', source: AuthErrorSource.apple),
        ),
      );
    });

    test('Facebook mapeia conta já existente', () {
      expect(
        authErrorKey(
          'account-exists-with-different-credential',
          source: AuthErrorSource.facebook,
        ),
        'auth_error_facebook_account_exists',
      );
    });
  });

  group('authErrorText', () {
    test('trio de login mostra o mesmo texto em pt-BR', () {
      const expected = 'E-mail ou senha incorretos';
      for (final code in [
        'invalid-credential',
        'INVALID_LOGIN_CREDENTIALS',
        'wrong-password',
        'user-not-found',
      ]) {
        expect(authErrorText(FirebaseAuthException(code: code)), expected);
      }
    });

    test('não devolve a mensagem crua do Firebase', () {
      final text = authErrorText(
        FirebaseAuthException(
          code: 'wrong-password',
          message:
              'The password is invalid or the user does not have a password.',
        ),
      );
      expect(text, 'E-mail ou senha incorretos');
      expect(text.toLowerCase(), isNot(contains('invalid')));
    });

    test('textos pt-BR dos códigos principais', () {
      expect(authErrorTextForCode('invalid-email'), 'E-mail inválido.');
      expect(
        authErrorTextForCode('user-disabled'),
        'Esta conta foi desativada.',
      );
      expect(
        authErrorTextForCode('email-already-in-use'),
        'Este e-mail já está em uso. Entre ou recupere a senha.',
      );
      expect(
        authErrorTextForCode('weak-password'),
        'A senha precisa ter no mínimo 6 caracteres.',
      );
      expect(
        authErrorTextForCode('too-many-requests'),
        'Muitas tentativas. Tente novamente mais tarde.',
      );
      expect(
        authErrorTextForCode('network-request-failed'),
        'Sem conexão. Verifique a internet e tente novamente.',
      );
      expect(
        authErrorTextForCode('operation-not-allowed'),
        'Este método de login não está habilitado. Tente outro.',
      );
      expect(
        authErrorTextForCode('requires-recent-login'),
        'Faça login novamente para continuar.',
      );
      expect(
        authErrorTextForCode('credential-already-in-use'),
        'Esta credencial já está vinculada a outra conta Remdy.',
      );
      expect(
        authErrorTextForCode('account-exists-with-different-credential'),
        'Esta conta já existe. Entre com o método de login original e vincule o novo método nas configurações.',
      );
      expect(
        authErrorTextForCode('expired-action-code'),
        'Este link expirou. Solicite um novo.',
      );
      expect(
        authErrorTextForCode('invalid-action-code'),
        'Este link é inválido ou já foi usado. Solicite um novo.',
      );
      expect(
        authErrorTextForCode('unknown-code'),
        'Não foi possível autenticar. Tente novamente.',
      );
    });
  });

  group('catálogo l10n', () {
    const files = ['pt-BR', 'pt-PT', 'en', 'es', 'fr'];

    test('as 5 línguas têm as mesmas chaves auth_error_*', () {
      final keysByFile = {
        for (final code in files)
          code: _loadJson(
            code,
          ).keys.where((k) => k.startsWith('auth_error_')).toSet(),
      };
      final expected = keysByFile['pt-BR']!;
      expect(expected, isNotEmpty);
      for (final code in files) {
        expect(
          keysByFile[code],
          expected,
          reason: '$code com chaves diferentes de pt-BR',
        );
      }
    });

    test('nenhum texto auth_error_* vazio', () {
      for (final code in files) {
        final map = _loadJson(code);
        final empty = map.entries
            .where(
              (e) =>
                  e.key.startsWith('auth_error_') &&
                  e.value is String &&
                  (e.value as String).trim().isEmpty,
            )
            .map((e) => e.key)
            .toList();
        expect(empty, isEmpty, reason: '$code vazio: $empty');
      }
    });
  });
}
