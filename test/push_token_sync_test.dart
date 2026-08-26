import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/push_token_sync.dart';

void main() {
  group('PushTokenSync', () {
    test('apsEnvironment production in release', () {
      expect(
        PushTokenSync.apsEnvironment(isReleaseMode: true),
        'production',
      );
      expect(
        PushTokenSync.apsEnvironment(isReleaseMode: false),
        'development',
      );
    });

    test('tokenDocFields include bundle and environment', () {
      final fields = PushTokenSync.tokenDocFields(
        token: 'abc',
        platform: 'ios',
        bundleId: PushTokenSync.bundleIdIos,
        apsEnvironment: 'production',
      );
      expect(fields['bundleId'], 'com.remdy.app');
      expect(fields['apsEnvironment'], 'production');
      expect(fields['platform'], 'ios');
    });

    test('iosTokenDocsToPrune keeps current and android', () {
      final prune = PushTokenSync.iosTokenDocsToPrune(
        currentToken: 'ios-new',
        docs: [
          {'id': 'ios-new', 'platform': 'ios', 'token': 'ios-new'},
          {'id': 'ios-old', 'platform': 'ios', 'token': 'ios-old'},
          {'id': 'and-1', 'platform': 'android', 'token': 'and-1'},
        ],
      );
      expect(prune, ['ios-old']);
    });

    test('maskToken never returns full value', () {
      const raw = 'abcdefghijklmnopqrstuvwxyz0123456789';
      final masked = PushTokenSync.maskToken(raw);
      expect(masked.contains(raw), isFalse);
      expect(masked.startsWith('abcdef…'), isTrue);
    });

    test('invalid registration codes', () {
      expect(
        PushTokenSync.isInvalidRegistrationCode(
          'messaging/registration-token-not-registered',
        ),
        isTrue,
      );
      expect(
        PushTokenSync.isInvalidRegistrationCode(
          'messaging/third-party-auth-error',
        ),
        isFalse,
      );
    });
  });

  group('iOS notification authorization audit', () {
    test('detects badge-only presentation', () {
      expect(
        PushTokenSync.isBadgeOnlyPresentation(
          authorizationStatus: 'authorized',
          alert: 'disabled',
          badge: 'enabled',
          sound: 'disabled',
        ),
        isTrue,
      );
      expect(
        PushTokenSync.isBadgeOnlyPresentation(
          authorizationStatus: 'authorized',
          alert: 'enabled',
          badge: 'enabled',
          sound: 'enabled',
        ),
        isFalse,
      );
      expect(
        PushTokenSync.isBadgeOnlyPresentation(
          authorizationStatus: 'denied',
          alert: 'disabled',
          badge: 'enabled',
          sound: 'disabled',
        ),
        isFalse,
      );
    });

    test('settings guidance for badge-only and denied', () {
      expect(
        PushTokenSync.shouldOfferNotificationSettingsGuidance(
          authorizationStatus: 'authorized',
          alert: 'disabled',
          badge: 'enabled',
          sound: 'disabled',
        ),
        isTrue,
      );
      expect(
        PushTokenSync.shouldOfferNotificationSettingsGuidance(
          authorizationStatus: 'denied',
          alert: 'disabled',
          badge: 'disabled',
          sound: 'disabled',
        ),
        isTrue,
      );
      expect(
        PushTokenSync.shouldOfferNotificationSettingsGuidance(
          authorizationStatus: 'authorized',
          alert: 'enabled',
          badge: 'enabled',
          sound: 'enabled',
        ),
        isFalse,
      );
    });

    test('sanitized auth log never invents tokens', () {
      final line = PushTokenSync.formatIosAuthAuditLine(
        authorizationStatus: 'authorized',
        alert: 'disabled',
        badge: 'enabled',
        sound: 'disabled',
      );
      expect(line.contains('status=authorized'), isTrue);
      expect(line.contains('alert=off'), isTrue);
      expect(line.contains('badge=on'), isTrue);
      expect(line.contains('sound=off'), isTrue);
      expect(line.toLowerCase().contains('token'), isFalse);
    });

    test('source contract: full permission request, no provisional/critical', () {
      final push = File('lib/services/push_service.dart').readAsStringSync();
      expect(push.contains('alert: true'), isTrue);
      expect(push.contains('badge: true'), isTrue);
      expect(push.contains('sound: true'), isTrue);
      expect(push.contains('provisional: false'), isTrue);
      expect(push.contains('criticalAlert: false'), isTrue);
      expect(push.contains('provisional: true'), isFalse);
      expect(push.contains('criticalAlert: true'), isFalse);
      expect(
        push.contains('setForegroundNotificationPresentationOptions'),
        isTrue,
      );
      // Foreground presentation must enable alert/badge/sound (not silent).
      expect(
        RegExp(
          r'setForegroundNotificationPresentationOptions\(\s*'
          r'alert:\s*true,\s*badge:\s*true,\s*sound:\s*true',
          multiLine: true,
        ).hasMatch(push),
        isTrue,
      );
      // Settings open is manual API only — page must not auto-call on init.
      final page =
          File('lib/pages/notifications_page.dart').readAsStringSync();
      expect(page.contains('openSystemNotificationSettings'), isTrue);
      expect(page.contains('notifications_ios_alert_sound_hint'), isTrue);
      // Ensure initState does not open settings automatically.
      final initBlock = RegExp(
        r'void initState\(\)[\s\S]*?super\.initState\(\);[\s\S]*?\}',
      ).firstMatch(page)?.group(0);
      expect(initBlock, isNotNull);
      expect(initBlock!.contains('openSystemNotificationSettings'), isFalse);
    });
  });

  group('pushAllowedChatClientPreview', () {
    test('requires verified age', () {
      expect(
        pushAllowedChatClientPreview(
          ageVerificationStatus: 'pending',
          notifEnabled: null,
          notifChat: null,
        ),
        isFalse,
      );
      expect(
        pushAllowedChatClientPreview(
          ageVerificationStatus: 'verified',
          notifEnabled: null,
          notifChat: null,
        ),
        isTrue,
      );
    });

    test('respects notifEnabled / notifChat false', () {
      expect(
        pushAllowedChatClientPreview(
          ageVerificationStatus: 'verified',
          notifEnabled: false,
          notifChat: null,
        ),
        isFalse,
      );
      expect(
        pushAllowedChatClientPreview(
          ageVerificationStatus: 'verified',
          notifEnabled: null,
          notifChat: false,
        ),
        isFalse,
      );
    });
  });

  test('logout and account deletion clear push tokens (source contract)', () {
    final home = File('lib/pages/home_page.dart').readAsStringSync();
    final shell = File('lib/pages/main_shell_page.dart').readAsStringSync();
    final delete = File('lib/pages/delete_account_page.dart').readAsStringSync();
    final push = File('lib/services/push_service.dart').readAsStringSync();
    expect(home.contains('PushService.clearForLogout'), isTrue);
    expect(shell.contains('PushService.clearForLogout'), isTrue);
    expect(delete.contains('PushService.clearForLogout'), isTrue);
    expect(push.contains('deleteToken()'), isTrue);
    expect(push.contains('iosTokenDocsToPrune'), isTrue);
    expect(push.contains('onTokenRefresh'), isTrue);
    expect(push.contains('_activeUid'), isTrue);
  });
}
