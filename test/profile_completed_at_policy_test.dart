import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/profile_completed_at_policy.dart';

void main() {
  group('ProfileCompletedAtPolicy', () {
    test('writes once with server timestamp only on first completion', () {
      expect(
        ProfileCompletedAtPolicy.shouldWriteFirstTime(
          alreadyHasProfileCompletedAt: false,
        ),
        isTrue,
      );
      expect(
        ProfileCompletedAtPolicy.shouldWriteFirstTime(
          alreadyHasProfileCompletedAt: true,
        ),
        isFalse,
      );
      expect(ProfileCompletedAtPolicy.pushDependsOnField, isFalse);
    });

    test('applyFirstCompletionTimestamp is idempotent', () {
      final ts = FieldValue.serverTimestamp();
      final payload = <String, dynamic>{'profileComplete': true};
      ProfileCompletedAtPolicy.applyFirstCompletionTimestamp(
        payload: payload,
        existingUserData: const {},
        serverTimestamp: ts,
      );
      expect(payload['profileCompletedAt'], ts);

      final second = <String, dynamic>{'profileComplete': true};
      ProfileCompletedAtPolicy.applyFirstCompletionTimestamp(
        payload: second,
        existingUserData: {
          'profileCompletedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        },
        serverTimestamp: ts,
      );
      expect(second.containsKey('profileCompletedAt'), isFalse);
    });

    test('edit after completion cannot reset via merge helper', () {
      final ts = FieldValue.serverTimestamp();
      final payload = <String, dynamic>{
        'name': 'Updated',
        'profileComplete': true,
        'updatedAt': ts,
      };
      ProfileCompletedAtPolicy.applyFirstCompletionTimestamp(
        payload: payload,
        existingUserData: {
          'profileCompletedAt': Timestamp.fromDate(DateTime(2026, 1, 5)),
          'profileComplete': true,
        },
        serverTimestamp: ts,
      );
      expect(payload.containsKey('profileCompletedAt'), isFalse);
      expect(payload['name'], 'Updated');
    });
  });
}
