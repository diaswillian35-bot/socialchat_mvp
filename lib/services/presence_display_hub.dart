import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'presence_display_rollout.dart';
import 'presence_rtdb_config.dart';
import 'presence_rtdb_logic.dart';

/// Shared Home listeners for live counters with **rollout compatibility**.
///
/// Prefers `presenceDisplayCounters/*` when fresh; falls back to legacy
/// `presenceCounters/*` when the new path is absent, denied, or stale.
/// Never keeps listeners on both trees at once.
class PresenceDisplayHub with WidgetsBindingObserver {
  PresenceDisplayHub._();
  static final PresenceDisplayHub instance = PresenceDisplayHub._();

  bool _homeVisible = false;
  bool _foreground = true;
  bool _observer = false;
  String? _countryCode;

  StreamController<int>? _worldController;
  StreamController<int>? _countryController;

  StreamSubscription<DatabaseEvent>? _worldSub;
  StreamSubscription<DatabaseEvent>? _countrySub;
  StreamSubscription<DatabaseEvent>? _updatedAtSub;

  Timer? _newPathProbeTimer;

  int? _world;
  int? _country;
  int? _updatedAtMs;

  /// Feed ativo: new ou legacy (nunca ambos).
  PresenceDisplaySource _activeFeed = PresenceDisplaySource.unknown;

  /// Última avaliação do path novo (pode ser `stale` mesmo com feed legacy).
  PresenceDisplaySource _lastEvaluation = PresenceDisplaySource.unknown;

  bool _newPermissionDenied = false;
  bool _worldConfirmed = false;
  bool _countryConfirmed = false;

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: PresenceRtdbConfig.databaseURL,
      );

  /// Diagnóstico sanitizado (`new` | `legacy` | `stale` | `unknown`).
  String get debugSourceLabel =>
      PresenceDisplayRollout.diagLabel(_lastEvaluation == PresenceDisplaySource.stale
          ? PresenceDisplaySource.stale
          : _activeFeed == PresenceDisplaySource.unknown
              ? PresenceDisplaySource.unknown
              : _activeFeed == PresenceDisplaySource.neu
                  ? PresenceDisplaySource.neu
                  : PresenceDisplaySource.legacy);

  PresenceDisplaySource get debugActiveFeed => _activeFeed;
  PresenceDisplaySource get debugLastEvaluation => _lastEvaluation;
  int? get debugWorld => _world;
  int? get debugCountry => _country;
  bool get debugWorldConfirmed => _worldConfirmed;
  bool get debugHomeListening =>
      _worldSub != null || _countrySub != null || _updatedAtSub != null;

  /// Testes: zera estado sem Firebase.
  void debugReset() {
    _cancelSubs();
    _newPathProbeTimer?.cancel();
    _newPathProbeTimer = null;
    _homeVisible = false;
    _foreground = true;
    _countryCode = null;
    _world = null;
    _country = null;
    _updatedAtMs = null;
    _activeFeed = PresenceDisplaySource.unknown;
    _lastEvaluation = PresenceDisplaySource.unknown;
    _newPermissionDenied = false;
    _worldConfirmed = false;
    _countryConfirmed = false;
  }

  void ensureObserver() {
    if (_observer) return;
    WidgetsBinding.instance.addObserver(this);
    _observer = true;
  }

  void setHomeVisible(bool visible, {String? countryCode}) {
    ensureObserver();
    _homeVisible = visible;
    if (countryCode != null && countryCode.trim().isNotEmpty) {
      _countryCode = countryCode.trim().toLowerCase();
    }
    _syncSubscriptions();
  }

  void setCountryCode(String countryCode) {
    final next = countryCode.trim().toLowerCase();
    if (next.isEmpty || next == _countryCode) return;
    _countryCode = next;
    if (_isActive) {
      _restartCountrySub();
    }
  }

  void onLogout() {
    _homeVisible = false;
    _tearDown();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    _syncSubscriptions();
  }

  bool get _isActive {
    final loggedIn = FirebaseAuth.instance.currentUser != null;
    return loggedIn && _homeVisible && _foreground;
  }

  Stream<int> watchWorld({String? excludeCountryCode}) {
    _worldController ??= StreamController<int>.broadcast(
      onListen: () {
        if (_worldConfirmed &&
            _world != null &&
            _worldController != null &&
            !_worldController!.isClosed) {
          _worldController!.add(_world!);
        }
      },
    );
    final exclude = excludeCountryCode?.trim().toLowerCase() ?? '';
    if (exclude.isEmpty) {
      return _worldController!.stream;
    }
    setCountryCode(exclude);
    _countryController ??= StreamController<int>.broadcast(
      onListen: () {
        if (_countryConfirmed &&
            _country != null &&
            _countryController != null &&
            !_countryController!.isClosed) {
          _countryController!.add(_country!);
        }
      },
    );
    late StreamController<int> out;
    StreamSubscription<int>? sw;
    StreamSubscription<int>? sc;
    int? world;
    int? country;
    void emit() {
      final v = PresenceRtdbLogic.worldMinusCountry(
        world: world,
        country: country,
      );
      if (v == null || out.isClosed) return;
      out.add(v);
    }

    out = StreamController<int>.broadcast(
      onListen: () {
        sw = _worldController!.stream.listen((w) {
          world = w;
          emit();
        });
        sc = _countryController!.stream.listen((c) {
          country = c;
          emit();
        });
        if (_worldConfirmed) world = _world;
        if (_countryConfirmed) country = _country;
        emit();
      },
      onCancel: () {
        sw?.cancel();
        sc?.cancel();
      },
    );
    return out.stream;
  }

  Stream<int> watchCountry(String countryCode) {
    setCountryCode(countryCode);
    _countryController ??= StreamController<int>.broadcast(
      onListen: () {
        if (_countryConfirmed &&
            _country != null &&
            _countryController != null &&
            !_countryController!.isClosed) {
          _countryController!.add(_country!);
        }
      },
    );
    return _countryController!.stream;
  }

  void _syncSubscriptions() {
    if (!_isActive) {
      _cancelSubs();
      _newPathProbeTimer?.cancel();
      _newPathProbeTimer = null;
      return;
    }

    // Preferência: path novo; se já sabemos que é legado/stale/denied → legado.
    if (_activeFeed == PresenceDisplaySource.legacy ||
        _newPermissionDenied ||
        _lastEvaluation == PresenceDisplaySource.stale ||
        _lastEvaluation == PresenceDisplaySource.legacy) {
      _attachLegacyOnly();
      _scheduleNewPathProbe();
      return;
    }

    // unknown ou new → escuta só o novo (probe inicial).
    _attachNewOnly();
  }

  void _attachNewOnly() {
    _newPathProbeTimer?.cancel();
    _newPathProbeTimer = null;
    if (_activeFeed != PresenceDisplaySource.neu) {
      // Cancela legado imediatamente ao ativar o novo.
      _cancelSubs();
      _activeFeed = PresenceDisplaySource.neu;
      _logDiag();
    }
    _worldSub ??=
        _db.ref('presenceDisplayCounters/world').onValue.listen(
      (event) {
        _onNewCounterEvent(isWorld: true, event: event);
      },
      onError: (Object e) => _onNewPathError(e),
    );
    _updatedAtSub ??=
        _db.ref('presenceDisplayCounters/updatedAt').onValue.listen(
      (event) {
        _updatedAtMs =
            PresenceDisplayRollout.parseUpdatedAtMs(event.snapshot.value);
        _reevaluateNewPath(counterSnapshotReceived: _worldConfirmed);
      },
      onError: (Object e) => _onNewPathError(e),
    );
    _restartCountrySub();
  }

  void _attachLegacyOnly() {
    if (_activeFeed != PresenceDisplaySource.legacy) {
      // Cancela novo imediatamente ao ativar o legado.
      _cancelSubs();
      _activeFeed = PresenceDisplaySource.legacy;
      _logDiag();
    }

    _worldSub ??= _db.ref('presenceCounters/world').onValue.listen(
      (event) {
        _world = PresenceRtdbLogic.parseCounter(event.snapshot.value);
        _worldConfirmed = true;
        _worldController?.add(_world!);
      },
      onError: (Object e) {
        _diagError('legacy_world', e);
        // Sem confirmação → não força zero falso.
      },
    );
    _restartCountrySub();
  }

  void _restartCountrySub() {
    _countrySub?.cancel();
    _countrySub = null;
    final cc = _countryCode;
    if (cc == null || cc.isEmpty) return;
    if (!_isActive) return;

    if (_activeFeed == PresenceDisplaySource.legacy) {
      _countrySub =
          _db.ref('presenceCounters/byCountry/$cc').onValue.listen(
        (event) {
          _country = PresenceRtdbLogic.parseCounter(event.snapshot.value);
          _countryConfirmed = true;
          _countryController?.add(_country!);
        },
        onError: (Object e) {
          _diagError('legacy_country', e);
        },
      );
      return;
    }

    // new / probing
    _countrySub =
        _db.ref('presenceDisplayCounters/countries/$cc').onValue.listen(
      (event) {
        _onNewCounterEvent(isWorld: false, event: event);
      },
      onError: (Object e) => _onNewPathError(e),
    );
  }

  void _onNewCounterEvent({
    required bool isWorld,
    required DatabaseEvent event,
  }) {
    final value = PresenceRtdbLogic.parseCounter(event.snapshot.value);
    // Snapshot recebido (inclusive null→0) = backend respondeu.
    if (isWorld) {
      _world = value;
      _worldConfirmed = true;
    } else {
      _country = value;
      _countryConfirmed = true;
    }
    _reevaluateNewPath(counterSnapshotReceived: true);
  }

  void _reevaluateNewPath({required bool counterSnapshotReceived}) {
    final evaluation = PresenceDisplayRollout.evaluateNewPath(
      now: DateTime.now(),
      updatedAtMs: _updatedAtMs,
      counterSnapshotReceived: counterSnapshotReceived,
      permissionDenied: _newPermissionDenied,
    );
    _lastEvaluation = evaluation;
    final feed = PresenceDisplayRollout.feedFor(evaluation: evaluation);

    if (feed == PresenceDisplaySource.legacy ||
        feed == PresenceDisplaySource.stale) {
      // Não emitir zeros do path novo se vamos cair no legado.
      _attachLegacyOnly();
      _scheduleNewPathProbe();
      return;
    }

    if (feed == PresenceDisplaySource.neu) {
      _activeFeed = PresenceDisplaySource.neu;
      _logDiag();
      if (_worldConfirmed && _world != null) {
        _worldController?.add(_world!);
      }
      if (_countryConfirmed && _country != null) {
        _countryController?.add(_country!);
      }
    }
  }

  void _onNewPathError(Object e) {
    final denied = _isPermissionDenied(e);
    _diagError(denied ? 'new_denied' : 'new_error', e);
    if (denied) {
      _newPermissionDenied = true;
      _lastEvaluation = PresenceDisplaySource.legacy;
    } else {
      // Ausência / rede: ainda tenta legado (não zero falso).
      _lastEvaluation = PresenceDisplaySource.legacy;
    }
    _attachLegacyOnly();
    _scheduleNewPathProbe();
  }

  void _scheduleNewPathProbe() {
    _newPathProbeTimer?.cancel();
    if (!_isActive) return;
    if (_activeFeed != PresenceDisplaySource.legacy) return;
    if (_newPermissionDenied) {
      // Re-tenta denied com menos frequência (rules podem ter sido deployadas).
      _newPathProbeTimer = Timer(
        PresenceDisplayRollout.legacyToNewProbeInterval * 4,
        () => unawaited(_probeNewPathOnce()),
      );
      return;
    }
    _newPathProbeTimer = Timer(
      PresenceDisplayRollout.legacyToNewProbeInterval,
      () => unawaited(_probeNewPathOnce()),
    );
  }

  /// One-shot (sem listener duplicado) para legado → novo.
  Future<void> _probeNewPathOnce() async {
    _newPathProbeTimer = null;
    if (!_isActive || _activeFeed != PresenceDisplaySource.legacy) return;
    try {
      final snap = await _db.ref('presenceDisplayCounters/updatedAt').get();
      _newPermissionDenied = false;
      final ms = PresenceDisplayRollout.parseUpdatedAtMs(snap.value);
      final evaluation = PresenceDisplayRollout.evaluateNewPath(
        now: DateTime.now(),
        updatedAtMs: ms,
        counterSnapshotReceived: ms != null,
        permissionDenied: false,
      );
      _lastEvaluation = evaluation;
      if (PresenceDisplayRollout.feedFor(evaluation: evaluation) ==
          PresenceDisplaySource.neu) {
        _updatedAtMs = ms;
        // Troca: cancela legado imediatamente e ativa novo.
        _cancelSubs();
        _attachNewOnly();
        return;
      }
    } catch (e) {
      if (_isPermissionDenied(e)) {
        _newPermissionDenied = true;
        _lastEvaluation = PresenceDisplaySource.legacy;
        _diagError('probe_denied', e);
      } else {
        _diagError('probe_error', e);
      }
    }
    _scheduleNewPathProbe();
  }

  bool _isPermissionDenied(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('permission-denied') ||
        s.contains('permission_denied') ||
        s.contains('permission denied');
  }

  void _logDiag() {
    if (!kDebugMode && !kProfileMode) return;
    debugPrint(
      'PresenceDisplayHub source=${PresenceDisplayRollout.diagLabel(_lastEvaluation)} '
      'feed=${PresenceDisplayRollout.diagLabel(_activeFeed)}',
    );
  }

  void _diagError(String code, Object e) {
    if (!kDebugMode && !kProfileMode) return;
    // Sem UID/e-mail/path completo com dados pessoais.
    debugPrint('PresenceDisplayHub $code');
  }

  void _cancelSubs() {
    _worldSub?.cancel();
    _worldSub = null;
    _countrySub?.cancel();
    _countrySub = null;
    _updatedAtSub?.cancel();
    _updatedAtSub = null;
  }

  void _tearDown() {
    _cancelSubs();
    _newPathProbeTimer?.cancel();
    _newPathProbeTimer = null;
    _world = null;
    _country = null;
    _updatedAtMs = null;
    _activeFeed = PresenceDisplaySource.unknown;
    _lastEvaluation = PresenceDisplaySource.unknown;
    _worldConfirmed = false;
    _countryConfirmed = false;
    // Não emite zero no logout — UI some com a Home.
  }
}
