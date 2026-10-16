import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/l10n/app_texts.dart';
import 'package:socialchat_mvp/pages/forgot_password_page.dart';

const _generic =
    'Se existir uma conta com este e-mail, enviaremos as instruções para redefinir a senha.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppTexts.loadFromMap(const {
      'email': 'E-mail',
      'password_reset_title': 'Recuperar senha',
      'password_reset_prompt': 'Digite seu e-mail',
      'password_reset_help':
          'Vamos enviar um link para você criar uma nova senha.',
      'password_reset_send': 'Enviar link',
      'password_reset_empty_email': 'Digite seu e-mail.',
      'password_reset_invalid_email': 'E-mail inválido.',
      'password_reset_generic': _generic,
      'password_reset_network':
          'Sem conexão. Verifique a internet e tente novamente.',
      'password_reset_later': 'Muitas tentativas. Tente novamente mais tarde.',
      'password_reset_back': 'Voltar ao login',
    }, const Locale('pt', 'BR'));
  });

  testWidgets('invalid email does not send a reset', (tester) async {
    var sent = 0;
    await tester.pumpWidget(_app((_) async => sent++));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'nao-e-email');
    await tester.tap(find.text('Enviar link'));
    await tester.pumpAndSettle();

    expect(find.text('E-mail inválido.'), findsOneWidget);
    expect(find.text(_generic), findsNothing);
    expect(sent, 0);
  });

  testWidgets('a completed request shows only the generic message',
      (tester) async {
    final gate = Completer<void>();
    var sent = 0;
    await tester.pumpWidget(_app((_) {
      sent++;
      return gate.future;
    }));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'person@example.com');
    await tester.tap(find.text('Enviar link'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(sent, 1);
    expect(find.text(_generic), findsOneWidget);
    expect(find.textContaining('Não encontrei'), findsNothing);
  });

  testWidgets('a missing account still shows the generic message',
      (tester) async {
    await tester.pumpWidget(_app(
      (_) async => throw FirebaseAuthException(code: 'user-not-found'),
    ));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'person@example.com');
    await tester.tap(find.text('Enviar link'));
    await tester.pumpAndSettle();

    expect(find.text(_generic), findsOneWidget);
    expect(find.textContaining('user-not-found'), findsNothing);
  });

  testWidgets('a network failure stays on the page with a connection error',
      (tester) async {
    await tester.pumpWidget(_app(
      (_) async => throw FirebaseAuthException(code: 'network-request-failed'),
    ));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'person@example.com');
    await tester.tap(find.text('Enviar link'));
    await tester.pumpAndSettle();

    expect(
      find.text('Sem conexão. Verifique a internet e tente novamente.'),
      findsOneWidget,
    );
    expect(find.text(_generic), findsNothing);
    expect(find.byType(ForgotPasswordPage), findsOneWidget);

    await tester.tap(find.byTooltip('Voltar ao login'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir'), findsOneWidget);
    expect(find.byType(ForgotPasswordPage), findsNothing);
  });
}

Widget _app(Future<void> Function(String email) send) {
  return MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ForgotPasswordPage(sendResetEmail: send),
              ),
            );
          },
          child: const Text('Abrir'),
        ),
      ),
    ),
  );
}
