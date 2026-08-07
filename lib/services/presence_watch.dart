import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'presence_rtdb_config.dart';
import 'presence_rtdb_logic.dart';
import 'presence_subscription_hub.dart';

/// Leitura de presença RTDB (sem Firestore, sem árvore mundial).
class PresenceWatch {
  PresenceWatch._();

  static FirebaseDatabase get _db => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: PresenceRtdbConfig.databaseURL,
      );

  /// Bolinha / UID único — via hub compartilhado.
  static Stream<bool> watchIsOnline(String uid) {
    return PresenceSubscriptionHub.instance.watchIsOnline(uid);
  }

  /// Contagem entre UIDs (dedupe). Usa hub; não recria por tick.
  static Stream<int> watchOnlineCount({
    required Iterable<String> uids,
    Set<String>? excludeUids,
    int? maxWatches,
  }) {
    final max = maxWatches ?? PresenceRtdbConfig.maxGroupPresenceWatches;
    final only = <String>{};
    for (final u in uids) {
      final t = u.trim();
      if (t.isEmpty) continue;
      if (excludeUids != null && excludeUids.contains(t)) continue;
      only.add(t);
      if (only.length >= max) break;
    }

    if (only.isEmpty) return Stream<int>.value(0);

    late StreamController<int> controller;
    final online = <String>{};
    final subs = <StreamSubscription<bool>>[];

    controller = StreamController<int>.broadcast(
      onListen: () {
        for (final uid in only) {
          subs.add(
            PresenceSubscriptionHub.instance.watchIsOnline(uid).listen(
              (isOn) {
                if (isOn) {
                  online.add(uid);
                } else {
                  online.remove(uid);
                }
                if (!controller.isClosed) controller.add(online.length);
              },
              onError: (_, __) {
                online.remove(uid);
                if (!controller.isClosed) controller.add(online.length);
              },
            ),
          );
        }
      },
      onCancel: () {
        for (final s in subs) {
          s.cancel();
        }
        subs.clear();
        online.clear();
      },
    );

    return controller.stream;
  }

  /// Contador Home por país — número escalar (CF), não árvore.
  /// Broadcast: a Home pode remontar StreamBuilders (ex.: rotação) sem
  /// `Bad state: Stream has already been listened to`.
  static Stream<int> watchCountryOnlineCount(String countryCode) {
    final cc = countryCode.trim().toLowerCase();
    if (cc.isEmpty) return Stream<int>.value(0);

    late StreamController<int> controller;
    StreamSubscription<DatabaseEvent>? sub;

    controller = StreamController<int>.broadcast(
      onListen: () {
        sub ??= _db.ref('presenceCounters/byCountry/$cc').onValue.listen(
          (event) {
            if (!controller.isClosed) {
              controller.add(PresenceRtdbLogic.parseCounter(event.snapshot.value));
            }
          },
          onError: (_, __) {
            if (!controller.isClosed) controller.add(0);
          },
        );
      },
      onCancel: () {
        sub?.cancel();
        sub = null;
      },
    );

    return controller.stream;
  }

  /// Contador mundial — número escalar. Nunca escuta `presenceIndex/byCountry`.
  static Stream<int> watchWorldOnlineCount({String? excludeCountryCode}) {
    final exclude = excludeCountryCode?.trim().toLowerCase() ?? '';
    if (exclude.isEmpty) {
      // Broadcast: Home pode remontar StreamBuilders sem
      // "Stream has already been listened to".
      late StreamController<int> controller;
      StreamSubscription<DatabaseEvent>? sub;
      controller = StreamController<int>.broadcast(
        onListen: () {
          sub ??= _db.ref('presenceCounters/world').onValue.listen(
            (event) {
              if (!controller.isClosed) {
                controller.add(
                  PresenceRtdbLogic.parseCounter(event.snapshot.value),
                );
              }
            },
            onError: (_, __) {
              if (!controller.isClosed) controller.add(0);
            },
          );
        },
        onCancel: () {
          sub?.cancel();
          sub = null;
        },
      );
      return controller.stream;
    }

    // Dois contadores pequenos: world − país (sem baixar árvore).
    // Só emite quando AMBOS chegaram — senão o mundo flasha o total bruto.
    late StreamController<int> controller;
    int? world;
    int? country;
    StreamSubscription<DatabaseEvent>? subW;
    StreamSubscription<DatabaseEvent>? subC;

    void emit() {
      final v = PresenceRtdbLogic.worldMinusCountry(
        world: world,
        country: country,
      );
      if (v == null || controller.isClosed) return;
      controller.add(v);
    }

    controller = StreamController<int>.broadcast(
      onListen: () {
        subW = _db.ref('presenceCounters/world').onValue.listen((e) {
          world = PresenceRtdbLogic.parseCounter(e.snapshot.value);
          emit();
        }, onError: (_, __) {
          world = 0;
          emit();
        });
        subC = _db.ref('presenceCounters/byCountry/$exclude').onValue.listen(
          (e) {
            country = PresenceRtdbLogic.parseCounter(e.snapshot.value);
            emit();
          },
          onError: (_, __) {
            country = 0;
            emit();
          },
        );
      },
      onCancel: () {
        subW?.cancel();
        subC?.cancel();
      },
    );

    return controller.stream;
  }
}
