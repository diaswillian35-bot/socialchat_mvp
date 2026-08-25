import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/presence_heartbeat_gate.dart';
import 'package:socialchat_mvp/services/presence_rtdb_config.dart';

void main() {
  group('SeparateHeartbeatGate', () {
    test('um probe por sessão; após denied não tenta de novo', () {
      final gate = SeparateHeartbeatGate();
      expect(gate.shouldAttemptNewPath, isTrue);

      gate.markAttemptStarting();
      expect(gate.attempts, 1);
      expect(gate.shouldAttemptNewPath, isFalse);

      gate.markDenied();
      expect(gate.denied, isTrue);

      // Vários ciclos de heartbeat após denied → zero writes novos.
      var wouldWrite = 0;
      for (var i = 0; i < 20; i++) {
        if (gate.shouldAttemptNewPath) {
          gate.markAttemptStarting();
          wouldWrite++;
        }
      }
      expect(wouldWrite, 0);
      expect(gate.attempts, 1);
    });

    test('log de denied só uma vez', () {
      final gate = SeparateHeartbeatGate();
      gate.markDenied();
      expect(gate.consumeDeniedLogSlot(), isTrue);
      expect(gate.consumeDeniedLogSlot(), isFalse);
      expect(gate.consumeDeniedLogSlot(), isFalse);
    });

    test('nova sessão reinicia probe', () {
      final gate = SeparateHeartbeatGate();
      gate.markAttemptStarting();
      gate.markDenied();
      expect(gate.shouldAttemptNewPath, isFalse);

      gate.onNewSession();
      expect(gate.denied, isFalse);
      expect(gate.probedThisSession, isFalse);
      expect(gate.attempts, 0);
      expect(gate.shouldAttemptNewPath, isTrue);
    });

    test('backend ready reabilita após denied', () {
      final gate = SeparateHeartbeatGate();
      gate.markAttemptStarting();
      gate.markDenied();
      gate.onBackendReady();
      expect(gate.shouldAttemptNewPath, isTrue);
    });

    test('race: markAttemptStarting síncrono bloqueia segundo probe', () {
      final gate = SeparateHeartbeatGate();
      expect(gate.shouldAttemptNewPath, isTrue);
      gate.markAttemptStarting();
      // Segundo ciclo concorrente não passa.
      expect(gate.shouldAttemptNewPath, isFalse);
      expect(gate.attempts, 1);
    });
  });

  group('PresenceService wiring', () {
    test('usa SeparateHeartbeatGate e não tenta HB novo a cada ciclo', () {
      final src = File('lib/services/presence_service.dart').readAsStringSync();
      expect(src.contains('SeparateHeartbeatGate'), isTrue);
      expect(src.contains('shouldAttemptNewPath'), isTrue);
      expect(src.contains('markAttemptStarting'), isTrue);
      expect(src.contains('consumeDeniedLogSlot'), isTrue);
      expect(PresenceRtdbConfig.separateHeartbeatIsPrimary, isFalse);
    });
  });
}
