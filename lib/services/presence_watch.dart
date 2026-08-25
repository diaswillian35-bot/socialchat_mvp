import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import 'presence_rtdb_config.dart';
import 'presence_rtdb_logic.dart';
import 'presence_subscription_hub.dart';
import 'presence_display_hub.dart';

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

  /// Contador Home por país — display novo com fallback legado (hub).
  static Stream<int> watchCountryOnlineCount(String countryCode) {
    return PresenceDisplayHub.instance.watchCountry(countryCode);
  }

  /// Contador mundial — display novo com fallback legado. Sem árvore RTDB.
  static Stream<int> watchWorldOnlineCount({String? excludeCountryCode}) {
    return PresenceDisplayHub.instance.watchWorld(
      excludeCountryCode: excludeCountryCode,
    );
  }
}
