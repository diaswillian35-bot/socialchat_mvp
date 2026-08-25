import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/presence_rtdb_config.dart';
import 'package:socialchat_mvp/services/presence_stability.dart';

void main() {
  group('PresenceStabilityGate', () {
    test('online emits immediately', () {
      final gate = PresenceStabilityGate(
        offlineHold: const Duration(seconds: 20),
      );
      final t0 = DateTime(2026, 8, 24, 12, 0, 0);
      expect(gate.consider(true, t0), isTrue);
      expect(gate.consider(true, t0.add(const Duration(seconds: 1))), isNull);
    });

    test('offline is held during hysteresis window', () {
      final gate = PresenceStabilityGate(
        offlineHold: const Duration(seconds: 20),
      );
      final t0 = DateTime(2026, 8, 24, 12, 0, 0);
      expect(gate.consider(true, t0), isTrue);

      // Brief offline blip — keep showing online (null = no emit change).
      expect(
        gate.consider(false, t0.add(const Duration(seconds: 5))),
        isNull,
      );
      expect(gate.lastEmitted, isTrue);

      // Online returns before hold ends — still online, no flicker emit.
      expect(
        gate.consider(true, t0.add(const Duration(seconds: 10))),
        isNull,
      );
      expect(gate.lastEmitted, isTrue);
    });

    test('offline emits after hold elapses', () {
      final gate = PresenceStabilityGate(
        offlineHold: const Duration(seconds: 20),
      );
      final t0 = DateTime(2026, 8, 24, 12, 0, 0);
      expect(gate.consider(true, t0), isTrue);
      expect(
        gate.consider(false, t0.add(const Duration(seconds: 1))),
        isNull,
      );
      expect(
        gate.consider(false, t0.add(const Duration(seconds: 21))),
        isFalse,
      );
      expect(gate.lastEmitted, isFalse);
    });

    test('flush completes pending offline', () {
      final gate = PresenceStabilityGate(
        offlineHold: const Duration(seconds: 20),
      );
      final t0 = DateTime(2026, 8, 24, 12, 0, 0);
      gate.consider(true, t0);
      gate.consider(false, t0.add(const Duration(seconds: 1)));
      expect(gate.flush(t0.add(const Duration(seconds: 5))), isNull);
      expect(gate.flush(t0.add(const Duration(seconds: 21))), isFalse);
    });

    test('never-online starts offline without inventing online', () {
      final gate = PresenceStabilityGate();
      final t0 = DateTime(2026, 8, 24, 12, 0, 0);
      expect(gate.consider(false, t0), isFalse);
      expect(gate.lastEmitted, isFalse);
    });
  });

  group('presence economics (documented constants)', () {
    test('TTL is > 2× heartbeat (no tight race)', () {
      expect(
        PresenceRtdbConfig.connectionStaleAfter.inSeconds,
        greaterThan(
          PresenceRtdbConfig.connectionHeartbeatInterval.inSeconds * 2,
        ),
      );
    });

    test('offline hold is below deferred goOffline and stale TTL', () {
      expect(
        PresenceStabilityGate.defaultOfflineHold.inSeconds,
        lessThan(60), // PresenceService.deferredOfflineDelay
      );
      expect(
        PresenceStabilityGate.defaultOfflineHold.inSeconds,
        lessThan(PresenceRtdbConfig.connectionStaleAfter.inSeconds),
      );
    });
  });
}
