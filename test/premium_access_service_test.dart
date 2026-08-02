import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/premium_access_service.dart';

void main() {
  final now = DateTime.utc(2026, 7, 22, 12);

  group('PremiumAccessService.parsePremiumUntil', () {
    test('null and empty', () {
      expect(PremiumAccessService.parsePremiumUntil(null), isNull);
      expect(PremiumAccessService.parsePremiumUntil(''), isNull);
      expect(PremiumAccessService.parsePremiumUntil('  '), isNull);
    });

    test('DateTime and Timestamp', () {
      final d = DateTime(2026, 8, 1, 12);
      expect(PremiumAccessService.parsePremiumUntil(d), d);
      final fromTs = PremiumAccessService.parsePremiumUntil(Timestamp.fromDate(d));
      expect(fromTs?.millisecondsSinceEpoch, d.millisecondsSinceEpoch);
    });

    test('millis and seconds', () {
      final d = DateTime(2026, 8, 1, 12);
      expect(
        PremiumAccessService.parsePremiumUntil(d.millisecondsSinceEpoch)
            ?.millisecondsSinceEpoch,
        d.millisecondsSinceEpoch,
      );
      expect(
        PremiumAccessService.parsePremiumUntil(
          d.millisecondsSinceEpoch ~/ 1000,
        )?.millisecondsSinceEpoch,
        d.millisecondsSinceEpoch,
      );
    });
  });

  group('PremiumAccessService.isPremiumActiveFromData', () {
    test('empty / null → false', () {
      expect(PremiumAccessService.isPremiumActiveFromData(null, now: now), false);
      expect(PremiumAccessService.isPremiumActiveFromData({}, now: now), false);
    });

    test('isMaster or isPremium → true', () {
      expect(
        PremiumAccessService.isPremiumActiveFromData(
          {'isMaster': true},
          now: now,
        ),
        true,
      );
      expect(
        PremiumAccessService.isPremiumActiveFromData(
          {'isPremium': true},
          now: now,
        ),
        true,
      );
    });

    test('future premiumUntil → true; past → false', () {
      expect(
        PremiumAccessService.isPremiumActiveFromData(
          {'premiumUntil': now.add(const Duration(days: 1))},
          now: now,
        ),
        true,
      );
      expect(
        PremiumAccessService.isPremiumActiveFromData(
          {'premiumUntil': now.subtract(const Duration(seconds: 1))},
          now: now,
        ),
        false,
      );
    });

    test('premiumType alone does not grant access', () {
      expect(
        PremiumAccessService.isPremiumActiveFromData(
          {'premiumType': 'trial', 'premiumSource': 'invite'},
          now: now,
        ),
        false,
      );
    });
  });
}
