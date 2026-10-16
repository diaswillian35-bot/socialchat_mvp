import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../pages/main_shell_page.dart';
import '../pages/group_chat_page.dart';
import '../pages/group_info_page.dart';
import '../pages/chat_page.dart';
import '../pages/event_detail_page.dart';
import '../features/locais/data/place_repository.dart';
import '../features/locais/locais_feature_flag.dart';
import '../features/locais/ui/locais_detail_page.dart';
import 'age_access_service.dart';
import 'app_notification_state.dart';
import 'block_service.dart';
import 'block_visibility.dart';
import 'push_open_logic.dart';
import 'push_token_sync.dart';

/// Snapshot of iOS notification authorization (no tokens / PII).
class IosNotificationAuthSnapshot {
  const IosNotificationAuthSnapshot({
    required this.authorizationStatus,
    required this.alert,
    required this.badge,
    required this.sound,
  });

  final String authorizationStatus;
  final String alert;
  final String badge;
  final String sound;

  bool get isBadgeOnly => PushTokenSync.isBadgeOnlyPresentation(
        authorizationStatus: authorizationStatus,
        alert: alert,
        badge: badge,
        sound: sound,
      );

  bool get shouldOfferSettingsGuidance =>
      PushTokenSync.shouldOfferNotificationSettingsGuidance(
        authorizationStatus: authorizationStatus,
        alert: alert,
        badge: badge,
        sound: sound,
      );

  String get sanitizedLogLine => PushTokenSync.formatIosAuthAuditLine(
        authorizationStatus: authorizationStatus,
        alert: alert,
        badge: badge,
        sound: sound,
      );
}

enum _IosSyncOutcome { saved, permissionBlocked, notReady }

class PushService {
  static final navKey = GlobalKey<NavigatorState>();

  static const _androidChannelId = 'high_importance_channel';
  static const _androidChannelName = 'Mensagens Remdy';

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _started = false;
  static bool _localInitialized = false;
  static String? _activeUid;

  /// Closed until this iOS process has a real APNs token and, if needed,
  /// has discarded a cached FCM token from another environment.
  static bool _iosPersistGateOpen = false;
  static IosNotificationAuthSnapshot? lastIosAuthSnapshot;
  static bool _lifecycleHooked = false;
  static bool _pushChannelBound = false;
  static bool _iosSyncRunning = false;
  static String? _iosSyncPendingReason;
  static const _pushChannel = MethodChannel('remdy/push_registration');
  static const _fcmFingerprintKey = 'push_fcm_fingerprint';

  static void _logPush(String phase, [Map<String, String> fields = const {}]) {
    debugPrint(PushTokenSync.formatPushSyncLog(phase: phase, fields: fields));
  }

  static Future<void> init() async {
    AppNotificationState.instance.bind();
    _hookLifecycle();
    _bindPushRegistrationChannel();
    AppNotificationState.instance.onActiveSurfaceChanged = () {
      refreshIosForegroundPresentation();
    };
    await _initLocalNotifications();
    await _applyIosForegroundPresentation();
    try {
      final settings = await _requestNotificationPermission();
      _recordIosAuth(settings);
    } catch (_) {}
  }

  /// Foreground: suppress iOS system banner/sound/badge (in-app unread only).
  /// Background: OS handles full FCM notification payload.
  static Future<void> _applyIosForegroundPresentation() async {
    if (kIsWeb) return;
    try {
      if (!Platform.isIOS) return;
      final enableSystem = !AppNotificationState.instance.isForeground;
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: enableSystem,
        badge: enableSystem,
        sound: enableSystem,
      );
    } catch (_) {}
  }

  /// Re-aplica opções iOS quando ciclo de vida muda (sem heartbeat).
  static Future<void> refreshIosForegroundPresentation() async {
    await _applyIosForegroundPresentation();
  }

  static void _hookLifecycle() {
    if (_lifecycleHooked) return;
    _lifecycleHooked = true;
    AppNotificationState.instance.onLifecycleChanged = (state) {
      refreshIosForegroundPresentation();
      if (state == AppLifecycleState.resumed) {
        final uid = (_activeUid ?? '').trim();
        if (uid.isNotEmpty) {
          requestIosSync(uid, reason: 'resume');
        }
      }
    };
  }

  static void _bindPushRegistrationChannel() {
    if (_pushChannelBound) return;
    _pushChannelBound = true;
    _pushChannel.setMethodCallHandler((call) async {
      if (call.method != 'apns') return;
      final args = call.arguments;
      final received = args is Map && args['received'] == true;
      final errorCode = args is Map ? args['errorCode'] : null;
      if (errorCode is int) {
        _logPush('error', {'source': 'apns', 'code': '$errorCode'});
      }
      _logPush('apns', {'state': received ? 'callback' : 'callback_empty'});
      final uid = (_activeUid ?? '').trim();
      if (uid.isNotEmpty) {
        await requestIosSync(uid, reason: 'apns_callback');
      }
    });
  }

  /// Never provisional / critical / silent — always alert+badge+sound.
  static Future<NotificationSettings> _requestNotificationPermission() {
    return FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      criticalAlert: false,
      announcement: false,
      carPlay: false,
    );
  }

  static IosNotificationAuthSnapshot _snapshotFromSettings(
    NotificationSettings settings,
  ) {
    return IosNotificationAuthSnapshot(
      authorizationStatus: settings.authorizationStatus.name,
      alert: settings.alert.name,
      badge: settings.badge.name,
      sound: settings.sound.name,
    );
  }

  static void _recordIosAuth(NotificationSettings settings) {
    final snap = _snapshotFromSettings(settings);
    lastIosAuthSnapshot = snap;
    if (kDebugMode) {
      debugPrint(snap.sanitizedLogLine);
    }
  }

  /// Read current iOS authorization (sanitized). Safe on Android (null).
  static Future<IosNotificationAuthSnapshot?> readIosNotificationAuth() async {
    if (kIsWeb) return null;
    try {
      if (!Platform.isIOS) return null;
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      final snap = _snapshotFromSettings(settings);
      lastIosAuthSnapshot = snap;
      if (kDebugMode) {
        debugPrint(snap.sanitizedLogLine);
      }
      return snap;
    } catch (_) {
      return null;
    }
  }

  /// Opens system Settings only when the user taps a UI action — never auto.
  static Future<bool> openSystemNotificationSettings() async {
    try {
      final uri = Uri.parse('app-settings:');
      if (await canLaunchUrl(uri)) {
        return launchUrl(uri);
      }
    } catch (_) {}
    return false;
  }

  static Future<void> _initLocalNotifications() async {
    if (_localInitialized) return;

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload == null || payload.isEmpty) return;
        _handleOpenFromPayload(payload);
      },
    );

    if (!kIsWeb && Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _androidChannelId,
              _androidChannelName,
              description: 'Notificações de chat, grupos e eventos',
              importance: Importance.high,
            ),
          );
    }

    _localInitialized = true;
  }

  /// Chame 1x após login (com uid válido).
  static Future<void> start(String uid) async {
    final trimmedUid = uid.trim();
    if (trimmedUid.isEmpty) return;
    _activeUid = trimmedUid;

    AppNotificationState.instance.bind();
    await _initLocalNotifications();
    await _applyIosForegroundPresentation();

    if (!_started) {
      _started = true;

      // Foreground: system may present alert/badge/sound; local banner still gated.
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _offerRemoteOpen(message, PushOpenSource.background);
      });

      // Bind once. iOS persistence goes through the same sync as cold start
      // so a refresh that arrives before APNs is not dropped.
      FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        final currentUid = (_activeUid ?? '').trim();
        if (currentUid.isEmpty) return;
        _logPush('fcm', {
          'state': token.trim().isEmpty ? 'empty' : 'refreshed',
        });
        if (_platform() == 'ios') {
          await requestIosSync(currentUid, reason: 'onTokenRefresh');
          return;
        }
        final trimmed = token.trim();
        if (trimmed.isEmpty) return;
        await _saveToken(currentUid, trimmed);
      });

      try {
        final initial = await FirebaseMessaging.instance.getInitialMessage();
        if (initial != null) {
          _offerRemoteOpen(initial, PushOpenSource.coldStart);
        }
      } catch (e) {
        _logPush('open', {
          'state': 'initial_error',
          'code': e.runtimeType.toString(),
        });
      }
    }

    await enableAndSyncToken(trimmedUid);
  }

  static Future<bool> enableAndSyncToken(String uid) async {
    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
    } catch (_) {}

    NotificationSettings settings;
    try {
      settings = await _requestNotificationPermission();
      _recordIosAuth(settings);
      await _applyIosForegroundPresentation();
    } catch (_) {
      return false;
    }

    // Accept authorized only for "ok" UX; still sync token if provisional
    // was previously granted by the OS (we never request provisional).
    final authorized =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

    if (_platform() == 'ios') {
      final saved = await requestIosSync(uid, reason: 'login');
      return authorized && saved;
    }

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.trim().isNotEmpty) {
        await _saveToken(uid, token.trim());
      }
    } catch (_) {}

    return authorized;
  }

  /// Cold start, login, resume, APNs callback, and token refresh share one
  /// loop. A new reason coalesces instead of stacking loops.
  static Future<bool> requestIosSync(
    String uid, {
    required String reason,
  }) async {
    if (_platform() != 'ios') return false;
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return false;
    if (_iosSyncRunning) {
      _iosSyncPendingReason = reason;
      return false;
    }
    _iosSyncRunning = true;
    var saved = false;
    try {
      saved = await _runIosSyncLoop(trimmed, reason: reason);
    } finally {
      _iosSyncRunning = false;
      final pending = _iosSyncPendingReason;
      _iosSyncPendingReason = null;
      if (pending != null && (_activeUid ?? '').trim() == trimmed && !saved) {
        saved = await requestIosSync(trimmed, reason: pending);
      }
    }
    return saved;
  }

  static Future<bool> _runIosSyncLoop(
    String uid, {
    required String reason,
  }) async {
    _logPush('retry', {'reason': reason, 'state': 'start'});
    var failed = 0;
    while (true) {
      if ((_activeUid ?? '').trim() != uid) {
        _logPush('retry', {'reason': reason, 'state': 'uid_changed'});
        return false;
      }
      final outcome = await _attemptIosSync(uid);
      if (outcome == _IosSyncOutcome.saved) return true;
      if (outcome == _IosSyncOutcome.permissionBlocked) {
        _logPush('retry', {'reason': reason, 'state': 'permission_stop'});
        return false;
      }
      final delay = PushTokenSync.nextIosSyncDelay(failed);
      if (delay == null) {
        _logPush('retry', {'reason': reason, 'state': 'exhausted'});
        return false;
      }
      failed += 1;
      _logPush('retry', {
        'reason': reason,
        'state': 'wait',
        'attempt': '$failed',
      });
      await Future<void>.delayed(delay);
    }
  }

  /// One pass. Does not delete the cached FCM token until APNs is present.
  static Future<_IosSyncOutcome> _attemptIosSync(String uid) async {
    NotificationSettings? settings;
    try {
      settings = await FirebaseMessaging.instance.getNotificationSettings();
      _recordIosAuth(settings);
      _logPush('permission', {
        'status': settings.authorizationStatus.name,
        'alert': settings.alert.name,
        'badge': settings.badge.name,
        'sound': settings.sound.name,
      });
    } catch (e) {
      _logPush(
          'error', {'source': 'permission', 'code': e.runtimeType.toString()});
    }

    final status = settings?.authorizationStatus;
    if (status == AuthorizationStatus.denied) {
      return _IosSyncOutcome.permissionBlocked;
    }

    final prefs = await SharedPreferences.getInstance();
    final currentEnv = PushTokenSync.apsEnvironment(
      isReleaseMode: kReleaseMode,
      isProfileMode: kProfileMode,
    );
    final storedEnv = prefs.getString(PushTokenSync.apsEnvironmentPrefsKey);
    final storedBuild = prefs.getString(PushTokenSync.registeredBuildPrefsKey);
    final previousUid = prefs.getString(PushTokenSync.pushOwnerUidPrefsKey);
    _logPush('owner', {
      'previous': PushTokenSync.maskUid(previousUid),
      'current': PushTokenSync.maskUid(uid),
    });

    if (PushTokenSync.shouldDetachPreviousUid(
      previousUid: previousUid,
      currentUid: uid,
    )) {
      await _removeIosAssociation(previousUid!,
          environment: storedEnv ?? currentEnv);
    }

    final apns = await _readApnsToken();
    final apnsReady = (apns ?? '').trim().isNotEmpty;
    _logPush('apns', {'state': apnsReady ? 'received' : 'empty'});
    if (!apnsReady) return _IosSyncOutcome.notReady;

    final refreshBuild = PushTokenSync.shouldRefreshRegistrationForBuild(
      storedBuild: storedBuild,
      currentBuild: PushTokenSync.clientBuild,
    );
    final rotateEnv = PushTokenSync.shouldDeleteCachedFcmToken(
      storedEnvironment: storedEnv,
      currentEnvironment: currentEnv,
      apnsReady: true,
    );
    if (refreshBuild || rotateEnv) {
      try {
        await FirebaseMessaging.instance.deleteToken();
        _logPush('deleteToken', {
          'reason': refreshBuild ? 'build_refresh' : 'environment_mismatch',
          'stored': (storedEnv ?? '').isEmpty ? 'missing' : storedEnv!,
          'current': currentEnv,
        });
      } catch (e) {
        _logPush('error', {
          'source': 'deleteToken',
          'code': e.runtimeType.toString(),
        });
      }
    }

    if (!PushTokenSync.canPersistIosFcmToken(
      apnsToken: apns,
      storedEnvironment: currentEnv,
      currentEnvironment: currentEnv,
    )) {
      return _IosSyncOutcome.notReady;
    }

    _iosPersistGateOpen = true;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      final trimmed = (token ?? '').trim();
      if (trimmed.isEmpty) {
        _logPush('fcm', {'state': 'empty'});
        return _IosSyncOutcome.notReady;
      }
      final fingerprint = sha256.convert(trimmed.codeUnits).toString();
      final previousFingerprint = prefs.getString(_fcmFingerprintKey);
      _logPush('fcm', {
        'state': 'received',
        'renewed': previousFingerprint == null
            ? 'unknown'
            : (previousFingerprint == fingerprint ? 'false' : 'true'),
      });
      final confirmed = await _saveToken(uid, trimmed);
      if (!confirmed) return _IosSyncOutcome.notReady;
      await prefs.setString(_fcmFingerprintKey, fingerprint);
      await prefs.setString(
        PushTokenSync.registeredBuildPrefsKey,
        PushTokenSync.clientBuild,
      );
      await _rememberIosPushOwner(uid, environment: currentEnv);
      return _IosSyncOutcome.saved;
    } catch (e) {
      _logPush('error', {'source': 'fcm', 'code': e.runtimeType.toString()});
      return _IosSyncOutcome.notReady;
    }
  }

  static Future<String?> _readApnsToken() async {
    try {
      final token = await FirebaseMessaging.instance.getAPNSToken();
      if ((token ?? '').trim().isNotEmpty) return token;
    } catch (e) {
      _logPush('error',
          {'source': 'getAPNSToken', 'code': e.runtimeType.toString()});
    }
    return null;
  }

  static Future<void> _rememberIosPushOwner(
    String uid, {
    String? environment,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PushTokenSync.pushOwnerUidPrefsKey, uid);
    final env = (environment ??
            PushTokenSync.apsEnvironment(
              isReleaseMode: kReleaseMode,
              isProfileMode: kProfileMode,
            ))
        .trim();
    if (env.isNotEmpty) {
      await prefs.setString(PushTokenSync.apsEnvironmentPrefsKey, env);
    }
  }

  /// Removes only this device's iOS registration for [uid].
  static Future<void> _removeIosAssociation(
    String uid, {
    required String environment,
  }) async {
    final trimmed = uid.trim();
    if (trimmed.isEmpty) return;
    try {
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(trimmed)
          .collection('fcmTokens');
      final snap = await col.get();
      final remove = PushTokenSync.iosAssociationDocsToRemove(
        environment: environment,
        docs: snap.docs.map(
          (d) => <String, String?>{
            'id': d.id,
            'platform': (d.data()['platform'] ?? '').toString(),
            'apsEnvironment': (d.data()['apsEnvironment'] ?? '').toString(),
          },
        ),
      );
      for (final id in remove) {
        await col.doc(id).delete();
      }
      final left = await col.get();
      final userRef =
          FirebaseFirestore.instance.collection('users').doc(trimmed);
      final userSnap = await userRef.get();
      final legacy = (userSnap.data()?['fcmToken'] ?? '').toString().trim();
      final legacyRemoved = legacy.isNotEmpty && remove.contains(legacy);
      if (left.docs.isEmpty) {
        await userRef.set(
          {
            'fcmUpdatedAt': FieldValue.serverTimestamp(),
            'hasPush': false,
            'fcmToken': FieldValue.delete(),
          },
          SetOptions(merge: true),
        );
      } else if (legacyRemoved) {
        await userRef.set(
          {
            'fcmUpdatedAt': FieldValue.serverTimestamp(),
            'fcmToken': FieldValue.delete(),
          },
          SetOptions(merge: true),
        );
      }
      _logPush('persist', {
        'state': 'detached',
        'uid': PushTokenSync.maskUid(trimmed),
        'removed': '${remove.length}',
      });
    } catch (e) {
      _logPush('error', {
        'source': 'detach',
        'code': e.runtimeType.toString(),
      });
    }
  }

  static Future<void> disableAndClearToken(String uid) async {
    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
    } catch (_) {}

    try {
      await FirebaseMessaging.instance.deleteToken();
      _logPush('deleteToken', {'reason': 'logout'});
    } catch (e) {
      _logPush('error', {
        'source': 'deleteToken',
        'code': e.runtimeType.toString(),
      });
    }

    try {
      if (_platform() == 'ios') {
        final env = PushTokenSync.apsEnvironment(
          isReleaseMode: kReleaseMode,
          isProfileMode: kProfileMode,
        );
        await _removeIosAssociation(uid, environment: env);
      } else {
        final col = FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('fcmTokens');
        final snap = await col.get();
        for (final d in snap.docs) {
          final platform =
              (d.data()['platform'] ?? '').toString().toLowerCase();
          if (platform == 'ios') continue;
          await d.reference.delete();
        }
        final left = await col.get();
        if (left.docs.isEmpty) {
          await FirebaseFirestore.instance.collection('users').doc(uid).set(
            {
              'fcmUpdatedAt': FieldValue.serverTimestamp(),
              'hasPush': false,
              'fcmToken': FieldValue.delete(),
            },
            SetOptions(merge: true),
          );
        }
      }
    } catch (e) {
      _logPush('error', {'source': 'logout', 'code': e.runtimeType.toString()});
    }

    if ((_activeUid ?? '') == uid) {
      _activeUid = null;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final owner = prefs.getString(PushTokenSync.pushOwnerUidPrefsKey);
      if (owner == uid) {
        await prefs.remove(PushTokenSync.pushOwnerUidPrefsKey);
        await prefs.remove(_fcmFingerprintKey);
      }
    } catch (_) {}
  }

  /// Clears Firestore + device token for the active uid (call on logout).
  static Future<void> clearForLogout(String? uid) async {
    final trimmed = (uid ?? _activeUid ?? '').trim();
    if (trimmed.isEmpty) {
      _activeUid = null;
      return;
    }
    await disableAndClearToken(trimmed);
  }

  static Future<bool> _saveToken(String uid, String token) async {
    final platform = _platform();
    if (platform == 'ios' && !_iosPersistGateOpen) return false;
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final bundleId = PushTokenSync.bundleIdForPlatform(platform);
    final apsEnv = PushTokenSync.apsEnvironment(
      isReleaseMode: kReleaseMode,
      isProfileMode: kProfileMode,
    );
    final fields = PushTokenSync.tokenDocFields(
      token: token,
      platform: platform,
      bundleId: bundleId,
      apsEnvironment: platform == 'ios' ? apsEnv : '',
    );

    final tokenRef = userRef.collection('fcmTokens').doc(token);
    await tokenRef.set(
      {
        ...fields,
        'updatedAt': FieldValue.serverTimestamp(),
        'clientBuild': PushTokenSync.clientBuild,
      },
      SetOptions(merge: true),
    );

    final confirmed = await tokenRef.get();
    final stored = (confirmed.data()?['token'] ?? '').toString().trim();
    if (!confirmed.exists || stored.isEmpty) {
      _logPush('persist', {'state': 'unconfirmed'});
      return false;
    }

    // Drop stale iOS siblings so TestFlight rebuilds don't keep dead tokens.
    try {
      final snap = await userRef.collection('fcmTokens').get();
      final prune = PushTokenSync.iosTokenDocsToPrune(
        currentToken: token,
        writerPlatform: platform,
        docs: snap.docs.map(
          (d) => <String, String?>{
            'id': d.id,
            'platform': (d.data()['platform'] ?? '').toString(),
            'token': (d.data()['token'] ?? d.id).toString(),
          },
        ),
      );
      for (final id in prune) {
        await userRef.collection('fcmTokens').doc(id).delete();
      }
    } catch (_) {}

    await userRef.set(
      {
        'hasPush': true,
        'fcmToken': token,
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    _logPush('persist', {'state': 'confirmed'});
    return true;
  }

  static String _platform() {
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
    } catch (_) {}
    return 'unknown';
  }

  /// Recebe FCM em foreground sem criar banner/local/som.
  static Future<void> _onForegroundMessage(RemoteMessage message) async {
    final data = Map<String, dynamic>.from(message.data);
    if (kDebugMode) {
      debugPrint(
        'PushService foreground data '
        'type=${data['type']} suppressVisual='
        '${AppNotificationState.instance.shouldSuppressVisualNotification(data)} '
        'skipUnread='
        '${AppNotificationState.instance.shouldSkipUnreadIncrement(data)}',
      );
    }

    // Regra: nunca notificação visual em primeiro plano.
    if (AppNotificationState.instance.shouldSuppressVisualNotification(data)) {
      return;
    }

    // Caminho defensivo (não deve ocorrer com a regra atual).
    await _showLocalNotification(message);
  }

  /// Expõe a decisão para testes sem depender do plugin.
  @visibleForTesting
  static bool shouldDisplayLocalForMessage(RemoteMessage message) {
    return AppNotificationState.instance.shouldShowLocalNotification(
      Map<String, dynamic>.from(message.data),
    );
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    final data = message.data;
    final title = (notification?.title ??
            data['otherName'] ??
            data['groupName'] ??
            'Remdy')
        .toString()
        .trim();
    final body = (notification?.body ?? '').trim();
    final imageUrl = (data['imageUrl'] ?? notification?.android?.imageUrl ?? '')
        .toString()
        .trim();

    if (title.isEmpty && body.isEmpty) return;

    await _initLocalNotifications();

    final payload = PushOpenParser.encodeData(data);
    final details = await _buildNotificationDetails(
      title: title,
      body: body.isEmpty ? title : body,
      imageUrl: imageUrl.isNotEmpty ? imageUrl : null,
    );

    await _localNotifications.show(
      message.hashCode,
      title,
      body.isEmpty ? title : body,
      details,
      payload: payload,
    );
  }

  static Future<String?> _downloadPushImage(String url) async {
    if (url.isEmpty || !url.startsWith('http')) return null;
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/push_${url.hashCode.abs()}.img');
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file.path;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Push image download failed: $e');
      }
      return null;
    }
  }

  static Future<NotificationDetails> _buildNotificationDetails({
    required String title,
    required String body,
    String? imageUrl,
  }) async {
    StyleInformation? styleInformation;
    AndroidBitmap<Object>? largeIcon;
    List<DarwinNotificationAttachment>? iosAttachments;

    if (imageUrl != null && imageUrl.isNotEmpty) {
      final imagePath = await _downloadPushImage(imageUrl);
      if (imagePath != null && File(imagePath).existsSync()) {
        final bitmap = FilePathAndroidBitmap(imagePath);
        largeIcon = bitmap;
        styleInformation = BigPictureStyleInformation(
          bitmap,
          contentTitle: title,
          summaryText: body,
          hideExpandedLargeIcon: true,
        );
        iosAttachments = [DarwinNotificationAttachment(imagePath)];
      }
    }

    return NotificationDetails(
      android: AndroidNotificationDetails(
        _androidChannelId,
        _androidChannelName,
        channelDescription: 'Notificações de chat, grupos e eventos',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: styleInformation,
        largeIcon: largeIcon,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        attachments: iosAttachments,
      ),
    );
  }

  static final PushOpenQueue openQueue = PushOpenQueue();
  static bool _flushingOpen = false;
  static int _openAttempts = 0;

  /// Type-only label. Navigation itself uses [PushOpenParser], which rejects
  /// a missing or unsafe id instead of opening Home.
  @visibleForTesting
  static String resolveOpenRoute(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString().trim();
    if (type == 'group_join_request') return 'group_info';
    if (type.startsWith('event')) return 'event';
    if (type.startsWith('group')) return 'group';
    if (type == 'chat' || type == 'private') return 'chat';
    if (type == 'place_review' || type == 'place_reply') return 'place';
    return 'unknown';
  }

  static void _offerRemoteOpen(RemoteMessage message, PushOpenSource source) {
    final data = Map<String, dynamic>.from(message.data);
    final target = PushOpenParser.parse(data, messageId: message.messageId);
    if (!target.isValid) {
      _logPush('open', {'state': 'invalid', 'source': source.name});
      return;
    }
    final queued = openQueue.offer(target);
    _logPush('open', {
      'state': queued ? 'queued' : 'duplicate',
      'source': source.name,
      ...PushOpenParser.logFields(target),
    });
    if (!queued) return;
    unawaited(flushPendingOpen());
  }

  static Future<void> _handleOpenFromPayload(String payload) async {
    _offerRemoteOpen(
      RemoteMessage(data: PushOpenParser.decodeData(payload)),
      PushOpenSource.foregroundLocal,
    );
  }

  /// AuthGate and MainShell call this once the navigator exists.
  /// A tap that arrived during splash or before age verification stays pending.
  static Future<void> flushPendingOpen() async {
    if (_flushingOpen) return;
    final nav = navKey.currentState;
    var verified = false;
    try {
      verified = await AgeAccessService.currentUserIsVerified();
    } catch (_) {
      verified = false;
    }
    final target = openQueue.peekIfReady(ready: verified && nav != null);
    if (target == null || nav == null) return;
    _flushingOpen = true;
    var opened = false;
    try {
      opened = await _openTarget(target, nav);
      if (opened) {
        openQueue.consume(target);
        _openAttempts = 0;
      }
    } finally {
      _flushingOpen = false;
      if (!opened && openQueue.pending != null && _openAttempts < 6) {
        _openAttempts += 1;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(flushPendingOpen());
        });
      }
    }
  }

  static void _showShell(NavigatorState nav, int index) {
    nav.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => MainShell(initialIndex: index),
      ),
      (route) => false,
    );
  }

  /// Shell first, destination on the next frame so it is not lost under splash.
  static Future<bool> _pushOverShell({
    required NavigatorState nav,
    required int shellIndex,
    required Widget page,
  }) async {
    _showShell(nav, shellIndex);
    final opened = Completer<bool>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final next = navKey.currentState;
      if (next == null) {
        if (!opened.isCompleted) opened.complete(false);
        return;
      }
      next.push(MaterialPageRoute(builder: (_) => page));
      if (!opened.isCompleted) opened.complete(true);
    });
    return opened.future;
  }

  static Future<bool> _openTarget(
    PushOpenTarget target,
    NavigatorState nav,
  ) async {
    if (navKey.currentState == null) return false;

    if (target.kind == PushOpenKind.place) {
      if (!LocaisFeatureFlag.isEnabled) return false;
      final live = navKey.currentState;
      if (live == null) return false;
      return _pushOverShell(
        nav: live,
        shellIndex: target.shellIndex,
        page: LocaisDetailPage(
          placeId: target.placeId,
          repository: createPlaceRepository(),
        ),
      );
    }

    if (target.kind == PushOpenKind.event) {
      if (target.actorUid.isNotEmpty &&
          BlockVisibility.hidesUid(target.actorUid)) {
        _logPush('open', {'state': 'blocked', 'kind': 'event'});
        final live = navKey.currentState;
        if (live == null) return false;
        _showShell(live, target.shellIndex);
        return true;
      }
      try {
        final ev = await FirebaseFirestore.instance
            .collection('events')
            .doc(target.eventId)
            .get();
        if (BlockVisibility.hidesEventMap(ev.data() ?? const {})) {
          _logPush('open', {'state': 'hidden', 'kind': 'event'});
          _showShell(navKey.currentState ?? nav, target.shellIndex);
          return true;
        }
      } catch (_) {
        return false;
      }
      final live = navKey.currentState;
      if (live == null) return false;
      return _pushOverShell(
        nav: live,
        shellIndex: target.shellIndex,
        page: EventDetailPage(eventId: target.eventId),
      );
    }

    if (target.kind == PushOpenKind.groupTab) {
      final live = navKey.currentState;
      if (live == null) return false;
      _showShell(live, target.shellIndex);
      return true;
    }

    if (target.kind == PushOpenKind.groupChat ||
        target.kind == PushOpenKind.groupInfo) {
      var groupName = target.displayName.isEmpty ? 'Remdy' : target.displayName;
      try {
        final snap = await FirebaseFirestore.instance
            .collection('groups')
            .doc(target.groupId)
            .get();
        final n = (snap.data()?['name'] ?? '').toString().trim();
        if (n.isNotEmpty) groupName = n;
      } catch (_) {}
      final live = navKey.currentState;
      if (live == null) return false;
      final page = target.kind == PushOpenKind.groupInfo
          ? GroupInfoPage(groupId: target.groupId)
          : GroupChatPage(groupId: target.groupId, groupName: groupName);
      return _pushOverShell(
        nav: live,
        shellIndex: target.shellIndex,
        page: page,
      );
    }

    if (target.kind == PushOpenKind.chat) {
      if (!await BlockService.allowOpenPeer(target.otherUid)) {
        _logPush('open', {'state': 'blocked', 'kind': 'chat'});
        final live = navKey.currentState;
        if (live == null) return false;
        _showShell(live, target.shellIndex);
        return true;
      }
      var otherName = target.displayName.isEmpty ? 'Remdy' : target.displayName;
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .doc(target.otherUid)
            .get();
        final n = (snap.data()?['name'] ?? '').toString().trim();
        if (n.isNotEmpty) otherName = n;
      } catch (_) {}
      final live = navKey.currentState;
      if (live == null) return false;
      return _pushOverShell(
        nav: live,
        shellIndex: target.shellIndex,
        page: ChatPage(
          conversationId: target.conversationId,
          otherUid: target.otherUid,
          otherName: otherName,
        ),
      );
    }

    return false;
  }
}
