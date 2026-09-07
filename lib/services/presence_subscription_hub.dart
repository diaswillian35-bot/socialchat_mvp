import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'presence_diagnostics.dart';
import 'presence_rtdb_config.dart';
import 'presence_rtdb_logic.dart';
import 'presence_session_state.dart';
import 'presence_stability.dart';

/// Hub de assinaturas RTDB com refcount + cache + histerese + recuperação.
///
/// - Erro de leitura → [PresenceReadStatus.unavailable] (NÃO offline)
/// - Reproduz último valor confirmado ao reter listener / soft-cache
/// - Renova token e recria assinatura após falhas
class PresenceSubscriptionHub {
  PresenceSubscriptionHub._();
  static final PresenceSubscriptionHub instance = PresenceSubscriptionHub._();

  static const Duration unsubscribeGrace = Duration(seconds: 2);
  static const Duration softCacheTtl = Duration(minutes: 2);
  static const Duration resubscribeMinInterval = Duration(seconds: 3);
  static const Duration resubscribeMaxInterval = Duration(seconds: 30);

  final Map<String, _UidEntry> _entries = {};
  final Map<String, _SoftCacheEntry> _softCache = {};
  final PresenceDiagnostics diagnostics = PresenceDiagnostics();

  @visibleForTesting
  int get debugActiveSubscriptions =>
      _entries.values.where((e) => e.subscription != null).length;

  @visibleForTesting
  int debugRefCount(String uid) => _entries[uid.trim()]?.refCount ?? 0;

  @visibleForTesting
  PresenceReadStatus? debugLastStatus(String uid) =>
      _entries[uid.trim()]?.lastStatus;

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: PresenceRtdbConfig.databaseURL,
      );

  /// Stream tri-estado compartilhado.
  Stream<PresenceReadStatus> watchStatus(String uid) {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) {
      return Stream<PresenceReadStatus>.value(PresenceReadStatus.offline);
    }

    late StreamController<PresenceReadStatus> controller;
    controller = StreamController<PresenceReadStatus>.broadcast(
      onListen: () => _retain(trimmed, controller),
      onCancel: () => _release(trimmed, controller),
    );
    return controller.stream;
  }

  /// Compat: emite só online/offline confirmados (filtra unavailable).
  Stream<bool> watchIsOnline(String uid) {
    return watchStatus(uid)
        .where((s) => s != PresenceReadStatus.unavailable)
        .map((s) => s == PresenceReadStatus.online);
  }

  void _emit(_UidEntry entry, PresenceReadStatus status) {
    if (entry.lastStatus == status) return;
    final from = entry.lastStatus?.name;
    entry.lastStatus = status;
    entry.lastUpdated = DateTime.now();
    if (status == PresenceReadStatus.online ||
        status == PresenceReadStatus.offline) {
      entry.lastConfirmed = status;
      _softCache[entry.uid] = _SoftCacheEntry(status, DateTime.now());
    }
    for (final c in List<StreamController<PresenceReadStatus>>.from(
      entry.consumers,
    )) {
      if (!c.isClosed) c.add(status);
    }
    diagnostics.record(
      PresenceDiagEvent(
        code: 'reader_emit',
        at: DateTime.now(),
        role: 'reader',
        fromPhase: from,
        toPhase: status.name,
      ),
    );
  }

  void _emitStable(_UidEntry entry, bool rawOnline) {
    final now = DateTime.now();
    final next = entry.gate.consider(rawOnline, now);
    entry.flushTimer?.cancel();
    entry.flushTimer = null;
    if (next != null) {
      _emit(
        entry,
        next ? PresenceReadStatus.online : PresenceReadStatus.offline,
      );
    }
    final pending = entry.gate.pendingOfflineRemaining(now);
    if (pending != null && pending > Duration.zero) {
      entry.flushTimer = Timer(pending + const Duration(milliseconds: 50), () {
        final flushed = entry.gate.flush(DateTime.now());
        if (flushed == null) return;
        _emit(
          entry,
          flushed ? PresenceReadStatus.online : PresenceReadStatus.offline,
        );
      });
    }
  }

  PresenceReadStatus? _replayStatus(_UidEntry entry) {
    if (entry.lastConfirmed != null) return entry.lastConfirmed;
    if (entry.lastStatus != null) return entry.lastStatus;
    final soft = _softCache[entry.uid];
    if (soft == null) return null;
    if (DateTime.now().difference(soft.at) > softCacheTtl) {
      _softCache.remove(entry.uid);
      return null;
    }
    return soft.status;
  }

  void _retain(String uid, StreamController<PresenceReadStatus> consumer) {
    final entry = _entries.putIfAbsent(uid, () => _UidEntry(uid));
    entry.graceTimer?.cancel();
    entry.graceTimer = null;
    entry.consumers.add(consumer);
    entry.refCount++;

    final replay = _replayStatus(entry);
    if (replay != null && !consumer.isClosed) {
      consumer.add(replay);
    } else if (!consumer.isClosed) {
      consumer.add(PresenceReadStatus.unavailable);
    }

    if (entry.subscription == null) {
      _attachSubscription(entry);
    }
  }

  void _attachSubscription(_UidEntry entry) {
    entry.subscription?.cancel();
    entry.subscription =
        _db.ref('presence/${entry.uid}/connections').onValue.listen(
      (event) {
        entry.consecutiveErrors = 0;
        final online =
            PresenceRtdbLogic.isOnlineFromConnections(event.snapshot.value);
        _emitStable(entry, online);
      },
      onError: (Object e, StackTrace st) {
        if (kDebugMode) {
          debugPrint('PresenceSubscriptionHub: read_error');
        }
        diagnostics.record(
          PresenceDiagEvent(
            code: 'reader_error',
            at: DateTime.now(),
            role: 'reader',
            fromPhase: entry.lastStatus?.name,
            toPhase: PresenceReadStatus.unavailable.name,
            errorCategory: PresenceDiagnostics.sanitizeError(e),
            attempt: entry.consecutiveErrors + 1,
          ),
        );
        _emit(entry, PresenceReadStatus.unavailable);
        entry.consecutiveErrors++;
        _scheduleResubscribe(entry);
      },
    );
  }

  void _scheduleResubscribe(_UidEntry entry) {
    if (entry.refCount <= 0) return;
    entry.resubscribeTimer?.cancel();
    final exp = entry.consecutiveErrors.clamp(1, 4);
    final ms = (resubscribeMinInterval.inMilliseconds * (1 << (exp - 1)))
        .clamp(
          resubscribeMinInterval.inMilliseconds,
          resubscribeMaxInterval.inMilliseconds,
        );
    entry.resubscribeTimer = Timer(Duration(milliseconds: ms), () {
      entry.resubscribeTimer = null;
      if (entry.refCount <= 0) return;
      unawaited(_resubscribeWithTokenRefresh(entry));
    });
  }

  Future<void> _resubscribeWithTokenRefresh(_UidEntry entry) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.getIdToken(true);
      }
    } catch (_) {}
    if (entry.refCount <= 0) return;
    diagnostics.record(
      PresenceDiagEvent(
        code: 'reader_resubscribe',
        at: DateTime.now(),
        role: 'reader',
        attempt: entry.consecutiveErrors,
      ),
    );
    _attachSubscription(entry);
  }

  void _release(String uid, StreamController<PresenceReadStatus> consumer) {
    final entry = _entries[uid];
    if (entry == null) return;
    entry.consumers.remove(consumer);
    entry.refCount = entry.consumers.length;
    if (entry.refCount > 0) return;

    if (entry.lastConfirmed != null) {
      _softCache[uid] = _SoftCacheEntry(entry.lastConfirmed!, DateTime.now());
    }

    entry.graceTimer?.cancel();
    entry.graceTimer = Timer(unsubscribeGrace, () {
      if (entry.refCount > 0) return;
      entry.flushTimer?.cancel();
      entry.resubscribeTimer?.cancel();
      entry.subscription?.cancel();
      entry.subscription = null;
      entry.gate.reset();
      _entries.remove(uid);
    });
  }

  @visibleForTesting
  void debugReset() {
    for (final e in _entries.values) {
      e.graceTimer?.cancel();
      e.flushTimer?.cancel();
      e.resubscribeTimer?.cancel();
      e.subscription?.cancel();
      for (final c in e.consumers) {
        if (!c.isClosed) c.close();
      }
    }
    _entries.clear();
    _softCache.clear();
    diagnostics.clear();
  }
}

class _UidEntry {
  _UidEntry(this.uid);

  final String uid;
  final PresenceStabilityGate gate = PresenceStabilityGate();
  int refCount = 0;
  PresenceReadStatus? lastStatus;
  PresenceReadStatus? lastConfirmed;
  DateTime? lastUpdated;
  int consecutiveErrors = 0;
  StreamSubscription<DatabaseEvent>? subscription;
  Timer? graceTimer;
  Timer? flushTimer;
  Timer? resubscribeTimer;
  final Set<StreamController<PresenceReadStatus>> consumers = {};
}

class _SoftCacheEntry {
  _SoftCacheEntry(this.status, this.at);
  final PresenceReadStatus status;
  final DateTime at;
}
