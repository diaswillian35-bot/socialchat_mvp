import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/online_status.dart';
import 'package:socialchat_mvp/services/online_status_ticker.dart';
import 'package:socialchat_mvp/services/presence_aggregate_policy.dart';

void main() {
  final now = DateTime(2026, 7, 25, 12, 0, 0);

  Map<String, dynamic> session({
    required String uid,
    required String sessionId,
    required bool isOnline,
    Duration ago = Duration.zero,
  }) {
    return {
      'uid': uid,
      'sessionId': sessionId,
      'isOnline': isOnline,
      'lastSeenAt': Timestamp.fromDate(now.subtract(ago)),
      'updatedAt': Timestamp.fromDate(now.subtract(ago)),
    };
  }

  Map<String, dynamic> user({
    required String uid,
    required bool isOnline,
    Duration ago = Duration.zero,
  }) {
    return {
      'uid': uid,
      'isOnline': isOnline,
      'lastSeenAt': Timestamp.fromDate(now.subtract(ago)),
    };
  }

  group('PresenceAggregatePolicy', () {
    test('erro/inconclusivo NÃO autoriza gravar agregado offline', () {
      expect(
        PresenceAggregatePolicy.shouldClientWriteAggregateOffline(
          OtherSessionsLookup.inconclusive,
        ),
        isFalse,
      );
      expect(
        PresenceAggregatePolicy.shouldClientWriteAggregateOffline(
          OtherSessionsLookup.noOtherOnline,
        ),
        isFalse,
      );
      expect(
        PresenceAggregatePolicy.shouldClientWriteAggregateOffline(
          OtherSessionsLookup.hasOtherOnline,
        ),
        isFalse,
      );
    });

    test('corrida A offline / B online: cliente não fecha agregado', () {
      // A consulta “nenhuma outra” e B grava online em paralelo:
      // política ainda proíbe write offline no cliente.
      final aWouldHaveSeen = OtherSessionsLookup.noOtherOnline;
      expect(
        PresenceAggregatePolicy.shouldClientWriteAggregateOffline(
          aWouldHaveSeen,
        ),
        isFalse,
      );

      // Servidor (espelho CF) vê B online → agregado permanece online.
      final sessions = [
        session(uid: 'u', sessionId: 'A', isOnline: false),
        session(uid: 'u', sessionId: 'B', isOnline: true),
      ];
      expect(
        PresenceAggregatePolicy.aggregateOnlineFromSessions(
          sessions: sessions,
          now: now,
        ),
        isTrue,
      );
    });

    test('sessão ativa além das primeiras 20: classify usa lista completa', () {
      final docs = <Map<String, dynamic>>[];
      for (var i = 0; i < 25; i++) {
        docs.add(session(
          uid: 'u',
          sessionId: 's$i',
          isOnline: false,
          ago: const Duration(minutes: 10),
        ));
      }
      // Sessão 24 (fora de um limit cego de 20) ainda online.
      docs[24] = session(uid: 'u', sessionId: 's24', isOnline: true);

      final lookup = PresenceAggregatePolicy.classifyOtherSessions(
        sessionDocs: docs,
        currentSessionId: 's0',
        now: now,
      );
      expect(lookup, OtherSessionsLookup.hasOtherOnline);

      expect(
        PresenceAggregatePolicy.countUniqueUidsOnline(
          sessions: docs,
          now: now,
          uidOf: (d) => d['uid'] as String,
        ),
        1,
      );
    });

    test('dois aparelhos mesmo UID = 1; duas contas = 2', () {
      expect(
        PresenceAggregatePolicy.countUniqueUidsOnline(
          sessions: [
            session(uid: 'willian', sessionId: 'phone', isOnline: true),
            session(uid: 'willian', sessionId: 'tablet', isOnline: true),
          ],
          now: now,
          uidOf: (d) => d['uid'] as String,
        ),
        1,
      );
      expect(
        PresenceAggregatePolicy.countUniqueUidsOnline(
          sessions: [
            session(uid: 'willian', sessionId: 'a', isOnline: true),
            session(uid: 'tester', sessionId: 'b', isOnline: true),
          ],
          now: now,
          uidOf: (d) => d['uid'] as String,
        ),
        2,
      );
    });
  });

  group('expiração sem snapshot', () {
    test('lastSeenAt expirado = bolinha/contador offline', () {
      final data = user(
        uid: 'x',
        isOnline: true,
        ago: const Duration(seconds: 200),
      );
      expect(OnlineStatus.isOnline(data, now), isFalse);
      expect(
        OnlineStatus.countUniqueOnline(
          docs: [data],
          now: now,
          idOf: (d) => d['uid'] as String,
        ),
        0,
      );
    });

    test('perda abrupta de internet: sem write offline, TTL decide', () {
      // Agregado ainda isOnline true (não houve write), mas lastSeen velho.
      final stale = user(
        uid: 'x',
        isOnline: true,
        ago: OnlineStatus.onlineWindow +
            OnlineStatus.clockSkewTolerance +
            const Duration(seconds: 1),
      );
      expect(OnlineStatus.isOnline(stale, now), isFalse);
    });

    test('ticker compartilhado emite e cancela sem listeners', () async {
      OnlineStatusTicker.instance.debugReset();
      final received = <DateTime>[];
      final sub = OnlineStatusTicker.instance.stream.listen(received.add);
      OnlineStatusTicker.instance.debugEmitNow(now);
      await Future<void>.delayed(Duration.zero);
      expect(received, isNotEmpty);
      await sub.cancel();
      // Sem listeners o timer interno deve parar (não explode).
      OnlineStatusTicker.instance.debugReset();
    });
  });

  group('grupo grande / privacidade', () {
    test('grupo grande: uma passagem, sem leitura por membro', () {
      final members = {for (var i = 0; i < 300; i++) 'u$i'};
      final docs = [
        for (var i = 0; i < 300; i++)
          user(
            uid: 'u$i',
            isOnline: i % 7 == 0,
            ago: i % 7 == 0
                ? Duration.zero
                : const Duration(seconds: 200),
          ),
        // Não-membros online ignorados
        user(uid: 'outsider', isOnline: true),
      ];
      final n = OnlineStatus.countUniqueOnline(
        docs: docs,
        now: now,
        idOf: (d) => d['uid'] as String,
        onlyUids: members,
        excludeUids: {'u0'}, // banido
      );
      // u0 banido; online quando i%7==0 → 0,7,14,...,294 = 43; minus u0 → 42
      expect(n, 42);
    });

    test('online_dot.dart usa PresenceWatch (RTDB), não Firestore', () {
      final src = File('lib/widget/online_dot.dart').readAsStringSync();
      expect(src.contains("collection('users')"), isFalse);
      expect(src.contains("collection('publicUsers')"), isFalse);
      expect(src.contains('PresenceWatch'), isTrue);
    });

    test('presence_service usa RTDB onDisconnect, sem sessions Firestore', () {
      final src = File('lib/services/presence_service.dart').readAsStringSync();
      expect(src.contains('.limit(20)'), isFalse);
      expect(src.contains('onDisconnect'), isTrue);
      // Heartbeat RTDB (Timer.periodic) é permitido; proibido é poll de sessions.
      expect(src.contains("collection('sessions')"), isFalse);
      expect(src.contains('_startHeartbeat'), isTrue);
      expect(src.contains('connectionHeartbeatInterval'), isTrue);
    });
  });
}
