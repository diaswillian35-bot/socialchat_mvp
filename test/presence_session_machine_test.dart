import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/presence_diagnostics.dart';
import 'package:socialchat_mvp/services/presence_session_state.dart';
import 'package:socialchat_mvp/services/presence_rtdb_config.dart';
import 'package:socialchat_mvp/services/presence_writer_recovery.dart';

void main() {
  group('PresenceSessionMachine writer transitions', () {
    test('start: auth not ready → starting', () {
      expect(
        PresenceSessionMachine.afterStartRequested(
          authReady: false,
          connectionActive: false,
        ),
        PresenceSessionPhase.starting,
      );
    });

    test('start: auth ready + connection → online', () {
      expect(
        PresenceSessionMachine.afterStartRequested(
          authReady: true,
          connectionActive: true,
        ),
        PresenceSessionPhase.online,
      );
    });

    test('start: auth ready without connection → recovering', () {
      expect(
        PresenceSessionMachine.afterStartRequested(
          authReady: true,
          connectionActive: false,
        ),
        PresenceSessionPhase.recovering,
      );
    });

    test('goOnline fail → recovering; success → online', () {
      expect(
        PresenceSessionMachine.afterGoOnlineResult(connectionActive: false),
        PresenceSessionPhase.recovering,
      );
      expect(
        PresenceSessionMachine.afterGoOnlineResult(connectionActive: true),
        PresenceSessionPhase.online,
      );
    });

    test('goOffline / stop → offline', () {
      expect(PresenceSessionMachine.afterGoOffline(), PresenceSessionPhase.offline);
      expect(PresenceSessionMachine.afterStop(), PresenceSessionPhase.offline);
      expect(PresenceSessionMachine.afterAuthLost(), PresenceSessionPhase.offline);
    });

    test('transient failure: started+fg → recovering; not started → unavailable',
        () {
      expect(
        PresenceSessionMachine.afterTransientFailure(
          started: true,
          foreground: true,
        ),
        PresenceSessionPhase.recovering,
      );
      expect(
        PresenceSessionMachine.afterTransientFailure(
          started: false,
          foreground: true,
        ),
        PresenceSessionPhase.unavailable,
      );
      expect(
        PresenceSessionMachine.afterTransientFailure(
          started: true,
          foreground: false,
        ),
        PresenceSessionPhase.offline,
      );
    });
  });

  group('PresenceSessionMachine reader', () {
    test('listen error never becomes offline', () {
      expect(
        PresenceSessionMachine.readStatusOnListenError(
          lastConfirmed: PresenceReadStatus.online,
        ),
        PresenceReadStatus.unavailable,
      );
      expect(
        PresenceSessionMachine.readStatusOnListenError(lastConfirmed: null),
        PresenceReadStatus.unavailable,
      );
    });

    test('snapshot maps to confirmed online/offline', () {
      expect(
        PresenceSessionMachine.readStatusFromSnapshot(rawOnline: true),
        PresenceReadStatus.online,
      );
      expect(
        PresenceSessionMachine.readStatusFromSnapshot(rawOnline: false),
        PresenceReadStatus.offline,
      );
    });

    test('dot: unavailable → null (not gray/green)', () {
      expect(PresenceSessionMachine.dotIsOnline(PresenceReadStatus.online), true);
      expect(
        PresenceSessionMachine.dotIsOnline(PresenceReadStatus.offline),
        false,
      );
      expect(
        PresenceSessionMachine.dotIsOnline(PresenceReadStatus.unavailable),
        isNull,
      );
    });
  });

  group('PresenceDiagnostics', () {
    test('ring buffer respects max and sanitizes errors', () {
      final d = PresenceDiagnostics(maxEvents: 3);
      for (var i = 0; i < 5; i++) {
        d.record(
          PresenceDiagEvent(
            code: 'e$i',
            at: DateTime.now(),
            role: 'writer',
          ),
        );
      }
      expect(d.events.length, 3);
      expect(d.events.first.code, 'e2');
      expect(
        PresenceDiagnostics.sanitizeError('PERMISSION_DENIED: foo'),
        'permission_denied',
      );
      expect(
        PresenceDiagnostics.sanitizeError('network unreachable'),
        'network',
      );
    });

    test('events never store raw token-like strings in code', () {
      final d = PresenceDiagnostics();
      d.record(
        PresenceDiagEvent(
          code: 'writer_go_online',
          at: DateTime.now(),
          role: 'writer',
          errorCategory: PresenceDiagnostics.sanitizeError(
            'FirebaseAuthException: token eyJhbGciOi...',
          ),
        ),
      );
      final json = d.events.single.toJson();
      expect(json['err'], 'auth_token');
      expect(json.values.join(' ').contains('eyJ'), isFalse);
    });
  });

  group('Writer recovery + heartbeat cost invariants', () {
    test('started without connection recovers; not when offline', () {
      final r = PresenceWriterRecovery();
      expect(
        r.shouldRecover(
          started: true,
          foreground: true,
          connectionActive: false,
          hasConnectionRef: false,
        ),
        isTrue,
      );
      expect(
        r.shouldRecover(
          started: true,
          foreground: false,
          connectionActive: false,
          hasConnectionRef: false,
        ),
        isFalse,
      );
      expect(
        r.shouldRecover(
          started: true,
          foreground: true,
          connectionActive: true,
          hasConnectionRef: true,
        ),
        isFalse,
      );
    });

    test('heartbeat interval unchanged (45s)', () {
      expect(
        PresenceRtdbConfig.connectionHeartbeatInterval,
        const Duration(seconds: 45),
      );
      expect(
        PresenceRtdbConfig.connectionStaleAfter,
        const Duration(minutes: 3),
      );
      expect(
        PresenceRtdbConfig.uiOfflineHold,
        const Duration(seconds: 20),
      );
    });

    test('UID change implies stop then start (machine offline then starting)',
        () {
      expect(PresenceSessionMachine.afterStop(), PresenceSessionPhase.offline);
      expect(
        PresenceSessionMachine.afterStartRequested(
          authReady: false,
          connectionActive: false,
        ),
        PresenceSessionPhase.starting,
      );
    });
  });
}
