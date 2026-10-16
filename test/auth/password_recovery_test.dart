import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/password_recovery.dart';

void main() {
  const generic = PasswordRecoveryStatus.genericSent;

  test('invalid email is rejected before any send', () async {
    var sent = 0;
    final status = await PasswordRecovery.request(
      email: 'nao-e-email',
      send: (_) async => sent++,
    );
    expect(status, PasswordRecoveryStatus.invalidEmail);
    expect(sent, 0);
  });

  test('a successful send is only the generic outcome', () async {
    String? received;
    final status = await PasswordRecovery.request(
      email: '  person@example.com  ',
      send: (email) async => received = email,
    );
    expect(status, generic);
    expect(received, 'person@example.com');
  });

  test('a missing account stays the generic outcome', () async {
    final status = await PasswordRecovery.request(
      email: 'person@example.com',
      send: (_) async => throw FirebaseAuthException(code: 'user-not-found'),
    );
    expect(status, generic);
  });

  test('a network failure is reported without a reset detail', () async {
    final status = await PasswordRecovery.request(
      email: 'person@example.com',
      send: (_) async =>
          throw FirebaseAuthException(code: 'network-request-failed'),
    );
    expect(status, PasswordRecoveryStatus.networkError);
  });
}
