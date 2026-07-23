import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/premium_access_service.dart';

/// Espelha a regra de acesso internacional usada no backend/rules.
bool isInternationalGroupAccess({
  required Map<String, dynamic> group,
  required Map<String, dynamic> user,
}) {
  if (group['isPremiumGroup'] == true) return true;
  String norm(dynamic v) => (v ?? '').toString().trim().toLowerCase();
  final home = norm(user['homeCountryCode']);
  final uc = home.isNotEmpty ? home : norm(user['countryCode']);
  final gc = norm(group['countryCode']);
  return uc.isNotEmpty && gc.isNotEmpty && uc != gc;
}

bool canAccessInternationalGroup({
  required Map<String, dynamic> group,
  required Map<String, dynamic> user,
  DateTime? now,
}) {
  if (!isInternationalGroupAccess(group: group, user: user)) return true;
  return PremiumAccessService.isPremiumActiveFromData(user, now: now);
}

void main() {
  final now = DateTime.utc(2026, 7, 22, 12);

  test('same country free user can access', () {
    expect(
      canAccessInternationalGroup(
        group: {'countryCode': 'br', 'isPremiumGroup': false},
        user: {'countryCode': 'br'},
        now: now,
      ),
      true,
    );
  });

  test('other country requires premium', () {
    expect(
      canAccessInternationalGroup(
        group: {'countryCode': 'ca', 'isPremiumGroup': false},
        user: {'countryCode': 'br'},
        now: now,
      ),
      false,
    );
    expect(
      canAccessInternationalGroup(
        group: {'countryCode': 'ca'},
        user: {'countryCode': 'br', 'isPremium': true},
        now: now,
      ),
      true,
    );
  });

  test('isPremiumGroup flag requires premium even same country', () {
    expect(
      canAccessInternationalGroup(
        group: {'countryCode': 'br', 'isPremiumGroup': true},
        user: {'countryCode': 'br'},
        now: now,
      ),
      false,
    );
  });
}
