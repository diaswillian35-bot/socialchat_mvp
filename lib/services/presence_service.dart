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
import 'presence_lifecycle.dart';
import 'presence_rtdb_config.dart';
import 'presence_heartbeat_gate.dart';

/// Presença via Realtime Database.
///
/// Cliente escreve **somente** `presence/{uid}/connections/{connectionId}`.
/// Contadores: Cloud Function atômica (Firestore) + mirror RTDB.
///
/// `resumed` curto **não** recria conexão se ela ainda está ativa.
class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  static const Duration onlineWindow = OnlineStatus.onlineWindow;
  static const Duration clockSkewTolerance = OnlineStatus.clockSkewTolerance;
  static const Duration queryLookbackExtra = OnlineStatus.queryLookbackExtra;
  static const Duration deferredOfflineDelay = Duration(seconds: 60);

  static const _legacyPrefsConnectionKey = 'remdy_presence_connection_id';

  final _fs = FirebaseFirestore.instance;

  FirebaseDatabase get _rtdb => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: PresenceRtdbConfig.databaseURL,
      );

  Timer? _deferredOfflineTimer;
  Timer? _heartbeatTimer;
  StreamSubscription<DatabaseEvent>? _connectedSub;
  Future<void> _opChain = Future<void>.value();
  bool _started = false;
  bool _foreground = true;
  bool _observerRegistered = false;
  bool _connectionActive = false;
  bool _legacyPrefsCleared = false;
  bool _rtdbConnected = false;
  final SeparateHeartbeatGate _hbGate = SeparateHeartbeatGate();
  /// Último modo sanitizado: `legacy` | `new` | `denied` | `dual` | `probed`.
  String _heartbeatDiag = 'unknown';

  String? _uid;
  String? _connectionId;
  DateTime? _lastFirestoreLastSeenWrite;

  DatabaseReference? _connectionRef;

  String? get debugConnectionId => _connectionId;
  bool get debugConnectionActive => _connectionActive;
  String get debugHeartbeatDiag => _heartbeatDiag;
  bool get debugSeparateHeartbeatDenied => _hbGate.denied;
  int get debugSeparateHeartbeatAttempts => _hbGate.attempts;
  bool get debugSeparateHeartbeatProbed => _hbGate.probedThisSession;

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
      _listenConnected();
      if (!_connectionActive || _connectionRef == null) {
        await _goOnline(forceNew: false);
      } else {
        await _ensureOnDisconnect(refreshTimestamp: true);
        _startHeartbeat();
      }
      return;
    }

    _started = true;
    _foreground = true;
    _hbGate.onNewSession();
    if (PresenceRtdbConfig.separateHeartbeatBackendReady) {
      _hbGate.onBackendReady();
    }
    _registerObserver();
    _uid = user.uid;
    _listenConnected();
    await _goOnline(forceNew: false);
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
      if (_heartbeatDiag != 'probed' && _heartbeatDiag != 'denied') {
        _heartbeatDiag = 'legacy';
      }
    } catch (e) {
      _log('_refreshLegacyConnectionTimestamp', e);
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
    _stopHeartbeat();
    await _connectedSub?.cancel();
    _connectedSub = null;
    final uid = _uid;
    _uid = null;
    _foreground = false;
    _unregisterObserver();
    _started = false;
    await _clearRtdbConnection(writeFirestoreLastSeen: true);
    if (uid != null) {
      await _touchFirestoreLastSeen(uid: uid, force: true);
    }
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

      final connectionId = generateConnectionId();
      _connectionId = connectionId;
      final connRef = _rtdb.ref('presence/$uid/connections/$connectionId');

      try {
        await connRef.onDisconnect().remove();
        await connRef.set(ServerValue.timestamp);
        _connectionRef = connRef;
        _connectionActive = true;
        _startHeartbeat();
        await _touchFirestoreLastSeen(uid: uid, force: false);
      } catch (e) {
        _log('_goOnline', e);
        _stopHeartbeat();
        _connectionRef = null;
        _connectionActive = false;
        _connectionId = null;
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
        if (!_started) break;
        _cancelDeferredOffline();
        _foreground = true;
        final action = PresenceLifecycle.decideResume(
          connectionActive: _connectionActive,
          hasConnectionRef: _connectionRef != null,
        );
        if (action == PresenceResumeAction.keepAlive) {
          // inactive→resumed, câmera, permissão: sem novo connectionId.
          unawaited(_ensureOnDisconnect(refreshTimestamp: true));
          _startHeartbeat();
        } else {
          unawaited(_goOnline(forceNew: false));
        }
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        if (_started) {
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
