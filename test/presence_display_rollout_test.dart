import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/presence_display_hub.dart';
import 'package:socialchat_mvp/services/presence_display_rollout.dart';
import 'package:socialchat_mvp/services/presence_rtdb_config.dart';

void main() {
  group('PresenceDisplayRollout.evaluateNewPath', () {
    final now = DateTime.utc(2026, 8, 22, 2, 0, 0);

    test('permission-denied → legacy', () {
      expect(
        PresenceDisplayRollout.evaluateNewPath(
          now: now,
          updatedAtMs: now.millisecondsSinceEpoch,
          counterSnapshotReceived: true,
          permissionDenied: true,
        ),
        PresenceDisplaySource.legacy,
      );
    });

    test('ausente (sem snapshot nem updatedAt) → unknown', () {
      expect(
        PresenceDisplayRollout.evaluateNewPath(
          now: now,
          updatedAtMs: null,
          counterSnapshotReceived: false,
        ),
        PresenceDisplaySource.unknown,
      );
    });

    test('backend novo ausente (snapshot sem updatedAt) → legacy', () {
      expect(
        PresenceDisplayRollout.evaluateNewPath(
          now: now,
          updatedAtMs: null,
          counterSnapshotReceived: true,
        ),
        PresenceDisplaySource.legacy,
      );
    });

    test('updatedAt fresco → new', () {
      final ms = now
          .subtract(const Duration(seconds: 10))
          .millisecondsSinceEpoch;
      expect(
        PresenceDisplayRollout.evaluateNewPath(
          now: now,
          updatedAtMs: ms,
          counterSnapshotReceived: true,
        ),
        PresenceDisplaySource.neu,
      );
    });

    test('updatedAt desatualizado → stale', () {
      final ms = now
          .subtract(PresenceDisplayRollout.maxDisplayAge +
              const Duration(seconds: 1))
          .millisecondsSinceEpoch;
      expect(
        PresenceDisplayRollout.evaluateNewPath(
          now: now,
          updatedAtMs: ms,
          counterSnapshotReceived: true,
        ),
        PresenceDisplaySource.stale,
      );
    });

    test('feedFor: stale/legacy → legacy; new → new', () {
      expect(
        PresenceDisplayRollout.feedFor(
          evaluation: PresenceDisplaySource.stale,
        ),
        PresenceDisplaySource.legacy,
      );
      expect(
        PresenceDisplayRollout.feedFor(
          evaluation: PresenceDisplaySource.legacy,
        ),
        PresenceDisplaySource.legacy,
      );
      expect(
        PresenceDisplayRollout.feedFor(
          evaluation: PresenceDisplaySource.neu,
        ),
        PresenceDisplaySource.neu,
      );
    });

    test('diagLabel sanitizado', () {
      expect(PresenceDisplayRollout.diagLabel(PresenceDisplaySource.neu), 'new');
      expect(
        PresenceDisplayRollout.diagLabel(PresenceDisplaySource.legacy),
        'legacy',
      );
      expect(
        PresenceDisplayRollout.diagLabel(PresenceDisplaySource.stale),
        'stale',
      );
    });

    test('parseUpdatedAtMs', () {
      expect(PresenceDisplayRollout.parseUpdatedAtMs(12345), 12345);
      expect(PresenceDisplayRollout.parseUpdatedAtMs(12345.0), 12345);
      expect(PresenceDisplayRollout.parseUpdatedAtMs('99'), 99);
      expect(PresenceDisplayRollout.parseUpdatedAtMs(null), isNull);
    });
  });

  group('rollout wiring (source files)', () {
    test('hub escuta novo e legado, sem ambos ao mesmo tempo no fluxo', () {
      final hub = File('lib/services/presence_display_hub.dart').readAsStringSync();
      expect(hub.contains('presenceDisplayCounters/world'), isTrue);
      expect(hub.contains('presenceCounters/world'), isTrue);
      expect(hub.contains('presenceCounters/byCountry/'), isTrue);
      expect(hub.contains('presenceDisplayCounters/countries/'), isTrue);
      expect(hub.contains('_attachLegacyOnly'), isTrue);
      expect(hub.contains('_attachNewOnly'), isTrue);
      expect(hub.contains('_probeNewPathOnce'), isTrue);
      expect(hub.contains('_cancelSubs'), isTrue);
      // Não emite zero em onError do path novo.
      expect(hub.contains("_worldController?.add(0)"), isFalse);
      expect(hub.contains("_countryController?.add(0)"), isFalse);
    });

    test('PresenceWatch delega ao hub (compat)', () {
      final watch = File('lib/services/presence_watch.dart').readAsStringSync();
      expect(watch.contains('PresenceDisplayHub'), isTrue);
      expect(watch.contains("ref('presenceIndex/byCountry')"), isFalse);
    });

    test('Home não usa initialData: 0 nos contadores', () {
      final home = File('lib/pages/home_page.dart').readAsStringSync();
      expect(home.contains('watchCountryOnlineCount'), isTrue);
      expect(home.contains('watchWorldOnlineCount'), isTrue);
      // Os StreamBuilders de live_now não devem forçar 0 pré-confirmação.
      final countryBlock = home.split('watchCountryOnlineCount').last.split('watchWorldOnlineCount').first;
      expect(countryBlock.contains('initialData: 0'), isFalse);
      final worldBlock = home.split('watchWorldOnlineCount').last.split('HomeDiscoverSection').first;
      expect(worldBlock.contains('initialData: 0'), isFalse);
    });

    test('heartbeat: legado primário; 1 probe/sessão via gate', () {
      expect(PresenceRtdbConfig.separateHeartbeatIsPrimary, isFalse);
      final src = File('lib/services/presence_service.dart').readAsStringSync();
      expect(src.contains('separateHeartbeatIsPrimary'), isTrue);
      expect(src.contains('_refreshLegacyConnectionTimestamp'), isTrue);
      expect(src.contains('presence/\$uid/heartbeat'), isTrue);
      expect(src.contains('SeparateHeartbeatGate'), isTrue);
      expect(src.contains('shouldAttemptNewPath'), isTrue);
    });

    test('keep-alive canônico é connections; heartbeat separado segue negado', () {
      // O timer de 45s renova presence/{uid}/connections/{id}.
      // presence/{uid}/heartbeat é só um probe (no máximo 1 por sessão) e
      // separateHeartbeatIsPrimary permanece false. As Rules publicadas e as
      // locais são as mesmas: sem o nó heartbeat e sem escrita de cliente em
      // presenceDisplayCounters. Abrir esses caminhos aqui seria uma escrita
      // nova que a presença atual não usa.
      final local = File('database.rules.json').readAsStringSync();
      final rules = jsonDecode(local) as Map<String, dynamic>;
      final root = rules['rules'] as Map<String, dynamic>;
      expect(root['.write'], false);
      expect(root.containsKey('presenceDisplayCounters'), isFalse);

      final presence = root['presence'] as Map<String, dynamic>;
      final uid = presence[r'$uid'] as Map<String, dynamic>;
      expect(uid.containsKey('heartbeat'), isFalse);
      expect(uid.containsKey('.write'), isFalse);
      final connection = ((uid['connections'] as Map)[r'$connectionId'] as Map);
      expect(connection['.write'], 'auth != null && auth.uid == \$uid');
      expect(connection['.validate'], 'newData.isNumber()');

      final counters = root['presenceCounters'] as Map<String, dynamic>;
      expect(counters['.write'], false);
      final online = root['presenceOnline'] as Map<String, dynamic>;
      final onlineUid = online[r'$uid'] as Map<String, dynamic>;
      expect(onlineUid['.write'], false);

      final head = Process.runSync('git', ['show', 'HEAD:database.rules.json']);
      expect(head.exitCode, 0);
      expect(head.stdout, local);
      expect(PresenceRtdbConfig.separateHeartbeatIsPrimary, isFalse);
    });
  });

  group('PresenceDisplayHub debug API', () {
    test('debugReset zera estado', () {
      final hub = PresenceDisplayHub.instance;
      hub.debugReset();
      expect(hub.debugActiveFeed, PresenceDisplaySource.unknown);
      expect(hub.debugHomeListening, isFalse);
      expect(hub.debugWorldConfirmed, isFalse);
      expect(hub.debugSourceLabel, 'unknown');
    });
  });
}
