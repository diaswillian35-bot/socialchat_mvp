import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/new_user_policy.dart';

Timestamp ts(DateTime d) => Timestamp.fromDate(d);

void main() {
  final now = DateTime(2026, 8, 26, 12);

  Map<String, dynamic> baseEligible({DateTime? completed}) => {
        'name': 'Ana',
        'profileComplete': true,
        'profileCompletedAt': ts(completed ?? now.subtract(const Duration(days: 2))),
        'ageVerificationStatus': 'verified',
        'nearbyEnabled': true,
        'homeCountryCode': 'br',
        'stateName': 'SC',
      };

  group('NewUserPolicy window', () {
    test('Novo during 7 days after profileCompletedAt', () {
      expect(
        NewUserPolicy.isWithinNewUserWindow(
          baseEligible(completed: now.subtract(const Duration(days: 6))),
          now: now,
        ),
        isTrue,
      );
      expect(
        NewUserPolicy.isWithinNewUserWindow(
          baseEligible(completed: now.subtract(const Duration(days: 7))),
          now: now,
        ),
        isFalse,
      );
    });

    test('legacy fallback uses updatedAt when profileComplete', () {
      final legacy = {
        'profileComplete': true,
        'updatedAt': ts(now.subtract(const Duration(days: 3))),
        'name': 'Legacy',
        'ageVerificationStatus': 'verified',
        'nearbyEnabled': true,
      };
      expect(NewUserPolicy.isWithinNewUserWindow(legacy, now: now), isTrue);
    });

    test('incomplete profile is never Novo', () {
      expect(
        NewUserPolicy.isEligibleDiscoverableNewUser({
          'createdAt': ts(now),
          'name': 'X',
        }, now: now),
        isFalse,
      );
    });
  });

  group('eligibility', () {
    test('requires verified, complete, discoverable, not banned', () {
      expect(NewUserPolicy.isEligibleDiscoverableNewUser(baseEligible(), now: now),
          isTrue);
      expect(
        NewUserPolicy.isEligibleDiscoverableNewUser({
          ...baseEligible(),
          'isBanned': true,
        }, now: now),
        isFalse,
      );
      expect(
        NewUserPolicy.isEligibleDiscoverableNewUser({
          ...baseEligible(),
          'nearbyEnabled': false,
        }, now: now),
        isFalse,
      );
    });

    test('recipient still Novo cannot receive aggregated push', () {
      expect(
        NewUserPolicy.canReceiveNewUsersPush(baseEligible(), now: now),
        isFalse,
      );
      expect(
        NewUserPolicy.canReceiveNewUsersPush({
          ...baseEligible(completed: now.subtract(const Duration(days: 30))),
          'notifEnabled': true,
        }, now: now),
        isTrue,
      );
    });
  });

  group('batch and cooldown', () {
    test('region key uses country|state without city PII', () {
      expect(
        NewUserPolicy.regionKey({
          'homeCountryCode': 'BR',
          'stateName': 'Santa Catarina',
          'cityName': 'Florianópolis',
        }),
        'br|santa catarina',
      );
    });

    test('cooldown 7 days per recipient', () {
      expect(
        NewUserPolicy.isRecipientCooldownActive({
          'lastNewUsersPushAt': ts(now.subtract(const Duration(days: 3))),
        }, now: now),
        isTrue,
      );
      expect(
        NewUserPolicy.isRecipientCooldownActive({
          'lastNewUsersPushAt': ts(now.subtract(const Duration(days: 8))),
        }, now: now),
        isFalse,
      );
    });

    test('push batch stays disabled until Rules protect field', () {
      expect(NewUserPolicy.pushBatchEnabled, isFalse);
    });

    test('idempotency key is deterministic', () {
      expect(
        NewUserPolicy.batchIdempotencyKey(
          recipientUid: 'u1',
          region: 'br|sc',
          batchWindowId: '2026-W34',
        ),
        'u1_br|sc_2026-W34',
      );
    });
  });
}
