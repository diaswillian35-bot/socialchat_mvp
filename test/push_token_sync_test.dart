import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:socialchat_mvp/services/push_token_sync.dart';

void main() {
  group('PushTokenSync', () {
    test('apsEnvironment production in release, development in profile', () {
      expect(
        PushTokenSync.apsEnvironment(isReleaseMode: true),
        'production',
      );
      expect(
        PushTokenSync.apsEnvironment(isReleaseMode: false),
        'development',
      );
      expect(
        PushTokenSync.apsEnvironment(isReleaseMode: true, isProfileMode: true),
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
        writerPlatform: 'ios',
        docs: [
          {'id': 'ios-new', 'platform': 'ios', 'token': 'ios-new'},
          {'id': 'ios-old', 'platform': 'ios', 'token': 'ios-old'},
          {'id': 'and-1', 'platform': 'android', 'token': 'and-1'},
        ],
      );
      expect(prune, ['ios-old']);
    });

    test('android writer does not delete ios tokens', () {
      final prune = PushTokenSync.iosTokenDocsToPrune(
        currentToken: 'and-new',
        writerPlatform: 'android',
        docs: [
          {'id': 'and-new', 'platform': 'android', 'token': 'and-new'},
          {'id': 'ios-live', 'platform': 'ios', 'token': 'ios-live'},
          {'id': 'ios-old', 'platform': 'ios', 'token': 'ios-old'},
        ],
      );
      expect(prune, isEmpty);
    });

    test('missing writer does not prune', () {
      final prune = PushTokenSync.iosTokenDocsToPrune(
        currentToken: 'ios-new',
        docs: [
          {'id': 'ios-old', 'platform': 'ios', 'token': 'ios-old'},
        ],
      );
      expect(prune, isEmpty);
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

    test('source contract: full permission request, no provisional/critical',
        () {
      final push = File('lib/services/push_service.dart').readAsStringSync();
      expect(push.contains('alert: true'), isTrue);
      expect(push.contains('badge: true'), isTrue);
      expect(push.contains('sound: true'), isTrue);
      expect(push.contains('provisional: false'), isTrue);
      expect(push.contains('criticalAlert: false'), isTrue);
      expect(
        push.contains('setForegroundNotificationPresentationOptions'),
        isTrue,
      );
      // Foreground: iOS system presentation off; in-app unread via Firestore.
      expect(
        push.contains(
            'enableSystem = !AppNotificationState.instance.isForeground'),
        isTrue,
      );
      expect(push.contains('writerPlatform: platform'), isTrue);
      // Settings open is manual API only — page must not auto-call on init.
      final page = File('lib/pages/notifications_page.dart').readAsStringSync();
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

  test('iOS rotates when APNs environment is missing or different', () {
    expect(
      PushTokenSync.shouldRotateFcmToken(
        storedEnvironment: 'production',
        currentEnvironment: 'development',
      ),
      isTrue,
    );
    expect(
      PushTokenSync.shouldRotateFcmToken(
        storedEnvironment: 'development',
        currentEnvironment: 'production',
      ),
      isTrue,
    );
    expect(
      PushTokenSync.shouldRotateFcmToken(
        storedEnvironment: null,
        currentEnvironment: 'development',
      ),
      isTrue,
    );
    expect(
      PushTokenSync.shouldRotateFcmToken(
        storedEnvironment: 'development',
        currentEnvironment: 'development',
      ),
      isFalse,
    );
  });

  test('iOS does not persist without an APNs token or after a mismatch', () {
    expect(
      PushTokenSync.canPersistIosFcmToken(
        apnsToken: '',
        storedEnvironment: 'development',
        currentEnvironment: 'development',
      ),
      isFalse,
    );
    expect(
      PushTokenSync.canPersistIosFcmToken(
        apnsToken: 'apns',
        storedEnvironment: 'production',
        currentEnvironment: 'development',
      ),
      isFalse,
    );
    expect(
      PushTokenSync.canPersistIosFcmToken(
        apnsToken: 'apns',
        storedEnvironment: 'development',
        currentEnvironment: 'development',
      ),
      isTrue,
    );
  });

  test('UID switch detaches the previous owner only', () {
    expect(
      PushTokenSync.shouldDetachPreviousUid(
        previousUid: 'account-a',
        currentUid: 'account-b',
      ),
      isTrue,
    );
    expect(
      PushTokenSync.shouldDetachPreviousUid(
        previousUid: 'account-a',
        currentUid: 'account-a',
      ),
      isFalse,
    );
    expect(
      PushTokenSync.shouldDetachPreviousUid(
        previousUid: '',
        currentUid: 'account-b',
      ),
      isFalse,
    );
  });

  test('cached FCM token is deleted only after APNs is ready', () {
    expect(
      PushTokenSync.shouldDeleteCachedFcmToken(
        storedEnvironment: null,
        currentEnvironment: 'development',
        apnsReady: false,
      ),
      isFalse,
    );
    expect(
      PushTokenSync.shouldDeleteCachedFcmToken(
        storedEnvironment: null,
        currentEnvironment: 'development',
        apnsReady: true,
      ),
      isTrue,
    );
    expect(
      PushTokenSync.shouldDeleteCachedFcmToken(
        storedEnvironment: 'development',
        currentEnvironment: 'development',
        apnsReady: true,
      ),
      isFalse,
    );
  });

  test('a new client build refreshes registration once', () {
    expect(
      PushTokenSync.shouldRefreshRegistrationForBuild(
        storedBuild: null,
        currentBuild: PushTokenSync.clientBuild,
      ),
      isTrue,
    );
    expect(
      PushTokenSync.shouldRefreshRegistrationForBuild(
        storedBuild: '35',
        currentBuild: '36',
      ),
      isTrue,
    );
    expect(
      PushTokenSync.shouldRefreshRegistrationForBuild(
        storedBuild: PushTokenSync.clientBuild,
        currentBuild: PushTokenSync.clientBuild,
      ),
      isFalse,
    );
    expect(PushTokenSync.clientBuild, '36');
  });

  test('iOS sync retries are bounded', () {
    expect(PushTokenSync.nextIosSyncDelay(0), const Duration(milliseconds: 500));
    expect(PushTokenSync.nextIosSyncDelay(6), const Duration(seconds: 30));
    expect(PushTokenSync.nextIosSyncDelay(7), isNull);
    expect(PushTokenSync.iosSyncRetryDelays.length, 7);
  });

  test('logout removes only this iOS environment', () {
    final remove = PushTokenSync.iosAssociationDocsToRemove(
      environment: 'development',
      docs: [
        {'id': 'ios-dev', 'platform': 'ios', 'apsEnvironment': 'development'},
        {'id': 'ios-prod', 'platform': 'ios', 'apsEnvironment': 'production'},
        {'id': 'android', 'platform': 'android', 'apsEnvironment': ''},
        {'id': 'ios-old', 'platform': 'ios', 'apsEnvironment': ''},
      ],
    );
    expect(remove, ['ios-dev', 'ios-old']);
  });

  test('sync log redacts token-like values and masks uids', () {
    const token = 'abcdefghijklmnopqrstuvwxyz0123456789TOKEN';
    final line = PushTokenSync.formatPushSyncLog(
      phase: 'fcm',
      fields: {'state': 'received', 'leak': token},
    );
    expect(line.contains(token), isFalse);
    expect(line.contains('leak=redacted'), isTrue);
    expect(line.contains('phase=fcm'), isTrue);
    expect(PushTokenSync.maskUid('DaBKgQfghbWTzx8BAzIV6XQHsgo1'), 'DaBKgQ…');
    expect(PushTokenSync.maskUid(''), '-');
  });

  test('logout and account deletion clear push tokens (source contract)', () {
    final home = File('lib/pages/home_page.dart').readAsStringSync();
    final shell = File('lib/pages/main_shell_page.dart').readAsStringSync();
    final delete =
        File('lib/pages/delete_account_page.dart').readAsStringSync();
    final push = File('lib/services/push_service.dart').readAsStringSync();
    expect(home.contains('PushService.clearForLogout'), isTrue);
    expect(shell.contains('PushService.clearForLogout'), isTrue);
    expect(delete.contains('PushService.clearForLogout'), isTrue);
    expect(push.contains('deleteToken()'), isTrue);
    expect(push.contains('getAPNSToken'), isTrue);
    expect(push.contains('_iosPersistGateOpen'), isTrue);
    expect(push.contains('shouldDetachPreviousUid'), isTrue);
    expect(push.contains("if (_platform() == 'ios')"), isTrue);
    expect(push.contains('iosTokenDocsToPrune'), isTrue);
    expect(push.contains('onTokenRefresh'), isTrue);
    expect(push.contains('_activeUid'), isTrue);
    expect(push.contains('requestIosSync'), isTrue);
    expect(push.contains("'state': 'unconfirmed'"), isTrue);
    expect(push.contains("'state': 'confirmed'"), isTrue);
    expect(push.contains('remdy/push_registration'), isTrue);
    expect(push.contains('clientBuild'), isTrue);
    expect(push.contains('build_refresh'), isTrue);
    expect(push.contains('registeredBuildPrefsKey'), isTrue);
  });
}
