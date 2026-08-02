import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/app_notification_state.dart';
import 'package:socialchat_mvp/services/push_service.dart';

void main() {
  late AppNotificationState state;

  setUp(() {
    state = AppNotificationState.instance;
    state.debugReset();
    state.debugSetLifecycle(AppLifecycleState.resumed);
  });

  tearDown(() {
    state.debugReset();
  });

  group('AppNotificationState foreground/background', () {
    test('foreground não exibe push/local notification', () {
      state.debugSetLifecycle(AppLifecycleState.resumed);
      final data = {
        'type': 'chat',
        'conversationId': 'c1',
      };
      expect(state.shouldShowLocalNotification(data), isFalse);
      expect(state.shouldSuppressVisualNotification(data), isTrue);
      expect(state.shouldShowVisualNotification(data), isFalse);
    });

    test('foreground atualiza bolinha: skipUnread só na conversa aberta', () {
      state.debugSetLifecycle(AppLifecycleState.resumed);
      state.enterPrivateChat('c_open');

      expect(
        state.shouldSkipUnreadIncrement({
          'type': 'chat',
          'conversationId': 'c_open',
        }),
        isTrue,
        reason: 'conversa aberta não aumenta unread',
      );
      expect(
        state.shouldSkipUnreadIncrement({
          'type': 'chat',
          'conversationId': 'c_other',
        }),
        isFalse,
        reason: 'outra conversa ainda atualiza bolinha via Firestore',
      );
    });

    test('conversa aberta (DM) não aumenta unread', () {
      state.enterPrivateChat('dm_1');
      expect(
        state.shouldSkipUnreadIncrement({
          'type': 'private',
          'conversationId': 'dm_1',
        }),
        isTrue,
      );
    });

    test('grupo aberto não aumenta unread', () {
      state.enterGroupChat('g_1');
      expect(
        state.shouldSkipUnreadIncrement({
          'type': 'group',
          'groupId': 'g_1',
        }),
        isTrue,
      );
      expect(
        state.shouldSkipUnreadIncrement({
          'type': 'group',
          'groupId': 'g_other',
        }),
        isFalse,
      );
    });

    test('evento aberto suprime skip visual para comentário do mesmo evento',
        () {
      state.enterEvent('e_1');
      expect(
        state.isForActiveSurface(
          AppNotificationState.targetFromData({
            'type': 'event_comment',
            'eventId': 'e_1',
          }),
        ),
        isTrue,
      );
    });

    test('background: onMessage não cria local (SO exibe FCM)', () {
      state.debugSetLifecycle(AppLifecycleState.paused);
      expect(state.isBackground, isTrue);
      expect(
        state.shouldShowLocalNotification({
          'type': 'chat',
          'conversationId': 'c1',
        }),
        isFalse,
        reason: 'evita duplicata com o banner do sistema',
      );
    });

    test('app fechado/detached: mesma regra — sem local via onMessage', () {
      state.debugSetLifecycle(AppLifecycleState.detached);
      expect(
        state.shouldShowLocalNotification({'type': 'group', 'groupId': 'g'}),
        isFalse,
      );
    });

    test('uma mensagem: skipUnread é determinístico (uma vez por payload)', () {
      state.enterPrivateChat('c1');
      final data = {'type': 'chat', 'conversationId': 'c1'};
      expect(state.shouldSkipUnreadIncrement(data), isTrue);
      expect(state.shouldSkipUnreadIncrement(data), isTrue);
    });

    test('DM, grupo e evento usam a mesma regra funcional', () {
      for (final lifecycle in [
        AppLifecycleState.resumed,
        AppLifecycleState.paused,
      ]) {
        state.debugSetLifecycle(lifecycle);
        for (final data in [
          {'type': 'chat', 'conversationId': 'c'},
          {'type': 'group', 'groupId': 'g'},
          {'type': 'event_comment', 'eventId': 'e'},
          {'type': 'group_join_request', 'groupId': 'g'},
        ]) {
          expect(
            state.shouldShowLocalNotification(data),
            isFalse,
            reason: 'Android/iOS: sem local em onMessage ($lifecycle $data)',
          );
        }
      }
    });
  });

  group('PushService tap routing', () {
    test('tap abre a página correta por type', () {
      expect(
        PushService.resolveOpenRoute({'type': 'chat'}),
        'chat',
      );
      expect(
        PushService.resolveOpenRoute({'type': 'private'}),
        'chat',
      );
      expect(
        PushService.resolveOpenRoute({'type': 'group'}),
        'group',
      );
      expect(
        PushService.resolveOpenRoute({'type': 'group_join_approved'}),
        'group',
      );
      expect(
        PushService.resolveOpenRoute({'type': 'group_join_request'}),
        'group_info',
      );
      expect(
        PushService.resolveOpenRoute({'type': 'event_comment'}),
        'event',
      );
      expect(
        PushService.resolveOpenRoute({'type': 'event_reply'}),
        'event',
      );
    });
  });

  group('enter/leave surfaces', () {
    test('leave limpa só a superfície correspondente', () {
      state.enterPrivateChat('c1');
      state.enterEvent('e1');
      state.leavePrivateChat('c1');
      expect(state.activeConversationId, isNull);
      expect(state.activeEventId, 'e1');
      state.leaveEvent('e1');
      expect(state.activeEventId, isNull);
    });

    test('enterGroup limpa conversa privada ativa', () {
      state.enterPrivateChat('c1');
      state.enterGroupChat('g1');
      expect(state.activeConversationId, isNull);
      expect(state.activeGroupId, 'g1');
    });
  });
}
