import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';
import 'package:socialchat_mvp/services/portal_qr_error_text.dart';

void main() {
  setUpAll(() {
    final map = jsonDecode(File('lib/l10n/pt-BR.json').readAsStringSync())
        as Map<String, dynamic>;
    AppTexts.loadFromMap(map, const Locale('pt', 'BR'));
  });

  test('mapeia os códigos da Function para as chaves certas', () {
    expect(portalQrErrorKey('deadline-exceeded'), 'portal_qr_expired');
    expect(portalQrErrorKey('not-found'), 'portal_qr_session_not_found');
    expect(
      portalQrErrorKey('failed-precondition'),
      'portal_qr_unavailable',
    );
    expect(portalQrErrorKey('unauthenticated'), 'portal_qr_unauthenticated');
    expect(portalQrErrorKey('internal'), 'portal_qr_generic');
    expect(portalQrErrorKey(null), 'portal_qr_generic');
  });

  test('não mostra a mensagem crua da Function', () {
    final text = portalQrErrorText(
      FirebaseFunctionsException(
        code: 'failed-precondition',
        message: 'Session already consumed',
      ),
    );
    expect(text, 'Este QR Code não está mais disponível.');
    expect(text.toLowerCase(), isNot(contains('consumed')));
  });

  test('textos pt-BR iguais aos de hoje', () {
    expect(
      AppTexts.t('portal_qr_need_login'),
      'Faça login no app Remdy antes de autorizar o portal.',
    );
    expect(
      AppTexts.t('portal_qr_expired'),
      'QR Code expirado. Gere um novo no computador.',
    );
    expect(
      AppTexts.t('portal_qr_session_not_found'),
      'Sessão de login não encontrada.',
    );
    expect(
      AppTexts.t('portal_qr_unauthenticated'),
      'Faça login no app Remdy para continuar.',
    );
    expect(
      AppTexts.t('portal_qr_generic'),
      'Não foi possível autorizar o login.',
    );
  });

  test('validações do login conservam o pt-BR atual', () {
    expect(AppTexts.t('login_email_required'), 'Digite o e-mail.');
    expect(AppTexts.t('login_email_invalid'), 'Digite um e-mail válido.');
    expect(
      AppTexts.t('login_password_min_length'),
      'Senha precisa ter no mínimo 6 caracteres.',
    );
    expect(AppTexts.t('login_passwords_mismatch'), 'As senhas não conferem.');
    expect(
      AppTexts.t('login_test_hint').replaceAll('{email}', 'a@b.com'),
      'Dica: crie o usuário a@b.com no Firebase Auth (Email/Senha).',
    );
  });
}
