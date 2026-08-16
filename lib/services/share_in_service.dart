import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'age_access_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_texts.dart';
import '../models/share_in_payload.dart';
import '../pages/share_in_page.dart';
import 'push_service.dart';
import 'share_in_parser.dart';

/// Orquestra recebimento nativo → fila persistente → Auth/Navigator → ShareInPage → ack.
class ShareInService {
  ShareInService._();

  static const MethodChannel channel = MethodChannel('remdy/share_in');
  static const String pendingPrefsKey = 'pending_share_in_json';
  static const String shareRoutePrefix = 'share_in/';
  static const Duration dedupTtl = Duration(minutes: 2);

  static bool _started = false;
  static bool _openingUi = false;
  static bool _applyingPending = false;
  static bool _pollingNative = false;

  static final Map<String, DateTime> _seenFingerprints = {};
  static final Set<String> _openedIntentIds = {};
  static String? _inflightIntentId;
  static String? _activeFingerprint;
  static String? _sentFingerprint;

  @visibleForTesting
  static void resetForTest() {
    _started = false;
    _openingUi = false;
    _applyingPending = false;
    _pollingNative = false;
    _seenFingerprints.clear();
    _openedIntentIds.clear();
    _inflightIntentId = null;
    _activeFingerprint = null;
    _sentFingerprint = null;
  }

  /// Native share entry is Android-only for first launch.
  /// iOS Share Extension is deferred — see
  /// `tmp_part8/ios_share_extension_full/ARCHITECTURE.md`.
  static bool get iosShareInDeferred =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool get nativeShareInEnabled => !iosShareInDeferred;

  static Future<void> start() async {
    if (_started) return;
    _started = true;

    if (iosShareInDeferred) {
      // Drop any leftover iOS handoff queue — extension removed from launch build.
      await clearPending();
      await _trace('dart_start_skipped_ios_deferred', {});
      return;
    }

    channel.setMethodCallHandler(_onMethodCall);
    await _trace('dart_start', {});

    // Retry: canal nativo pode atrasar alguns frames após cold start.
    for (var i = 0; i < 20; i++) {
      try {
        final initial = await channel.invokeMethod<dynamic>('getInitialShare');
        if (initial is Map) {
          await _trace('dart_received', {
            'intentId': '${initial['intentId']}',
            'via': 'getInitialShare',
          });
          await ingestNativeMap(Map<dynamic, dynamic>.from(initial));
          return;
        }
        await _trace('dart_received_empty', {'attempt': i});
        break;
      } catch (e) {
        await _trace('getInitialShare_retry', {'attempt': i, 'error': '$e'});
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  }

  /// Chamado em toda volta ao foreground (ícone / background), sem cabo/debugger.
  static Future<void> onAppResumed() async {
    if (iosShareInDeferred) return;
    await _trace('app_resumed', {});
    await applyPendingIfAny();
    await pollNativePending();
  }

  static Future<void> pollNativePending() async {
    if (iosShareInDeferred) return;
    if (_pollingNative) return;
    _pollingNative = true;
    try {
      final peek = await channel.invokeMethod<dynamic>('peekPendingShare');
      if (peek is Map) {
        await _trace('dart_received', {
          'intentId': '${peek['intentId']}',
          'via': 'peekPendingShare',
        });
        await ingestNativeMap(Map<dynamic, dynamic>.from(peek));
      }
    } catch (e) {
      await _trace('peek_failed', {'error': '$e'});
    } finally {
      _pollingNative = false;
    }
  }

  static Future<dynamic> _onMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onShare':
        final args = call.arguments;
        if (args is Map) {
          await _trace('dart_received', {
            'intentId': '${args['intentId']}',
            'via': 'onShare',
          });
          await ingestNativeMap(Map<dynamic, dynamic>.from(args));
        }
        return null;
      default:
        throw PlatformException(code: 'not_implemented', message: call.method);
    }
  }

  static Future<ShareInIngestOutcome> ingestNativeMap(
    Map<dynamic, dynamic> raw, {
    SharedPreferences? prefs,
  }) async {
    final parsed = ShareInParser.parseNativeMap(raw);
    if (!parsed.isOk || parsed.payload == null) {
      _toastKey(parsed.errorKey ?? 'share_in_invalid');
      // Conteúdo inválido: limpa nativo para não loopar.
      await _ackNative(raw['intentId']?.toString());
      return ShareInIngestOutcome.rejected;
    }
    return ingestPayload(parsed.payload!, prefs: prefs);
  }

  static Future<ShareInIngestOutcome> ingestPayload(
    ShareInPayload payload, {
    SharedPreferences? prefs,
    bool skipUi = false,
  }) async {
    _pruneDedup();

    if (_openedIntentIds.contains(payload.intentId) ||
        _sentFingerprint == payload.fingerprint) {
      await _ackNative(payload.intentId);
      return ShareInIngestOutcome.duplicate;
    }
    if (_inflightIntentId == payload.intentId || _openingUi) {
      return ShareInIngestOutcome.duplicate;
    }
    if (_activeFingerprint == payload.fingerprint) {
      return ShareInIngestOutcome.duplicate;
    }

    // Fila persistente até a página estar no Navigator.
    final prefsInst = prefs ?? await SharedPreferences.getInstance();
    final existingRaw = prefsInst.getString(pendingPrefsKey);
    if (existingRaw != null && existingRaw.isNotEmpty) {
      try {
        final existing = jsonDecode(existingRaw) as Map<String, dynamic>;
        if (existing['intentId'] == payload.intentId) {
          // Mesma intent já enfileirada — não reprocessa em loop.
          if (_currentUser() == null) {
            return ShareInIngestOutcome.duplicate;
          }
        }
      } catch (_) {}
    }
    await persistPending(payload, prefs: prefsInst);
    await _trace('queued', {'intentId': payload.intentId});

    final user = await _waitForUser();
    if (user == null) {
      await _trace('auth_waiting', {'intentId': payload.intentId});
      _toastKey('share_in_login_needed');
      return ShareInIngestOutcome.pendingLogin;
    }
    await _trace('auth_ready', {'uid': user.uid});

    if (skipUi) {
      return ShareInIngestOutcome.pendingLogin;
    }

    _inflightIntentId = payload.intentId;
    _activeFingerprint = payload.fingerprint;
    _seenFingerprints[payload.fingerprint] = DateTime.now();

    final opened = await openShareUi(payload);
    _inflightIntentId = null;

    if (!opened) {
      await _trace('page_not_opened', {'intentId': payload.intentId});
      _activeFingerprint = null;
      // Mantém prefs + arquivo nativo.
      return ShareInIngestOutcome.queued;
    }

    _openedIntentIds.add(payload.intentId);
    await clearPending(prefs: prefs);
    await _ackNative(payload.intentId);
    await _trace('ack_written', {'intentId': payload.intentId});
    return ShareInIngestOutcome.openedUi;
  }

  static Future<void> _ackNative(String? intentId) async {
    if (intentId == null || intentId.isEmpty) return;
    try {
      await channel.invokeMethod<dynamic>('ackPendingShare', {
        'intentId': intentId,
      });
    } catch (e) {
      await _trace('ack_failed', {'intentId': intentId, 'error': '$e'});
    }
  }

  static Future<void> _trace(String event, Map<String, Object?> data) async {
    if (kDebugMode) {
      debugPrint('ShareIn[$event]: $data');
    }
    try {
      await channel.invokeMethod<dynamic>('appendTrace', {
        'event': event,
        ...data,
      });
    } catch (_) {}
  }

  /// Após AuthGate autenticado — processa fila prefs + poll nativo.
  static Future<void> applyPendingIfAny({SharedPreferences? prefs}) async {
    if (iosShareInDeferred) return;
    if (_applyingPending) return;
    _applyingPending = true;
    try {
      await _trace('apply_pending_start', {});
      final p = prefs ?? await SharedPreferences.getInstance();
      final raw = p.getString(pendingPrefsKey);
      if (raw != null && raw.isNotEmpty && _currentUser() != null) {
        try {
          final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          final payload = ShareInPayload.fromJson(json);
          if (payload.text.isNotEmpty) {
            final reparsed = ShareInParser.parseText(
              payload.text,
              intentId: payload.intentId.isEmpty
                  ? 'pending_${payload.receivedAtMs}'
                  : payload.intentId,
              subject: payload.subject,
              source: payload.source,
              receivedAtMs: payload.receivedAtMs,
            );
            if (reparsed.isOk && reparsed.payload != null) {
              _seenFingerprints.remove(reparsed.payload!.fingerprint);
              await ingestPayload(reparsed.payload!, prefs: p);
            }
          }
        } catch (_) {
          await p.remove(pendingPrefsKey);
        }
      }
      await pollNativePending();
    } finally {
      _applyingPending = false;
    }
  }

  static Future<void> markSent(ShareInPayload payload) async {
    _sentFingerprint = payload.fingerprint;
    _activeFingerprint = null;
    await clearPending();
  }

  static Future<void> markCancelled(ShareInPayload payload) async {
    if (_activeFingerprint == payload.fingerprint) {
      _activeFingerprint = null;
    }
    await clearPending();
  }

  @visibleForTesting
  static bool isDuplicateFingerprintForTest(String fingerprint) =>
      _isDuplicateFingerprint(fingerprint);

  @visibleForTesting
  static Future<void> persistPending(
    ShareInPayload payload, {
    SharedPreferences? prefs,
  }) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    await p.setString(pendingPrefsKey, jsonEncode(payload.toJson()));
  }

  static Future<void> clearPending({SharedPreferences? prefs}) async {
    final p = prefs ?? await SharedPreferences.getInstance();
    await p.remove(pendingPrefsKey);
  }

  static bool _isDuplicateFingerprint(String fingerprint) {
    if (_activeFingerprint == fingerprint) return true;
    final seen = _seenFingerprints[fingerprint];
    if (seen == null) return false;
    return DateTime.now().difference(seen) < dedupTtl;
  }

  static void _pruneDedup() {
    final now = DateTime.now();
    _seenFingerprints.removeWhere((_, t) => now.difference(t) > dedupTtl);
  }

  /// Aguarda AuthGate + Navigator; faz **push** (não destrói AuthGate).
  /// Retorna true só se a ShareInPage ficou no stack.
  static Future<bool> openShareUi(ShareInPayload payload) async {
    if (_openingUi) return false;
    if (_currentUser() == null) {
      await persistPending(payload);
      return false;
    }
    if (!await AgeAccessService.currentUserIsVerified()) {
      await persistPending(payload);
      return false;
    }
    _openingUi = true;
    try {
      for (var i = 0; i < 60; i++) {
        final nav = PushService.navKey.currentState;
        final user = _currentUser();
        if (nav != null && user != null) {
          await _trace('navigator_ready', {'attempt': i});
          final routeName = '$shareRoutePrefix${payload.intentId}';

          await Future<void>.delayed(Duration.zero);
          final completer = Completer<void>();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!completer.isCompleted) completer.complete();
          });
          await completer.future;

          nav.push(
            MaterialPageRoute<void>(
              settings: RouteSettings(name: routeName),
              builder: (_) => ShareInPage(payload: payload),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final opened = nav.canPop();
          if (opened) {
            await _trace('page_opened', {
              'intentId': payload.intentId,
              'route': routeName,
            });
            return true;
          }
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
      await persistPending(payload);
      return false;
    } finally {
      _openingUi = false;
    }
  }

  static Future<User?> _waitForUser({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final cur = _currentUser();
    if (cur is User) return cur;
    try {
      final user = await FirebaseAuth.instance
          .authStateChanges()
          .firstWhere((u) => u != null)
          .timeout(timeout);
      return user;
    } catch (_) {
      final again = _currentUser();
      return again is User ? again : null;
    }
  }

  static void _toastKey(String key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = PushService.navKey.currentContext;
      if (c == null) return;
      String text = key;
      try {
        text = AppTexts.current.get(key);
      } catch (_) {}
      ScaffoldMessenger.of(c).showSnackBar(
        SnackBar(
          content: Text(text),
          behavior: SnackBarBehavior.floating,
        ),
      );
    });
  }

  static dynamic _currentUser() {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }
}

enum ShareInIngestOutcome {
  openedUi,
  pendingLogin,
  duplicate,
  rejected,
  queued,
}
