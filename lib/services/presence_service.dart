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
  StreamSubscription<DatabaseEvent>? _connectedSub;
  bool _started = false;
  bool _foreground = true;
  bool _observerRegistered = false;
  bool _connectionActive = false;
  bool _legacyPrefsCleared = false;
  bool _rtdbConnected = false;

  String? _uid;
  String? _connectionId;
  DateTime? _lastFirestoreLastSeenWrite;

  DatabaseReference? _connectionRef;

  String? get debugConnectionId => _connectionId;
  bool get debugConnectionActive => _connectionActive;

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
        await _ensureOnDisconnect();
      }
      return;
    }

    _started = true;
    _foreground = true;
    _registerObserver();
    _uid = user.uid;
    _listenConnected();
    await _goOnline(forceNew: false);
  }

  void _listenConnected() {
    _connectedSub ??= _rtdb.ref('.info/connected').onValue.listen((event) {
      final connected = event.snapshot.value == true;
      final was = _rtdbConnected;
      _rtdbConnected = connected;
      if (!_started) return;

      if (connected && !was) {
        // Reconexão real de rede.
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
      // Mesmo connectionId: só re-registra onDisconnect + refresh timestamp.
      await _ensureOnDisconnect(refreshTimestamp: true);
      return;
    }
    await _goOnline(forceNew: false);
  }

  Future<void> _ensureOnDisconnect({bool refreshTimestamp = false}) async {
    final ref = _connectionRef;
    if (ref == null) return;
    try {
      await ref.onDisconnect().remove();
      if (refreshTimestamp) {
        await ref.set(ServerValue.timestamp);
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
  Future<void> _goOnline({required bool forceNew}) async {
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
      await _ensureOnDisconnect();
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
      await _touchFirestoreLastSeen(uid: uid, force: false);
    } catch (e) {
      _log('_goOnline', e);
      _connectionRef = null;
      _connectionActive = false;
      _connectionId = null;
    }
  }

  Future<void> _goOffline({required String reason}) async {
    if (!_started && _uid == null) return;
    _log('offline ($reason)');
    _foreground = false;
    await _clearRtdbConnection(writeFirestoreLastSeen: true);
  }

  Future<void> _clearRtdbConnection({required bool writeFirestoreLastSeen}) async {
    final uid = _uid;
    final connRef = _connectionRef;
    final clearedId = _connectionId;
    _connectionRef = null;
    _connectionId = null;
    _connectionActive = false;

    try {
      if (connRef != null) {
        await connRef.onDisconnect().cancel();
        await connRef.remove();
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
          unawaited(_ensureOnDisconnect());
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
