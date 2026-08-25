import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

import 'presence_rtdb_config.dart';
import 'presence_rtdb_logic.dart';
import 'presence_stability.dart';

/// Hub de assinaturas RTDB com refcount + cache curto + histerese offline.
///
/// - Uma assinatura por UID compartilhada entre widgets
/// - Cancela após o último listener (com grace curto)
/// - Não cria assinatura por tick/rebuild
/// - Offline só após [PresenceStabilityGate.defaultOfflineHold] (anti-flicker)
class PresenceSubscriptionHub {
  PresenceSubscriptionHub._();
  static final PresenceSubscriptionHub instance = PresenceSubscriptionHub._();

  /// Grace antes de cancelar a assinatura RTDB após o último listener.
  static const Duration unsubscribeGrace = Duration(seconds: 2);

  final Map<String, _UidEntry> _entries = {};

  @visibleForTesting
  int get debugActiveSubscriptions =>
      _entries.values.where((e) => e.subscription != null).length;

  @visibleForTesting
  int debugRefCount(String uid) => _entries[uid.trim()]?.refCount ?? 0;

  FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: PresenceRtdbConfig.databaseURL,
      );

  /// Stream compartilhado: online se há ≥1 conexão (com hold offline).
  Stream<bool> watchIsOnline(String uid) {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return Stream<bool>.value(false);

    late StreamController<bool> controller;
    controller = StreamController<bool>.broadcast(
      onListen: () => _retain(trimmed, controller),
      onCancel: () => _release(trimmed, controller),
    );
    return controller.stream;
  }

  void _emitStable(_UidEntry entry, bool rawOnline) {
    final now = DateTime.now();
    final next = entry.gate.consider(rawOnline, now);
    entry.flushTimer?.cancel();
    entry.flushTimer = null;
    if (next != null) {
      entry.lastValue = next;
      entry.lastUpdated = now;
      for (final c in List<StreamController<bool>>.from(entry.consumers)) {
        if (!c.isClosed) c.add(next);
      }
    }
    final pending = entry.gate.pendingOfflineRemaining(now);
    if (pending != null && pending > Duration.zero) {
      entry.flushTimer = Timer(pending + const Duration(milliseconds: 50), () {
        final flushed = entry.gate.flush(DateTime.now());
        if (flushed == null) return;
        entry.lastValue = flushed;
        entry.lastUpdated = DateTime.now();
        for (final c in List<StreamController<bool>>.from(entry.consumers)) {
          if (!c.isClosed) c.add(flushed);
        }
      });
    }
  }

  void _retain(String uid, StreamController<bool> consumer) {
    final entry = _entries.putIfAbsent(uid, () => _UidEntry(uid));
    entry.graceTimer?.cancel();
    entry.graceTimer = null;
    entry.consumers.add(consumer);
    entry.refCount++;

    if (entry.subscription == null) {
      entry.subscription = _db.ref('presence/$uid/connections').onValue.listen(
        (event) {
          final online =
              PresenceRtdbLogic.isOnlineFromConnections(event.snapshot.value);
          _emitStable(entry, online);
        },
        onError: (Object e, StackTrace st) {
          if (kDebugMode) {
            debugPrint('PresenceSubscriptionHub($uid): $e');
          }
          // Treat error as offline raw — still respect hold if was online.
          _emitStable(entry, false);
        },
      );
    } else if (entry.lastValue != null && !consumer.isClosed) {
      consumer.add(entry.lastValue!);
    }
  }

  void _release(String uid, StreamController<bool> consumer) {
    final entry = _entries[uid];
    if (entry == null) return;
    entry.consumers.remove(consumer);
    entry.refCount = entry.consumers.length;
    if (entry.refCount > 0) return;

    entry.graceTimer?.cancel();
    entry.graceTimer = Timer(unsubscribeGrace, () {
      if (entry.refCount > 0) return;
      entry.flushTimer?.cancel();
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
      e.subscription?.cancel();
      for (final c in e.consumers) {
        if (!c.isClosed) c.close();
      }
    }
    _entries.clear();
  }
}

class _UidEntry {
  _UidEntry(this.uid);

  final String uid;
  final PresenceStabilityGate gate = PresenceStabilityGate();
  int refCount = 0;
  bool? lastValue;
  DateTime? lastUpdated;
  StreamSubscription<DatabaseEvent>? subscription;
  Timer? graceTimer;
  Timer? flushTimer;
  final Set<StreamController<bool>> consumers = {};
}
