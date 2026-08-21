import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String source(String path) => File(path).readAsStringSync();

  test('AuthGate and Splash gate restored sessions before MainShell', () {
    final authGate = source('lib/pages/auth_gate.dart');
    final splash = source('lib/pages/splash_page.dart');
    expect(authGate, contains('AgeVerification.isVerified'));
    expect(authGate.indexOf('AgeVerification.isVerified'),
        lessThan(authGate.lastIndexOf('return const MainShell')));
    expect(splash, contains('AgeVerification.isVerified'));
    expect(splash.indexOf('AgeVerification.isVerified'),
        lessThan(splash.indexOf('_replace(const AuthGate())')));
  });

  test('notification, event link, group link, and share entry points guard age',
      () {
    for (final path in <String>[
      'lib/services/push_service.dart',
      'lib/services/event_deep_link_service.dart',
      'lib/services/share_in_service.dart',
      'lib/services/share_extension_incoming_service.dart',
      'lib/main.dart',
    ]) {
      expect(source(path), contains('AgeAccessService.currentUserIsVerified()'),
          reason: path);
    }
  });

  test('pending links are processed only after AuthGate verifies age', () {
    final authGate = source('lib/pages/auth_gate.dart');
    final verified = authGate.indexOf('AgeVerification.isVerified');
    expect(authGate.indexOf('EventDeepLinkService.applyPendingIfAny()'),
        greaterThan(verified));
    expect(authGate.indexOf('ShareInService.applyPendingIfAny()'),
        greaterThan(verified));
    expect(authGate.indexOf('_applyPendingGroupIfAny(user)'),
        greaterThan(verified));
  });
}
