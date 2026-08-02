import 'dart:io' show Platform;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Mints / renews / revokes the iOS Share Extension short-lived session.
/// Token is stored only in the Keychain Access Group (native), never prefs.
///
/// Launch pause: Share Extension is not embedded in the shipping Runner.
/// Keep code ready; do not mint sessions until re-enabled for a release.
class ShareExtensionSessionService {
  ShareExtensionSessionService._();

  /// Flip to true when Share Extension returns to a shipping build.
  static const bool enabledForLaunch = false;

  static const MethodChannel _keychain = MethodChannel('remdy/share_session');
  /// Server TTL is 7d; renew when remaining < 50%. Throttle burst calls.
  static const Duration _minIssueGap = Duration(minutes: 5);
  static const int _sessionTtlMs = 7 * 24 * 60 * 60 * 1000;

  static DateTime? _lastIssueAt;
  static bool _busy = false;

  static bool get _supported =>
      enabledForLaunch &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Call after login and on foreground. No-ops on Android/web.
  static Future<void> ensureSession() async {
    if (!_supported) return;
    if (_busy) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (_lastIssueAt != null &&
        DateTime.now().difference(_lastIssueAt!) < _minIssueGap) {
      return;
    }

    final needsIssue = await _needsRenewal();
    if (!needsIssue) return;

    _busy = true;
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('issueShareExtensionSession');
      final result = await callable.call(<String, dynamic>{
        'deviceId': Platform.isIOS ? 'ios' : 'other',
      });
      final data = Map<String, dynamic>.from(result.data as Map);
      final token = '${data['token'] ?? ''}';
      final sid = '${data['sid'] ?? ''}';
      final expiresAtMs = data['expiresAtMs'];
      if (token.isEmpty || sid.isEmpty) return;
      await _keychain.invokeMethod<void>('saveSession', {
        'token': token,
        'sid': sid,
        'expiresAtMs': expiresAtMs,
      });
      _lastIssueAt = DateTime.now();
      if (kDebugMode) {
        debugPrint('ShareExtSession: issued sid=${sid.substring(0, 6)}…');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ShareExtSession ensure failed: $e');
      }
    } finally {
      _busy = false;
    }
  }

  static Future<bool> _needsRenewal() async {
    try {
      final meta = await _keychain.invokeMethod<dynamic>('readSessionMeta');
      if (meta == null) return true;
      final map = Map<String, dynamic>.from(meta as Map);
      final exp = map['expiresAtMs'];
      final expiresAtMs = exp is int
          ? exp
          : exp is num
              ? exp.toInt()
              : int.tryParse('$exp') ?? 0;
      if (expiresAtMs <= 0) return true;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (expiresAtMs <= now) return true;
      final remaining = expiresAtMs - now;
      return remaining < (_sessionTtlMs * 0.5).round();
    } catch (_) {
      return true;
    }
  }

  /// Logout / ban / delete — revoke server sessions and wipe Keychain.
  static Future<void> revokeLocalAndRemote() async {
    if (!_supported) return;
    try {
      if (FirebaseAuth.instance.currentUser != null) {
        final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable('revokeShareExtensionSessions');
        await callable.call(<String, dynamic>{});
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ShareExtSession revoke remote failed: $e');
      }
    }
    try {
      await _keychain.invokeMethod<void>('clearSession');
    } catch (_) {}
    _lastIssueAt = null;
  }
}
