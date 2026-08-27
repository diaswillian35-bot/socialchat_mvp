import 'package:cloud_firestore/cloud_firestore.dart';

/// Client-side policy for immutable `profileCompletedAt`.
///
/// Server Rules (published) do **not** yet enforce immutability — see audit in
/// `tmp_part8/notifications/PROFILE_BUILD_FINAL_REVIEW.md`. Push batching must
/// not rely on this field until Rules are deployed.
class ProfileCompletedAtPolicy {
  ProfileCompletedAtPolicy._();

  static const pushDependsOnField = false;

  static bool alreadySet(Map<String, dynamic> userData) {
    final v = userData['profileCompletedAt'];
    return v != null;
  }

  /// Write at most once, always with server timestamp (never client DateTime).
  static bool shouldWriteFirstTime({required bool alreadyHasProfileCompletedAt}) {
    return !alreadyHasProfileCompletedAt;
  }

  /// Merge helper — never includes `profileCompletedAt` when already set.
  static void applyFirstCompletionTimestamp({
    required Map<String, dynamic> payload,
    required Map<String, dynamic> existingUserData,
    required FieldValue serverTimestamp,
  }) {
    if (shouldWriteFirstTime(
      alreadyHasProfileCompletedAt: alreadySet(existingUserData),
    )) {
      payload['profileCompletedAt'] = serverTimestamp;
    }
  }
}
