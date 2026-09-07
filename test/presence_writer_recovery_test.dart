import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/presence_lifecycle.dart';
import 'package:socialchat_mvp/services/presence_writer_recovery.dart';

void main() {
  group('PresenceWriterRecovery policy', () {
    late PresenceWriterRecovery recovery;
    late DateTime t0;

    setUp(() {
      recovery = PresenceWriterRecovery();
      t0 = DateTime(2026, 8, 28, 12, 0, 0);
    });

    test('auth demora após abertura — started+fg sem conexão deve recuperar', () {
      expect(
        recovery.shouldRecover(
          started: true,
          foreground: true,
          connectionActive: false,
          hasConnectionRef: false,
        ),
        isTrue,
      );
      expect(recovery.canAttemptNow(t0), isTrue);
    });

    test('goOnline falha uma vez e recupera após backoff', () {
      recovery.markAttempt(t0);
      recovery.markFailure(t0);
      expect(recovery.consecutiveFailures, 1);
      expect(recovery.canAttemptNow(t0), isFalse);
      expect(
        recovery.canAttemptNow(t0.add(const Duration(seconds: 5))),
        isTrue,
      );
      recovery.markSuccess();
      expect(recovery.consecutiveFailures, 0);
      expect(recovery.canAttemptNow(t0.add(const Duration(seconds: 5))), isTrue);
    });

    test('retorno do background — recovery pausa fora do foreground', () {
      expect(
        recovery.shouldRecover(
          started: true,
          foreground: false,
          connectionActive: false,
          hasConnectionRef: false,
        ),
        isFalse,
      );
      expect(
        PresenceLifecycle.decideResume(
          connectionActive: false,
          hasConnectionRef: false,
        ),
        PresenceResumeAction.reestablish,
      );
    });

    test('RTDB cai e volta — reestablish quando sem conexão ativa', () {
      expect(
        PresenceLifecycle.decideResume(
          connectionActive: false,
          hasConnectionRef: true,
        ),
        PresenceResumeAction.reestablish,
      );
      expect(
        recovery.shouldRecover(
          started: true,
          foreground: true,
          connectionActive: false,
          hasConnectionRef: true,
        ),
        isTrue,
      );
    });

    test('serviço iniciado sem conexão real — shouldRecover true', () {
      expect(
        recovery.shouldRecover(
          started: true,
          foreground: true,
          connectionActive: false,
          hasConnectionRef: false,
        ),
        isTrue,
      );
      expect(
        recovery.shouldRecover(
          started: true,
          foreground: true,
          connectionActive: true,
          hasConnectionRef: false,
        ),
        isTrue,
      );
    });

    test('logout/login outro UID — política não recupera se não started', () {
      expect(
        recovery.shouldRecover(
          started: false,
          foreground: true,
          connectionActive: false,
          hasConnectionRef: false,
        ),
        isFalse,
      );
    });

    test('retry não duplica — keepExisting quando conexão ativa', () {
      expect(
        PresenceLifecycle.decideGoOnline(
          connectionActive: true,
          hasConnectionRef: true,
          forceNew: false,
        ),
        PresenceGoOnlineAction.keepExisting,
      );
      expect(
        recovery.shouldRecover(
          started: true,
          foreground: true,
          connectionActive: true,
          hasConnectionRef: true,
        ),
        isFalse,
      );
    });

    test('backoff exponencial limitado a 60s', () {
      expect(recovery.backoffAfterFailures(1), const Duration(seconds: 5));
      expect(recovery.backoffAfterFailures(2), const Duration(seconds: 10));
      expect(recovery.backoffAfterFailures(3), const Duration(seconds: 20));
      expect(recovery.backoffAfterFailures(4), const Duration(seconds: 40));
      expect(recovery.backoffAfterFailures(5), const Duration(seconds: 60));
      expect(recovery.backoffAfterFailures(99), const Duration(seconds: 60));
    });

    test('sanitizeError não vaza detalhes sensíveis', () {
      expect(
        PresenceWriterRecovery.sanitizeError(
          Exception('Permission denied at /presence/uid/connections'),
        ),
        'permission_denied',
      );
      expect(
        PresenceWriterRecovery.sanitizeError(
          Exception('network error offline'),
        ),
        'network',
      );
      expect(
        PresenceWriterRecovery.sanitizeError(Exception('something else')),
        'write_failed',
      );
    });
  });

  group('presence_service writer recovery wiring', () {
    final src = File('lib/services/presence_service.dart').readAsStringSync();

    test('auth token, recovery timer e logs sanitizados', () {
      expect(src.contains('idTokenChanges'), isTrue);
      expect(src.contains('PresenceWriterRecovery'), isTrue);
      expect(src.contains('_scheduleWriterRecovery'), isTrue);
      expect(src.contains('_logWriterFailure'), isTrue);
      expect(src.contains('_ensureAuthReady'), isTrue);
      expect(src.contains('getIdToken'), isTrue);
    });

    test('dispose/stop cancela timers e listeners', () {
      expect(src.contains('_cancelRecovery'), isTrue);
      expect(src.contains('_authSub?.cancel'), isTrue);
      expect(src.contains('_connectedSub?.cancel'), isTrue);
      expect(src.contains('_recoveryTimer?.cancel'), isTrue);
      expect(src.contains('_heartbeatTimer?.cancel'), isTrue);
    });

    test('MainShell dispose NÃO chama PresenceService.stop', () {
      final shell =
          File('lib/pages/main_shell_page.dart').readAsStringSync();
      final disposeIdx = shell.indexOf('void dispose()');
      expect(disposeIdx, greaterThan(0));
      final disposeBlock = shell.substring(
        disposeIdx,
        disposeIdx + 200,
      );
      expect(disposeBlock.contains('PresenceService.instance.stop'), isFalse);
    });

    test('hub erro de leitura NÃO emite offline', () {
      final hub =
          File('lib/services/presence_subscription_hub.dart').readAsStringSync();
      expect(hub.contains('PresenceReadStatus.unavailable'), isTrue);
      expect(hub.contains('reader_resubscribe'), isTrue);
      expect(hub.contains('_emitStable(entry, false)'), isFalse);
    });

    test('foreground pausa recovery; background cancela timer', () {
      expect(src.contains("trigger: 'resume'"), isTrue);
      expect(src.contains('_cancelRecovery'), isTrue);
      expect(src.contains('AppLifecycleState.paused'), isTrue);
    });

    test('UID ativo exposto para diagnóstico', () {
      expect(src.contains('debugActiveUid'), isTrue);
    });

    test('serialização evita connectionIds paralelos', () {
      expect(src.contains('_serialized'), isTrue);
      expect(src.contains('_recoveryInFlight'), isTrue);
    });
  });
}
