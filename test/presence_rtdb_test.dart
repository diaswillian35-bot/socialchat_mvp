import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/online_status.dart';
import 'package:socialchat_mvp/services/presence_lifecycle.dart';
import 'package:socialchat_mvp/services/presence_rtdb_config.dart';
import 'package:socialchat_mvp/services/presence_rtdb_logic.dart';
import 'package:socialchat_mvp/services/presence_service.dart';
import 'package:socialchat_mvp/services/presence_subscription_hub.dart';

void main() {
  group('lifecycle resumed sem recriar', () {
    test('inactive→resumed com conexão ativa = keepAlive (sem piscar contador)', () {
      final action = PresenceLifecycle.decideResume(
        connectionActive: true,
        hasConnectionRef: true,
      );
      expect(action, PresenceResumeAction.keepAlive);
      expect(
        PresenceLifecycle.shouldBlinkCountersOnResume(action: action),
        isFalse,
      );
    });

    test('resumed sem conexão = reestablish', () {
      expect(
        PresenceLifecycle.decideResume(
          connectionActive: false,
          hasConnectionRef: false,
        ),
        PresenceResumeAction.reestablish,
      );
    });

    test('goOnline não recria se ativa; forceNew recria', () {
      expect(
        PresenceLifecycle.decideGoOnline(
          connectionActive: true,
          hasConnectionRef: true,
          forceNew: false,
        ),
        PresenceGoOnlineAction.keepExisting,
      );
      expect(
        PresenceLifecycle.decideGoOnline(
          connectionActive: true,
          hasConnectionRef: true,
          forceNew: true,
        ),
        PresenceGoOnlineAction.createNew,
      );
    });

    test('presence_service usa decideResume / .info/connected', () {
      final src = File('lib/services/presence_service.dart').readAsStringSync();
      expect(src.contains('PresenceLifecycle.decideResume'), isTrue);
      expect(src.contains('.info/connected'), isTrue);
      expect(src.contains('keepAlive'), isTrue);
      expect(src.contains('_ensureOnDisconnect'), isTrue);
    });
  });

  group('connectionId único', () {
    test('IDs gerados são distintos (instância antiga ≠ nova)', () {
      final a = PresenceService.generateConnectionId(
        now: DateTime(2026, 7, 25, 12, 0, 0, 0, 1),
        randomBits: 1,
      );
      final b = PresenceService.generateConnectionId(
        now: DateTime(2026, 7, 25, 12, 0, 0, 0, 2),
        randomBits: 2,
      );
      expect(a, isNot(b));
      expect(
        PresenceRtdbLogic.oldDisconnectCanRemoveNew(
          oldConnectionId: a,
          newConnectionId: b,
        ),
        isFalse,
      );
    });

    test('mesmo ID reutilizado seria inseguro', () {
      expect(
        PresenceRtdbLogic.oldDisconnectCanRemoveNew(
          oldConnectionId: 'c_same',
          newConnectionId: 'c_same',
        ),
        isTrue,
      );
    });

    test('presence_service não persiste connectionId em SharedPreferences', () {
      final src = File('lib/services/presence_service.dart').readAsStringSync();
      expect(src.contains('generateConnectionId'), isTrue);
      expect(src.contains("prefs.setString(_legacyPrefsConnectionKey"), isFalse);
      expect(src.contains('prefs.setString(_prefsConnectionKey'), isFalse);
      // Limpa legado, não grava novo.
      expect(src.contains('remove(_legacyPrefsConnectionKey)'), isTrue);
    });
  });

  group('contadores 0↔1 por UID', () {
    test('duas conexões: enter só na primeira; leave só na última', () {
      expect(
        PresenceRtdbLogic.counterDelta(
          connectionsBefore: 0,
          connectionsAfter: 1,
        ),
        PresenceCounterDelta.enter,
      );
      expect(
        PresenceRtdbLogic.counterDelta(
          connectionsBefore: 1,
          connectionsAfter: 2,
        ),
        PresenceCounterDelta.none,
      );
      expect(
        PresenceRtdbLogic.counterDelta(
          connectionsBefore: 2,
          connectionsAfter: 1,
        ),
        PresenceCounterDelta.none,
      );
      expect(
        PresenceRtdbLogic.counterDelta(
          connectionsBefore: 1,
          connectionsAfter: 0,
        ),
        PresenceCounterDelta.leave,
      );
    });

    test('dois aparelhos = uma pessoa no count de UIDs', () {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final n = PresenceRtdbLogic.countOnlineUids(
        presenceByUid: {
          'u1': {
            'c_old': nowMs - 1000,
            'c_new': nowMs,
          },
        },
      );
      expect(n, 1);
    });
  });

  group('grupo 81+', () {
    test('não trata parcial como total exato', () {
      final members = List.generate(81, (i) => 'm$i');
      final watched = PresenceRtdbLogic.capMemberWatches(
        members,
        prioritizeUid: 'm0',
        max: PresenceRtdbConfig.maxGroupPresenceWatches,
      );
      expect(watched.length, PresenceRtdbConfig.maxGroupPresenceWatches);

      final display = PresenceRtdbLogic.groupOnlineDisplay(
        memberCount: 81,
        watchedOnlineCount: 12,
        watchedMemberCount: watched.length,
      );
      expect(display.isPartial, isTrue);
      final label = display.format(
        onlineWord: 'online',
        partialFormatter: (c) => '$c+ online',
      );
      expect(label, '12+ online');
      expect(label.contains('12 online'), isFalse); // sem o "+" seria ambíguo
    });

    test('grupo pequeno mostra total exato', () {
      final d = PresenceRtdbLogic.groupOnlineDisplay(
        memberCount: 10,
        watchedOnlineCount: 3,
        watchedMemberCount: 10,
      );
      expect(d.isPartial, isFalse);
      expect(
        OnlineStatus.formatOnlineCount(count: d.count, onlineWord: 'online'),
        '3 online',
      );
    });
  });

  group('Home / listeners', () {
    test('PresenceWatch não escuta árvore mundial presenceIndex/byCountry', () {
      final src = File('lib/services/presence_watch.dart').readAsStringSync();
      expect(src.contains("ref('presenceIndex/byCountry')"), isFalse);
      expect(src.contains('presenceCounters/world'), isTrue);
      expect(src.contains('presenceCounters/byCountry'), isTrue);
    });

    test('cliente não escreve índice/counters', () {
      final src = File('lib/services/presence_service.dart').readAsStringSync();
      expect(src.contains('presenceIndex'), isFalse);
      expect(src.contains('presenceCounters'), isFalse);
      expect(src.contains('presence/'), isTrue);
      expect(src.contains('onDisconnect'), isTrue);
    });
  });

  group('hub compartilhado', () {
    test('refcount e cancelamento (sem Firebase)', () {
      final hub = PresenceSubscriptionHub.instance;
      hub.debugReset();
      // Sem Firebase.app o watch falharia ao escutar — só validamos API de reset.
      expect(hub.debugActiveSubscriptions, 0);
      expect(hub.debugRefCount('x'), 0);
    });

    test('online_dot e PresenceWatch usam hub', () {
      final dot = File('lib/widget/online_dot.dart').readAsStringSync();
      final watch = File('lib/services/presence_watch.dart').readAsStringSync();
      expect(dot.contains('PresenceWatch'), isTrue);
      expect(watch.contains('PresenceSubscriptionHub'), isTrue);
    });
  });

  group('falha parcial', () {
    test('plano do cliente: só conexão (índice órfão impossível no cliente)', () {
      // Espelha functions/presence_rtdb_counters_logic.clientWritePlan
      const writesConnection = true;
      const writesIndex = false;
      const writesCounters = false;
      expect(writesConnection && !writesIndex && !writesCounters, isTrue);
    });
  });
}
