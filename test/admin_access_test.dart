import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/admin_access.dart';
import 'package:socialchat_mvp/services/remdy_launch_access.dart';

void main() {
  tearDown(() => AdminAccess.instance.debugSet(admin: false));

  test('só o email exato e verificado é admin', () {
    expect(AdminAccess.isAdminEmail(email: 'diaswillian35@gmail.com', verified: true), isTrue);
    expect(AdminAccess.isAdminEmail(email: ' DiasWillian35@gmail.com ', verified: true), isTrue);
    expect(AdminAccess.isAdminEmail(email: 'diaswillian35@gmail.com', verified: false), isFalse);
    expect(AdminAccess.isAdminEmail(email: 'outro@gmail.com', verified: true), isFalse);
    expect(AdminAccess.isAdminEmail(email: null, verified: true), isFalse);
  });

  test('não-admin continua preso ao próprio país', () {
    expect(AdminAccess.effectiveCountry('br'), 'br');
    expect(RemdyLaunchAccess.canAccessCountryContent(userHomeCountryCode: 'br', targetCountryCode: 'pt'), isFalse);
    expect(RemdyLaunchAccess.canAccessGroupCountry(userHomeCountryCode: 'br', groupCountryCode: 'ca'), isFalse);
  });

  test('admin vê todos os países e escolhe o país exibido', () {
    AdminAccess.instance.debugSet(admin: true, viewCountry: 'pt');
    expect(AdminAccess.effectiveCountry('br'), 'pt');
    expect(RemdyLaunchAccess.canAccessCountryContent(userHomeCountryCode: 'br', targetCountryCode: 'pt'), isTrue);
    expect(RemdyLaunchAccess.canAccessGroupCountry(userHomeCountryCode: 'br', groupCountryCode: 'ca'), isTrue);
    expect(RemdyLaunchAccess.showsComingSoonOnHome(userHomeCountryCode: 'br', targetCountryCode: 'ca'), isFalse);
  });

  test('regras de DM não têm exceção de admin', () {
    final rules = File('firestore.rules').readAsStringSync();
    expect(rules.contains('diaswillian35'), isFalse);
    expect(File('functions/super_admin.js').existsSync(), isTrue);
    final dm = File('functions/index.js').readAsStringSync();
    final start = dm.indexOf('exports.sendDmMessage');
    if (start >= 0) {
      final body = dm.substring(start, (start + 4000).clamp(0, dm.length));
      expect(body.contains('isSuperAdmin'), isFalse);
    }
  });
}
