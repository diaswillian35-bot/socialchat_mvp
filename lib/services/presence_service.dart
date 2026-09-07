import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'online_status.dart';
import 'presence_diagnostics.dart';
import 'presence_display_hub.dart';
import 'presence_lifecycle.dart';
import 'presence_rtdb_config.dart';
import 'presence_heartbeat_gate.dart';
import 'presence_session_state.dart';
import 'presence_writer_recovery.dart';

/// Presença via Realtime Database.
///
/// Cliente escreve **somente** `presence/{uid}/connections/{connectionId}`.
/// Contadores: Cloud Function atômica (Firestore) + mirror RTDB.
///
/// Sessão amarrada ao Auth (não ao lifetime do MainShell).
class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  static const Duration onlineWindow = OnlineStatus.onlineWindow;
  static const Duration clockSkewTolerance = OnlineStatus.clockSkewTolerance;
  static const Duration queryLookbackExtra = OnlineStatus.queryLookbackExtra;
  static const Duration deferredOfflineDelay = Duration(seconds: 60);

  static const _legacyPrefsConnectionKey = 'remdy_presence_connection_id';

  final _fs = FirebaseFirestore.instance;
  final PresenceDiagnostics diagnostics = PresenceDiagnostics();

  FirebaseDatabase get _rtdb => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: PresenceRtdbConfig.databaseURL,
      );

  Timer? _deferredOfflineTimer;
  Timer? _heartbeatTimer;
  Timer? _recoveryTimer;
  StreamSubscription<DatabaseEvent>? _connectedSub;
  StreamSubscription<User?>? _authSub;
  Future<void> _opChain = Future<void>.value();
  bool _started = false;
  bool _foreground = true;
  bool _observerRegistered = false;
  bool _connectionActive = false;
  bool _legacyPrefsCleared = false;
  bool _rtdbConnected = false;
  bool _recoveryInFlight = false;
  PresenceSessionPhase _phase = PresenceSessionPhase.offline;
  DateTime? _lastHeartbeatAt;
  final SeparateHeartbeatGate _hbGate = SeparateHeartbeatGate();
  final PresenceWriterRecovery _recovery = PresenceWriterRecovery();
  /// Último modo sanitizado: `legacy` | `new` | `denied` | `dual` | `probed`.
  String _heartbeatDiag = 'unknown';

  String? _uid;
  String? _connectionId;
  DateTime? _lastFirestoreLastSeenWrite;

  DatabaseReference? _connectionRef;

  String? get debugConnectionId => _connectionId;
  String? get debugActiveUid => _uid;
  bool get debugConnectionActive => _connectionActive;
  bool get debugStarted => _started;
  bool get debugRecoveryScheduled => _recoveryTimer != null;
  int get debugRecoveryFailures => _recovery.consecutiveFailures;
  String get debugHeartbeatDiag => _heartbeatDiag;
  bool get debugSeparateHeartbeatDenied => _hbGate.denied;
  int get debugSeparateHeartbeatAttempts => _hbGate.attempts;
  bool get debugSeparateHeartbeatProbed => _hbGate.probedThisSession;
  PresenceSessionPhase get debugPhase => _phase;
  int? get debugHeartbeatAgeSec {
    final at = _lastHeartbeatAt;
    if (at == null) return null;
    return DateTime.now().difference(at).inSeconds;
  }

  void _setPhase(PresenceSessionPhase next, {required String code}) {
    if (_phase == next) return;
    final from = _phase;
    _phase = next;
    diagnostics.record(
      PresenceDiagEvent(
        code: code,
        at: DateTime.now(),
        role: 'writer',
        fromPhase: from.name,
        toPhase: next.name,
        attempt: _recovery.consecutiveFailures,
        heartbeatAgeSec: debugHeartbeatAgeSec,
      ),
    );
    if (kDebugMode) {
      debugPrint('PresenceWriter: phase ${from.name}→${next.name} ($code)');
    }
  }

  @Deprecated('Use PresenceWatch')
  static bool isPublicUserOnline(Map<String, dynamic> data, DateTime now) {
    return OnlineStatus.isOnline(data, now);
  }

  @Deprecated('Use PresenceWatch.watchCountryCounter')
  static Timestamp onlineQuerySince(DateTime now) {
    return OnlineStatus.querySince(now);
  }

  static String generateConnectionId({
    DateTime? now,
    int? randomBits,
  }) {
    final t = now ?? DateTime.now();
    final rnd = randomBits ?? Random.secure().nextInt(1 << 30);
    return 'c_${t.microsecondsSinceEpoch}_$rnd';
  }

  void _log(String context, [Object? error]) {
    if (kDebugMode) {
      debugPrint(
        error == null
            ? 'PresenceService: $context'
            : 'PresenceService: $context: $error',
      );
    }
  }

  /// Sanitized writer diagnostics (Profile/Release-safe — no UID/token/path).
  void _logWriterFailure(String context, [Object? error]) {
    final reason = error != null
        ? PresenceWriterRecovery.sanitizeError(error)
        : 'no_connection';
    diagnostics.record(
      PresenceDiagEvent(
        code: 'writer_$context',
        at: DateTime.now(),
        role: 'writer',
        fromPhase: _phase.name,
        toPhase: PresenceSessionPhase.recovering.name,
        errorCategory: reason,
        attempt: _recovery.consecutiveFailures,
        heartbeatAgeSec: debugHeartbeatAgeSec,
      ),
    );
    debugPrint(
      'PresenceWriter: $context reason=$reason '
      'phase=${_phase.name} started=$_started fg=$_foreground '
      'rtdb=$_rtdbConnected conn=$_connectionActive',
    );
  }

  Future<bool> _ensureAuthReady({bool forceRefresh = false}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    if (_uid != null && user.uid != _uid) {
      _logWriterFailure('auth_uid_mismatch');
      return false;
    }
    try {
      await user.getIdToken(forceRefresh);
      return true;
    } catch (e) {
      _logWriterFailure('auth_token', e);
      return false;
    }
  }

  void _listenAuth() {
    _authSub ??= FirebaseAuth.instance.idTokenChanges().listen((user) {
      if (user == null) {
        if (_started || _uid != null) {
          unawaited(stop());
        }
        return;
      }
      // Auth pronto mas writer ainda não iniciado → start (cold start / TF).
      if (!_started) {
        unawaited(start());
        return;
      }
      if (_uid != null && user.uid != _uid) {
        unawaited(_restartForUid(user.uid));
        return;
      }
      if (_foreground && !_connectionActive) {
        unawaited(_attemptWriterRecovery(trigger: 'auth_token'));
      }
    }, onError: (Object e) {
      _logWriterFailure('auth_stream', e);
      _setPhase(
        PresenceSessionMachine.afterTransientFailure(
          started: _started,
          foreground: _foreground,
        ),
        code: 'auth_stream_error',
      );
    });
  }

  Future<void> _restartForUid(String newUid) async {
    await stop();
    final user = FirebaseAuth.instance.currentUser;
    if (user != null && user.uid == newUid) {
      await start();
    }
  }

  void _cancelRecovery() {
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    _recoveryInFlight = false;
  }

  void _scheduleWriterRecovery({required String trigger}) {
    if (!_recovery.shouldRecover(
      started: _started,
      foreground: _foreground,
      connectionActive: _connectionActive,
      hasConnectionRef: _connectionRef != null,
    )) {
      _cancelRecovery();
      return;
    }

    _recoveryTimer?.cancel();
    final now = DateTime.now();
    final delay = _recovery.delayUntilNextAttempt(now);
    if (delay == Duration.zero) {
      unawaited(_attemptWriterRecovery(trigger: trigger));
      return;
    }

    _recoveryTimer = Timer(delay, () {
      _recoveryTimer = null;
      unawaited(_attemptWriterRecovery(trigger: '${trigger}_timer'));
    });
  }

  Future<void> _attemptWriterRecovery({required String trigger}) async {
    if (_recoveryInFlight) return;
    if (!_recovery.shouldRecover(
      started: _started,
      foreground: _foreground,
      connectionActive: _connectionActive,
      hasConnectionRef: _connectionRef != null,
    )) {
      _cancelRecovery();
      return;
    }

    _recoveryInFlight = true;
    final now = DateTime.now();
    if (!_recovery.canAttemptNow(now)) {
      _recoveryInFlight = false;
      _scheduleWriterRecovery(trigger: trigger);
      return;
    }

    _recovery.markAttempt(now);
    try {
      final forceToken = trigger.contains('permission') ||
          trigger.contains('auth') ||
          _recovery.consecutiveFailures >= 2;
      if (!await _ensureAuthReady(forceRefresh: forceToken)) {
        _recovery.markFailure(now);
        _logWriterFailure('recovery_$trigger');
        _setPhase(
          PresenceSessionMachine.afterTransientFailure(
            started: _started,
            foreground: _foreground,
          ),
          code: 'recovery_auth_wait',
        );
        _recoveryInFlight = false;
        _scheduleWriterRecovery(trigger: 'auth_wait');
        return;
      }

      _setPhase(PresenceSessionPhase.recovering, code: 'recovery_$trigger');
      await _goOnline(forceNew: !_connectionActive);

      if (_connectionActive && _connectionRef != null) {
        _recovery.markSuccess();
        _setPhase(PresenceSessionPhase.online, code: 'recovery_ok');
        _cancelRecovery();
      } else {
        _recovery.markFailure(now);
        _logWriterFailure('recovery_$trigger');
        _setPhase(PresenceSessionPhase.recovering, code: 'recovery_retry');
        _recoveryInFlight = false;
        _scheduleWriterRecovery(trigger: 'retry');
      }
    } catch (e) {
      _recovery.markFailure(now);
      _logWriterFailure('recovery_$trigger', e);
      _setPhase(PresenceSessionPhase.recovering, code: 'recovery_exception');
      _recoveryInFlight = false;
      _scheduleWriterRecovery(trigger: 'retry');
    }
  }

  Future<void> _clearLegacyPersistedConnectionId() async {
    if (_legacyPrefsCleared) return;
    _legacyPrefsCleared = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(_legacyPrefsConnectionKey)) {
        await prefs.remove(_legacyPrefsConnectionKey);
      }
    } catch (e) {
      _log('_clearLegacyPersistedConnectionId', e);
    }
  }

  Future<void> start() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await _clearLegacyPersistedConnectionId();

    if (_started && _uid != user.uid) {
      await stop();
    }

    if (_started && _uid == user.uid) {
      _cancelDeferredOffline();
      _foreground = true;
      _listenAuth();
      _listenConnected();
      if (!await _ensureAuthReady()) {
        _setPhase(PresenceSessionPhase.starting, code: 'restart_auth_wait');
        _scheduleWriterRecovery(trigger: 'restart_auth_wait');
        return;
      }
      if (!_connectionActive || _connectionRef == null) {
        _setPhase(PresenceSessionPhase.recovering, code: 'restart_no_conn');
        await _goOnline(forceNew: false);
        if (!_connectionActive) {
          _scheduleWriterRecovery(trigger: 'restart_go_online');
        } else {
          _setPhase(PresenceSessionPhase.online, code: 'restart_online');
        }
      } else {
        await _ensureOnDisconnect(refreshTimestamp: true);
        _startHeartbeat();
        _recovery.markSuccess();
        _cancelRecovery();
        _setPhase(PresenceSessionPhase.online, code: 'restart_keepalive');
      }
      return;
    }

    _started = true;
    _foreground = true;
    _setPhase(PresenceSessionPhase.starting, code: 'start');
    _hbGate.onNewSession();
    if (PresenceRtdbConfig.separateHeartbeatBackendReady) {
      _hbGate.onBackendReady();
    }
    _registerObserver();
    _listenAuth();
    _uid = user.uid;
    _listenConnected();
    if (!await _ensureAuthReady()) {
      _setPhase(PresenceSessionPhase.starting, code: 'start_auth_wait');
      _scheduleWriterRecovery(trigger: 'start_auth_wait');
      return;
    }
    await _goOnline(forceNew: false);
    if (_connectionActive) {
      _setPhase(PresenceSessionPhase.online, code: 'start_online');
    } else {
      _setPhase(PresenceSessionPhase.recovering, code: 'start_go_online');
      _scheduleWriterRecovery(trigger: 'start_go_online');
    }
  }

  /// Serializa goOnline/goOffline/clear para não criar connectionIds em paralelo.
  Future<T> _serialized<T>(Future<T> Function() fn) {
    final run = _opChain.then((_) => fn());
    _opChain = run.then((_) {}, onError: (_) {});
    return run;
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    if (!_connectionActive || _connectionRef == null) return;
    _heartbeatTimer = Timer.periodic(
      PresenceRtdbConfig.connectionHeartbeatInterval,
      (_) {
        if (!_started || !_foreground || !_connectionActive) return;
        unawaited(_writeHeartbeat());
      },
    );
    unawaited(_writeHeartbeat());
  }

  Future<void> _writeHeartbeat() async {
    final uid = _uid;
    if (uid == null) return;
    final ref = _connectionRef;

    if (PresenceRtdbConfig.separateHeartbeatBackendReady &&
        _hbGate.denied) {
      _hbGate.onBackendReady();
    }

    if (PresenceRtdbConfig.separateHeartbeatIsPrimary) {
      // Pós-deploy: keep-alive só no path sem trigger CF.
      try {
        await _rtdb.ref('presence/$uid/heartbeat').set(ServerValue.timestamp);
        if (ref != null) await ref.onDisconnect().remove();
        _heartbeatDiag = 'new';
      } catch (e) {
        if (_isPermissionDenied(e)) {
          _hbGate.markDenied();
          _heartbeatDiag = 'denied';
          if (_hbGate.consumeDeniedLogSlot()) {
            _log('heartbeat_separate denied');
          }
        } else {
          _log('_writeHeartbeat new-primary', e);
        }
        // Fallback de emergência: renovar connection (legado).
        await _refreshLegacyConnectionTimestamp(ref);
      }
      return;
    }

    // Pré-deploy (default): keep-alive canônico só no path legado.
    await _refreshLegacyConnectionTimestamp(ref);

    // No máximo 1 probe/sessão no path novo; após denied → só legado.
    if (!_hbGate.shouldAttemptNewPath) {
      if (_heartbeatDiag != 'denied') {
        _heartbeatDiag = 'legacy';
      }
      return;
    }

    _hbGate.markAttemptStarting();
    try {
      await _rtdb.ref('presence/$uid/heartbeat').set(ServerValue.timestamp);
      _heartbeatDiag = 'probed';
    } catch (e) {
      if (_isPermissionDenied(e)) {
        _hbGate.markDenied();
        _heartbeatDiag = 'denied';
        if (_hbGate.consumeDeniedLogSlot()) {
          _log('heartbeat_separate denied');
        }
      } else {
        // Já consumiu o único probe da sessão; keep-alive segue só legado.
        _heartbeatDiag = 'legacy';
        _log('_writeHeartbeat separate', e);
      }
    }
  }

  Future<void> _refreshLegacyConnectionTimestamp(DatabaseReference? ref) async {
    if (ref == null) return;
    try {
      await ref.onDisconnect().remove();
      await ref.set(ServerValue.timestamp);
      _lastHeartbeatAt = DateTime.now();
      if (_heartbeatDiag != 'probed' && _heartbeatDiag != 'denied') {
        _heartbeatDiag = 'legacy';
      }
    } catch (e) {
      _log('_refreshLegacyConnectionTimestamp', e);
      if (_isPermissionDenied(e)) {
        _connectionActive = false;
        _setPhase(PresenceSessionPhase.recovering, code: 'hb_permission');
        _scheduleWriterRecovery(trigger: 'hb_permission');
      }
    }
  }

  bool _isPermissionDenied(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('permission-denied') ||
        s.contains('permission_denied') ||
        s.contains('permission denied');
  }

  Future<void> _ensureOnDisconnect({bool refreshTimestamp = false}) async {
    final ref = _connectionRef;
    if (ref == null) return;
    try {
      await ref.onDisconnect().remove();
      if (refreshTimestamp) {
        await _writeHeartbeat();
      }
    } catch (e) {
      _log('_ensureOnDisconnect', e);
      // Conexão perdida no servidor → recria.
      _connectionActive = false;
      _connectionRef = null;
      _connectionId = null;
      if (_started && _foreground) {
        await _goOnline(forceNew: true);
      }
    }
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void _listenConnected() {
    _connectedSub ??= _rtdb.ref('.info/connected').onValue.listen((event) {
      final connected = event.snapshot.value == true;
      final was = _rtdbConnected;
      _rtdbConnected = connected;
      if (!_started) return;

      if (connected && !was) {
        unawaited(_onRtdbReconnected());
      }
    }, onError: (Object e) {
      _log('.info/connected', e);
    });
  }

  Future<void> _onRtdbReconnected() async {
    if (!_started || !_foreground) return;
    _log('rtdb reconnected');
    if (_connectionActive && _connectionRef != null && _connectionId != null) {
      await _ensureOnDisconnect(refreshTimestamp: true);
      return;
    }
    await _goOnline(forceNew: false);
    if (!_connectionActive) {
      _scheduleWriterRecovery(trigger: 'rtdb_reconnect');
    }
  }

  void _registerObserver() {
    if (_observerRegistered) return;
    WidgetsBinding.instance.addObserver(this);
    _observerRegistered = true;
  }

  void _unregisterObserver() {
    if (!_observerRegistered) return;
    WidgetsBinding.instance.removeObserver(this);
    _observerRegistered = false;
  }

  void _cancelDeferredOffline() {
    _deferredOfflineTimer?.cancel();
    _deferredOfflineTimer = null;
  }

  void _scheduleDeferredOffline({required String reason}) {
    _cancelDeferredOffline();
    _deferredOfflineTimer = Timer(deferredOfflineDelay, () {
      _deferredOfflineTimer = null;
      if (!_started) return;
      unawaited(_goOffline(reason: 'deferred_$reason'));
    });
  }

  Future<void> stop() async {
    _cancelDeferredOffline();
    _cancelRecovery();
    _recovery.reset();
    _stopHeartbeat();
    await _connectedSub?.cancel();
    _connectedSub = null;
    await _authSub?.cancel();
    _authSub = null;
    final uid = _uid;
    _uid = null;
    _foreground = false;
    _unregisterObserver();
    _started = false;
    await _clearRtdbConnection(writeFirestoreLastSeen: true);
    if (uid != null) {
      await _touchFirestoreLastSeen(uid: uid, force: true);
    }
    _setPhase(PresenceSessionPhase.offline, code: 'stop');
    try {
      PresenceDisplayHub.instance.onLogout();
    } catch (_) {}
  }

  /// [forceNew] só quando a conexão foi perdida / nunca existiu.
  Future<void> _goOnline({required bool forceNew}) {
    return _serialized(() async {
      if (!_started) return;
      final uid = _uid;
      if (uid == null) return;

      _foreground = true;

      final action = PresenceLifecycle.decideGoOnline(
        connectionActive: _connectionActive,
        hasConnectionRef: _connectionRef != null,
        forceNew: forceNew,
      );

      if (action == PresenceGoOnlineAction.keepExisting) {
        _log('online keep existing');
        await _ensureOnDisconnect(refreshTimestamp: true);
        _startHeartbeat();
        return;
      }

      _log('online create connection');

      if (_connectionRef != null) {
        await _clearRtdbConnection(writeFirestoreLastSeen: false);
      }

      if (!await _ensureAuthReady()) {
        _logWriterFailure('go_online_auth');
        _scheduleWriterRecovery(trigger: 'go_online_auth');
        return;
      }

      final connectionId = generateConnectionId();
      _connectionId = connectionId;
      final connRef = _rtdb.ref('presence/$uid/connections/$connectionId');

      try {
        await connRef.onDisconnect().remove();
        await connRef.set(ServerValue.timestamp);
        _connectionRef = connRef;
        _connectionActive = true;
        _lastHeartbeatAt = DateTime.now();
        _recovery.markSuccess();
        _cancelRecovery();
        _startHeartbeat();
        _setPhase(PresenceSessionPhase.online, code: 'go_online_ok');
        await _touchFirestoreLastSeen(uid: uid, force: false);
      } catch (e) {
        final denied = _isPermissionDenied(e);
        _logWriterFailure(denied ? 'go_online_permission' : 'go_online', e);
        _log('_goOnline', e);
        _stopHeartbeat();
        _connectionRef = null;
        _connectionActive = false;
        _connectionId = null;
        _setPhase(PresenceSessionPhase.recovering, code: 'go_online_fail');
        if (denied) {
          // Força renovação de token na próxima recovery.
          unawaited(_ensureAuthReady(forceRefresh: true));
        }
        _scheduleWriterRecovery(
          trigger: denied ? 'go_online_permission' : 'go_online_fail',
        );
      }
    });
  }

  Future<void> _goOffline({required String reason}) {
    return _serialized(() async {
      if (!_started && _uid == null) return;
      _log('offline ($reason)');
      _foreground = false;
      _stopHeartbeat();
      await _clearRtdbConnection(writeFirestoreLastSeen: true);
      _setPhase(PresenceSessionPhase.offline, code: 'go_offline_$reason');
    });
  }

  Future<void> _clearRtdbConnection({required bool writeFirestoreLastSeen}) async {
    final uid = _uid;
    final connRef = _connectionRef;
    final clearedId = _connectionId;
    _stopHeartbeat();
    _connectionRef = null;
    _connectionId = null;
    _connectionActive = false;

    try {
      if (connRef != null) {
        await connRef.onDisconnect().cancel();
        await connRef.remove();
      }
      // Best-effort: só se houve probe bem-sucedido nesta sessão.
      if (uid != null &&
          _hbGate.probedThisSession &&
          !_hbGate.denied &&
          _heartbeatDiag == 'probed') {
        try {
          await _rtdb.ref('presence/$uid/heartbeat').remove();
        } catch (e) {
          if (_isPermissionDenied(e)) {
            _hbGate.markDenied();
            _heartbeatDiag = 'denied';
          }
        }
      }
    } catch (e) {
      _log('_clearRtdbConnection id=$clearedId', e);
    }

    if (writeFirestoreLastSeen && uid != null) {
      await _touchFirestoreLastSeen(uid: uid, force: true);
    }
  }

  Future<void> _touchFirestoreLastSeen({
    required String uid,
    required bool force,
  }) async {
    final now = DateTime.now();
    if (!force && _lastFirestoreLastSeenWrite != null) {
      final elapsed = now.difference(_lastFirestoreLastSeenWrite!);
      if (elapsed < PresenceRtdbConfig.firestoreLastSeenMinInterval) {
        return;
      }
    }

    final ts = FieldValue.serverTimestamp();
    try {
      await _fs.collection('publicUsers').doc(uid).set({
        'uid': uid,
        'lastSeenAt': ts,
        'updatedAt': ts,
      }, SetOptions(merge: true));
      await _fs.collection('users').doc(uid).set({
        'lastSeenAt': ts,
        'updatedAt': ts,
      }, SetOptions(merge: true));
      _lastFirestoreLastSeenWrite = now;
    } catch (e) {
      _log('_touchFirestoreLastSeen', e);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        if (!_started) {
          // Sessão autenticada pode existir sem start (shell remount).
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            unawaited(start());
          }
          break;
        }
        _cancelDeferredOffline();
        _foreground = true;
        final action = PresenceLifecycle.decideResume(
          connectionActive: _connectionActive,
          hasConnectionRef: _connectionRef != null,
        );
        if (action == PresenceResumeAction.keepAlive) {
          unawaited(_ensureOnDisconnect(refreshTimestamp: true));
          _startHeartbeat();
          _recovery.markSuccess();
          _cancelRecovery();
          _setPhase(PresenceSessionPhase.online, code: 'resume_keepalive');
        } else {
          _setPhase(PresenceSessionPhase.recovering, code: 'resume_reestablish');
          unawaited(_goOnline(forceNew: false).then((_) {
            if (!_connectionActive) {
              _scheduleWriterRecovery(trigger: 'resume');
            } else {
              _setPhase(PresenceSessionPhase.online, code: 'resume_online');
            }
          }));
        }
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (_started) {
          _cancelRecovery();
          _scheduleDeferredOffline(reason: state.name);
        }
        break;
      case AppLifecycleState.detached:
        _cancelDeferredOffline();
        if (_started) {
          unawaited(_goOffline(reason: state.name));
        }
        break;
    }
  }
}
