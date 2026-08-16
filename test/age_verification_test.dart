import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/age_verification.dart';

void main() {
  final today = DateTime(2026, 8, 15);

  test('accepts someone turning 18 today', () {
    expect(AgeVerification.isAdult(DateTime(2008, 8, 15), today), isTrue);
  });

  test('blocks someone turning 18 tomorrow', () {
    expect(AgeVerification.isAdult(DateTime(2008, 8, 16), today), isFalse);
  });

  test('handles leap-day birthday by calendar date', () {
    expect(
        AgeVerification.isAdult(DateTime(2008, 2, 29), DateTime(2026, 2, 28)),
        isFalse);
    expect(AgeVerification.isAdult(DateTime(2008, 2, 29), DateTime(2026, 3, 1)),
        isTrue);
  });

  test('rejects future and excessively old dates', () {
    expect(AgeVerification.isReasonable(DateTime(2027), today), isFalse);
    expect(AgeVerification.isReasonable(DateTime(1800), today), isFalse);
  });

  test('uses documented canonical wire format', () {
    expect(AgeVerification.wireDate(DateTime(2000, 2, 9)), '2000-02-09');
    expect(AgeVerification.policyVersion, '18plus-2026-08-15');
  });
}
