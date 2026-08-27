import 'package:cloud_firestore/cloud_firestore.dart';

/// "Novo" user eligibility — 7 days after profile completion.
///
/// Discoverable maps to `nearbyEnabled` (existing field). Legacy profiles
/// without `profileCompletedAt` fall back safely.
class NewUserPolicy {
  NewUserPolicy._();

  /// Push batching must stay OFF until Firestore Rules immutably protect
  /// `profileCompletedAt` (see ProfileCompletedAtPolicy.pushDependsOnField).
  static const pushBatchEnabled = false;

  static const newUserWindowDays = 7;
  static const batchSize = 10;
  static const recipientCooldownDays = 7;

  static const pushTitleKey = 'new_users_push_title';
  static const pushBody =
      'Novas pessoas chegaram à Remdy. Venha dar um oi!';

  /// Reference instant for "Novo" window.
  static DateTime? profileCompletedInstant(Map<String, dynamic> data) {
    final completedAt = data['profileCompletedAt'];
    if (completedAt is Timestamp) return completedAt.toDate();

    // Legacy: profile marked complete — use updatedAt or createdAt.
    if (data['profileComplete'] == true) {
      final updatedAt = data['updatedAt'];
      if (updatedAt is Timestamp) return updatedAt.toDate();
      final createdAt = data['createdAt'];
      if (createdAt is Timestamp) return createdAt.toDate();
    }

    // Very old incomplete profiles: not "Novo".
    return null;
  }

  static bool isWithinNewUserWindow(
    Map<String, dynamic> data, {
    DateTime? now,
  }) {
    final instant = profileCompletedInstant(data);
    if (instant == null) return false;
    final clock = now ?? DateTime.now();
    return clock.difference(instant).inDays < newUserWindowDays;
  }

  /// Shown on Home carousel / list with green "Novo" selo.
  static bool showsNewBadge(
    Map<String, dynamic> data, {
    DateTime? now,
  }) {
    return isEligibleDiscoverableNewUser(data, now: now);
  }

  /// Eligible to appear as a new user (Home, push batch counting).
  static bool isEligibleDiscoverableNewUser(
    Map<String, dynamic> data, {
    DateTime? now,
  }) {
    if (!_isActive(data)) return false;
    if (data['ageVerificationStatus'] != 'verified') return false;
    if (data['profileComplete'] != true) return false;
    if (data['nearbyEnabled'] != true) return false;
    if ((data['name'] ?? '').toString().trim().isEmpty) return false;
    return isWithinNewUserWindow(data, now: now);
  }

  /// Recipient may receive aggregated "new users" push.
  static bool canReceiveNewUsersPush(
    Map<String, dynamic> recipientData, {
    DateTime? now,
  }) {
    if (!_isActive(recipientData)) return false;
    if (recipientData['notifEnabled'] == false) return false;
    if (recipientData['ageVerificationStatus'] != 'verified') return false;
    // Still "Novo" → excluded from receiving.
    if (isWithinNewUserWindow(recipientData, now: now)) return false;
    return true;
  }

  /// Cooldown: max 1 aggregated push per recipient per 7 days.
  static bool isRecipientCooldownActive(
    Map<String, dynamic> recipientData, {
    DateTime? now,
  }) {
    final last = recipientData['lastNewUsersPushAt'];
    if (last is! Timestamp) return false;
    final clock = now ?? DateTime.now();
    return clock.difference(last.toDate()).inDays < recipientCooldownDays;
  }

  /// Region key for batching (country + optional state; never city/PII).
  static String regionKey(Map<String, dynamic> data) {
    final country = (data['homeCountryCode'] ?? data['countryCode'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final state = (data['stateName'] ?? data['state'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (country.isEmpty) return 'unknown';
    if (state.isEmpty) return country;
    return '$country|$state';
  }

  /// Idempotency doc id for a batch send to a recipient in a region window.
  static String batchIdempotencyKey({
    required String recipientUid,
    required String region,
    required String batchWindowId,
  }) {
    return '${recipientUid}_${region}_$batchWindowId';
  }

  static bool _isActive(Map<String, dynamic> data) {
    if (data['isBanned'] == true) return false;
    if (data['deleted'] == true || data['isDeleted'] == true) return false;
    if (data['accountDeleted'] == true) return false;
    return true;
  }
}
