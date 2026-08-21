import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'share_extension_destinations_service.dart';

/// Mints / renews / revokes the iOS Share Extension short-lived session.
/// Token is stored only natively (Keychain Access Group + App Group file).
class ShareExtensionSessionService {
  ShareExtensionSessionService._();

  /// Share Extension is embedded in Runner (Debug / Profile / Release).
  static const bool enabledForLaunch = true;

  static const MethodChannel _keychain = MethodChannel('remdy/share_session');

  /// Server TTL is 7d; renew when remaining < 50%. Throttle burst calls.
  static const Duration _minIssueGap = Duration(minutes: 5);
  static const int _sessionTtlMs = 7 * 24 * 60 * 60 * 1000;

  static DateTime? _lastIssueAt;
  static DateTime? _skipIssueUntil;
  static bool _started = false;
  static StreamSubscription<User?>? _authSub;
  static int _channelAttempts = 0;
  static Completer<void>? _gate;

  static bool get _supported =>
      enabledForLaunch &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Listen to restored sessions, login and later auth events.
  /// Does not require a new login when [FirebaseAuth.currentUser] already exists.
  static void start() {
    if (!_supported || _started) return;
    _started = true;
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        unawaited(ensureSession());
      }
    });
    final binding = SchedulerBinding.instance;
    binding.addPostFrameCallback((_) {
      unawaited(ensureSession());
      unawaited(Future<void>.delayed(const Duration(seconds: 2), ensureSession));
      unawaited(Future<void>.delayed(const Duration(seconds: 6), ensureSession));
    });
  }

  /// Call after login, restored session, app start and on foreground.
  static Future<void> ensureSession() async {
    if (!_supported) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    while (_gate != null) {
      await _gate!.future;
    }
    final gate = Completer<void>();
    _gate = gate;

    try {
      await _ensureSessionLocked(user);
    } finally {
      _gate = null;
      if (!gate.isCompleted) gate.complete();
    }
  }

  static Future<void> _ensureSessionLocked(User user) async {
    unawaited(ShareExtensionDestinationsService.publish());
    final nativeReady = await _nativeHasSession();
    try {
      await _keychain.invokeMethod<void>('markEnsure', {
        'hasUser': true,
        'nativeReady': nativeReady,
      });
    } catch (_) {}
    if (nativeReady &&
        _lastIssueAt != null &&
        DateTime.now().difference(_lastIssueAt!) < _minIssueGap) {
      return;
    }

    final needsIssue = !nativeReady || await _needsRenewal();
    if (!needsIssue) {
      _lastIssueAt ??= DateTime.now();
      return;
    }
    if (_skipIssueUntil != null && DateTime.now().isBefore(_skipIssueUntil!)) {
      return;
    }

    try {
      await user.getIdToken().timeout(const Duration(seconds: 15));
    } catch (e) {
      await _markCallable(ok: false, code: 'id_token_${e.runtimeType}');
      return;
    }

    Map<String, dynamic>? data;
    Object? lastError;
    for (var i = 0; i < 2; i++) {
      try {
        final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
            .httpsCallable(
          'issueShareExtensionSession',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
        );
        final result = await callable.call(<String, dynamic>{
          'deviceId': Platform.isIOS ? 'ios' : 'other',
        }).timeout(const Duration(seconds: 25));
        data = Map<String, dynamic>.from(result.data as Map);
        lastError = null;
        _skipIssueUntil = null;
        await _markCallable(ok: true, code: 'ok');
        break;
      } catch (e) {
        lastError = e;
        _logCallableFailure(e);
        final code = e is FirebaseFunctionsException
            ? e.code
            : e is TimeoutException
                ? 'timeout'
                : e.runtimeType.toString();
        await _markCallable(ok: false, code: code);
        if (e is FirebaseFunctionsException && e.code == 'not-found') {
          // Function not deployed — destinations cache path is enough; stop hammering.
          _skipIssueUntil = DateTime.now().add(const Duration(hours: 6));
          break;
        }
        await Future<void>.delayed(Duration(milliseconds: 500 * (i + 1)));
      }
    }
    if (data == null) {
      debugPrint(
        'ShareExtSession: issue failed after retries (${lastError.runtimeType})',
      );
      return;
    }
    final token = '${data['token'] ?? ''}';
    final sid = '${data['sid'] ?? ''}';
    final expiresAtMs = _asInt(data['expiresAtMs']);
    if (token.isEmpty || sid.isEmpty) {
      debugPrint('ShareExtSession: issue returned empty sid/token flags');
      return;
    }
    final saved = await _saveNativeWithRetry(
      token: token,
      sid: sid,
      expiresAtMs: expiresAtMs,
    );
    if (saved) {
      _lastIssueAt = DateTime.now();
      debugPrint(
        'ShareExtSession: native save confirmed sidLen=${sid.length} expSet=${expiresAtMs > 0}',
      );
    } else {
      debugPrint('ShareExtSession: native save not confirmed');
    }
  }

  static Future<void> _markCallable({required bool ok, required String code}) async {
    try {
      await _keychain.invokeMethod<void>('markCallable', {
        'ok': ok,
        'code': code,
      });
    } catch (_) {}
  }

  static Future<bool> _saveNativeWithRetry({
    required String token,
    required String sid,
    required int expiresAtMs,
  }) async {
    _channelAttempts = 0;
    for (var i = 0; i < 20; i++) {
      _channelAttempts++;
      try {
        final raw = await _keychain.invokeMethod<dynamic>('saveSession', {
          'token': token,
          'sid': sid,
          'expiresAtMs': expiresAtMs,
        });
        if (_saveLooksOk(raw) || await _nativeHasSession()) {
          return true;
        }
      } on MissingPluginException {
        debugPrint('ShareExtSession: channel not ready attempt=$_channelAttempts');
      } catch (e) {
        debugPrint('ShareExtSession: native save error ${e.runtimeType}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return _nativeHasSession();
  }

  static bool _saveLooksOk(dynamic raw) {
    if (raw is bool) return raw;
    if (raw is Map) {
      final map = Map<Object?, Object?>.from(raw);
      return map['ok'] == true || map['readable'] == true;
    }
    return false;
  }

  static Future<bool> _nativeHasSession() async {
    try {
      final value = await _keychain.invokeMethod<bool>('hasSession');
      return value == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _needsRenewal() async {
    try {
      final meta = await _keychain.invokeMethod<dynamic>('readSessionMeta');
      if (meta == null) return true;
      final map = Map<String, dynamic>.from(meta as Map);
      final expiresAtMs = _asInt(map['expiresAtMs']);
      if (expiresAtMs <= 0) return true;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (expiresAtMs <= now) return true;
      final remaining = expiresAtMs - now;
      return remaining < (_sessionTtlMs * 0.5).round();
    } catch (_) {
      return true;
    }
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  static void _logCallableFailure(Object e) {
    if (e is FirebaseFunctionsException) {
      debugPrint('ShareExtSession: callable failed code=${e.code}');
      return;
    }
    debugPrint('ShareExtSession: callable failed ${e.runtimeType}');
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
      debugPrint('ShareExtSession revoke remote failed: ${e.runtimeType}');
    }
    try {
      await _keychain.invokeMethod<void>('clearSession');
    } catch (_) {}
    _lastIssueAt = null;
  }
}
