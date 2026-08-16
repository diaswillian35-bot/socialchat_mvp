import 'package:cloud_firestore/cloud_firestore.dart';

class AgeVerification {
  static const int minimumAge = 18;
  static const int maximumAge = 120;
  static const String policyVersion = '18plus-2026-08-15';

  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime latestEligibleBirthDate(DateTime today) =>
      DateTime(today.year - minimumAge, today.month, today.day);

  static DateTime earliestAllowedBirthDate(DateTime today) =>
      DateTime(today.year - maximumAge, today.month, today.day);

  static bool isAdult(DateTime birthDate, DateTime today) {
    final birth = dateOnly(birthDate);
    final current = dateOnly(today);
    var age = current.year - birth.year;
    if (current.month < birth.month ||
        (current.month == birth.month && current.day < birth.day)) {
      age--;
    }
    return age >= minimumAge;
  }

  static bool isReasonable(DateTime birthDate, DateTime today) {
    final birth = dateOnly(birthDate);
    final current = dateOnly(today);
    return !birth.isAfter(current) &&
        !birth.isBefore(earliestAllowedBirthDate(current));
  }

  static bool isVerified(Map<String, dynamic>? data) {
    if (data == null) return false;
    return data['ageVerificationStatus'] == 'verified' &&
        data['ageVerifiedAt'] is Timestamp &&
        data['dateOfBirth'] is Timestamp;
  }

  static String wireDate(DateTime value) {
    final d = dateOnly(value);
    return '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }
}
