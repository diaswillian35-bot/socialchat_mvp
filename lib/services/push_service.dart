import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../pages/main_shell_page.dart';
import '../pages/group_chat_page.dart';
import '../pages/group_info_page.dart';
import '../pages/chat_page.dart';
import '../pages/event_detail_page.dart';
import 'app_notification_state.dart';

class PushService {
  static final navKey = GlobalKey<NavigatorState>();

  static const _androidChannelId = 'high_importance_channel';
  static const _androidChannelName = 'Mensagens Remdy';

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _started = false;
  static bool _localInitialized = false;

  static Future<void> init() async {
    AppNotificationState.instance.bind();
    await _initLocalNotifications();
    await _applyIosForegroundPresentation(show: false);
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {}
  }

  /// iOS: em foreground o FCM nativo também não deve alertar/som.
  static Future<void> _applyIosForegroundPresentation({
    required bool show,
  }) async {
    if (kIsWeb) return;
    try {
      if (!Platform.isIOS) return;
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: show,
        badge: show,
        sound: show,
      );
    } catch (_) {}
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
    AppNotificationState.instance.bind();
    await _initLocalNotifications();
    await _applyIosForegroundPresentation(show: false);

    if (!_started) {
      _started = true;

      // Continua recebendo FCM em foreground para dados/contadores,
      // mas não cria notificação visual/local.
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);

      FirebaseMessaging.onMessageOpenedApp.listen((message) async {
        await _handleOpen(message);
      });

      FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        final trimmed = token.trim();
        if (trimmed.isEmpty) return;
        await _saveToken(uid, trimmed);
      });

      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        await _handleOpen(initial);
      }
    }

    await enableAndSyncToken(uid);
  }

  static Future<bool> enableAndSyncToken(String uid) async {
    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(true);
    } catch (_) {}

    NotificationSettings settings;
    try {
      settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (_) {
      return false;
    }

    final authorized =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.trim().isNotEmpty) {
        await _saveToken(uid, token.trim());
      }
    } catch (_) {}

    return authorized;
  }

  static Future<void> disableAndClearToken(String uid) async {
    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
    } catch (_) {}

    try {
      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens');

      final snap = await col.get();
      for (final d in snap.docs) {
        await d.reference.delete();
      }

      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'fcmUpdatedAt': FieldValue.serverTimestamp(),
          'hasPush': false,
          'fcmToken': FieldValue.delete(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }

  static Future<void> _saveToken(String uid, String token) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    await userRef.collection('fcmTokens').doc(token).set(
      {
        'token': token,
        'platform': _platform(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    await userRef.set(
      {
        'hasPush': true,
        'fcmToken': token,
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
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

    final payload = _encodePayload(data);
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

  static String _encodePayload(Map<String, dynamic> data) {
    return data.entries.map((e) => '${e.key}=${e.value}').join('&');
  }

  static Map<String, String> _decodePayload(String payload) {
    final map = <String, String>{};
    for (final part in payload.split('&')) {
      final idx = part.indexOf('=');
      if (idx <= 0) continue;
      map[part.substring(0, idx)] = part.substring(idx + 1);
    }
    return map;
  }

  static Future<void> _handleOpenFromPayload(String payload) async {
    await _handleOpen(RemoteMessage(data: _decodePayload(payload)));
  }

  /// Resolve a rota de destino do tap (testável sem Navigator).
  @visibleForTesting
  static String resolveOpenRoute(Map<String, dynamic> data) {
    final type = (data['type'] ?? '').toString().trim();
    if (type.startsWith('event') ||
        type == 'event_comment' ||
        type == 'event_reply') {
      return 'event';
    }
    if (type == 'group_join_request') return 'group_info';
    if (type.startsWith('group')) return 'group';
    if (type == 'chat' || type == 'private') return 'chat';
    return 'unknown';
  }

  static Future<void> _handleOpen(RemoteMessage message) async {
    final data = message.data;
    if (kDebugMode) {
      debugPrint('PUSH OPEN: $data');
    }

    final type = (data['type'] ?? '').toString().trim();
    final nav = navKey.currentState;
    if (nav == null) return;

    if (type == 'event' ||
        type == 'event_approved' ||
        type == 'event_rejected' ||
        type == 'event_needs_changes' ||
        type == 'event_changes_approved' ||
        type == 'event_changes_submitted' ||
        type == 'event_moderation' ||
        type == 'event_comment' ||
        type == 'event_reply') {
      final eventId = (data['eventId'] ?? '').toString().trim();
      if (eventId.isEmpty) return;

      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell(initialIndex: 3)),
        (route) => false,
      );
      await Future.delayed(const Duration(milliseconds: 200));
      nav.push(
        MaterialPageRoute(builder: (_) => EventDetailPage(eventId: eventId)),
      );
      return;
    }

    if (type == 'group' ||
        type == 'group_join_request' ||
        type == 'group_join_approved' ||
        type == 'group_join_rejected') {
      final groupId = (data['groupId'] ?? '').toString().trim();
      if (groupId.isEmpty) {
        nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShell(initialIndex: 2)),
          (route) => false,
        );
        return;
      }

      String groupName = (data['groupName'] ?? '').toString().trim();

      if (groupName.isEmpty) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('groups')
              .doc(groupId)
              .get();
          final n = (snap.data()?['name'] ?? '').toString().trim();
          if (n.isNotEmpty) groupName = n;
        } catch (_) {}
      }

      if (groupName.isEmpty) groupName = 'Remdy';

      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell(initialIndex: 2)),
        (route) => false,
      );
      await Future.delayed(const Duration(milliseconds: 200));

      if (type == 'group' || type == 'group_join_approved') {
        nav.push(
          MaterialPageRoute(
            builder: (_) => GroupChatPage(
              groupId: groupId,
              groupName: groupName,
            ),
          ),
        );
      } else if (type == 'group_join_request') {
        nav.push(
          MaterialPageRoute(
            builder: (_) => GroupInfoPage(groupId: groupId),
          ),
        );
      }
      return;
    }

    if (type == 'chat' || type == 'private') {
      final conversationId = (data['conversationId'] ?? '').toString().trim();
      final otherUid =
          (data['otherUid'] ?? data['senderId'] ?? '').toString().trim();
      String otherName = (data['otherName'] ?? '').toString().trim();

      if (conversationId.isEmpty || otherUid.isEmpty) return;

      if (otherName.isEmpty) {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('users')
              .doc(otherUid)
              .get();
          final n = (snap.data()?['name'] ?? '').toString().trim();
          if (n.isNotEmpty) otherName = n;
        } catch (_) {}
      }

      if (otherName.isEmpty) otherName = 'Remdy';

      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell(initialIndex: 1)),
        (route) => false,
      );
      await Future.delayed(const Duration(milliseconds: 200));
      nav.push(
        MaterialPageRoute(
          builder: (_) => ChatPage(
            conversationId: conversationId,
            otherUid: otherUid,
            otherName: otherName,
          ),
        ),
      );
    }
  }
}
