import 'package:flutter/foundation.dart';

/// Pure helpers for FCM token hygiene + iOS notification auth audit (unit-tested).
///
/// Does not invent online status or print full tokens.
class PushTokenSync {
  PushTokenSync._();

  static const bundleIdIos = 'com.remdy.app';

  /// APNs environment implied by build mode.
  /// Release/TestFlight/App Store → production. Debug → development.
  static String apsEnvironment({required bool isReleaseMode}) =>
      isReleaseMode ? 'production' : 'development';

  /// Fields written under `users/{uid}/fcmTokens/{token}`.
  static Map<String, Object?> tokenDocFields({
    required String token,
    required String platform,
    required String bundleId,
    required String apsEnvironment,
  }) {
    return {
      'token': token,
      'platform': platform,
      'bundleId': bundleId,
      'apsEnvironment': apsEnvironment,
    };
  }

  /// After rotating to [currentToken], which sibling token doc ids should be
  /// deleted? Keeps current token and non-iOS platforms (e.g. Android).
  static List<String> iosTokenDocsToPrune({
    required String currentToken,
    required Iterable<Map<String, String?>> docs,
  }) {
    final current = currentToken.trim();
    if (current.isEmpty) return const [];
    final out = <String>[];
    for (final d in docs) {
      final id = (d['id'] ?? '').trim();
      final tok = (d['token'] ?? id).trim();
      final platform = (d['platform'] ?? '').trim().toLowerCase();
      if (id.isEmpty) continue;
      if (tok == current || id == current) continue;
      // Only prune iOS (or unknown-on-iOS-client) siblings — never Android.
      if (platform == 'android') continue;
      if (platform.isEmpty || platform == 'ios' || platform == 'unknown') {
        out.add(id);
      }
    }
    return out;
  }

  /// Sanitize FCM error codes for logs (never include token material).
  static String sanitizeMessagingErrorCode(String? code) {
    final c = (code ?? '').trim();
    if (c.isEmpty) return 'unknown';
    // Keep messaging/* codes as-is — they contain no token.
    return c.length > 120 ? c.substring(0, 120) : c;
  }

  static bool isInvalidRegistrationCode(String? code) {
    final c = (code ?? '').trim();
    return c == 'messaging/registration-token-not-registered' ||
        c == 'messaging/invalid-registration-token';
  }

  /// Mask for diagnostics (never full token).
  static String maskToken(String? token) {
    final t = (token ?? '').trim();
    if (t.isEmpty) return '[empty]';
    if (t.length < 12) return '[short]';
    return '${t.substring(0, 6)}…${t.substring(t.length - 4)} (len=${t.length})';
  }

  static String bundleIdForPlatform(String platform) {
    if (platform == 'ios') return bundleIdIos;
    return '';
  }

  /// Normalize authorizationStatus enum name for logs (no PII).
  static String sanitizeAuthorizationStatus(String? status) {
    final s = (status ?? '').trim().toLowerCase();
    if (s.isEmpty) return 'unknown';
    if (s.length > 40) return s.substring(0, 40);
    return s;
  }

  /// Normalize AppleNotificationSetting-like values to on/off/unknown.
  static String sanitizeSettingFlag(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    if (v == 'enabled' || v == 'true' || v == 'on') return 'on';
    if (v == 'disabled' || v == 'false' || v == 'off') return 'off';
    if (v.isEmpty) return 'unknown';
    return 'other';
  }

  /// One-line sanitized iOS auth audit for debug logs (never tokens).
  static String formatIosAuthAuditLine({
    required String? authorizationStatus,
    required String? alert,
    required String? badge,
    required String? sound,
  }) {
    return 'iosNotifAuth '
        'status=${sanitizeAuthorizationStatus(authorizationStatus)} '
        'alert=${sanitizeSettingFlag(alert)} '
        'badge=${sanitizeSettingFlag(badge)} '
        'sound=${sanitizeSettingFlag(sound)}';
  }

  /// True when OS allows badge but not alert and not sound (Willian symptom).
  static bool isBadgeOnlyPresentation({
    required String? authorizationStatus,
    required String? alert,
    required String? badge,
    required String? sound,
  }) {
    final status = sanitizeAuthorizationStatus(authorizationStatus);
    if (status != 'authorized' && status != 'provisional') return false;
    final badgeOn = sanitizeSettingFlag(badge) == 'on';
    final alertOn = sanitizeSettingFlag(alert) == 'on';
    final soundOn = sanitizeSettingFlag(sound) == 'on';
    return badgeOn && !alertOn && !soundOn;
  }

  /// Offer manual Settings guidance when alerts/sounds are off (or denied).
  /// Does not imply auto-opening Settings.
  static bool shouldOfferNotificationSettingsGuidance({
    required String? authorizationStatus,
    required String? alert,
    required String? badge,
    required String? sound,
  }) {
    final status = sanitizeAuthorizationStatus(authorizationStatus);
    if (status == 'denied' || status == 'notdetermined') return true;
    if (isBadgeOnlyPresentation(
      authorizationStatus: authorizationStatus,
      alert: alert,
      badge: badge,
      sound: sound,
    )) {
      return true;
    }
    final alertOn = sanitizeSettingFlag(alert) == 'on';
    final soundOn = sanitizeSettingFlag(sound) == 'on';
    if (status == 'authorized' || status == 'provisional') {
      return !alertOn || !soundOn;
    }
    return false;
  }
}

/// Whether [pushAllowed] gates would pass for chat (mirrors Functions).
@visibleForTesting
bool pushAllowedChatClientPreview({
  required String? ageVerificationStatus,
  required bool? notifEnabled,
  required bool? notifChat,
}) {
  if (notifEnabled == false) return false;
  if (ageVerificationStatus != 'verified') return false;
  if (notifChat == false) return false;
  return true;
}
