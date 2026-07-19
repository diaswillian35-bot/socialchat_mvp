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
import '../pages/chat_page.dart';
import '../pages/event_detail_page.dart';

class PushService {
  static final navKey = GlobalKey<NavigatorState>();

  static const _androidChannelId = 'high_importance_channel';
  static const _androidChannelName = 'Mensagens Remdy';

  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static bool _started = false;
  static bool _localInitialized = false;

  static Future<void> init() async {
    await _initLocalNotifications();
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
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
    await _initLocalNotifications();

    if (!_started) {
      _started = true;

      FirebaseMessaging.onMessage.listen(_showForegroundNotification);

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

  static Future<void> _showForegroundNotification(RemoteMessage message) async {
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
      body: body.isEmpty ? 'Nova notificação' : body,
      imageUrl: imageUrl.isNotEmpty ? imageUrl : null,
    );

    await _localNotifications.show(
      message.hashCode,
      title,
      body.isEmpty ? 'Nova notificação' : body,
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
      debugPrint('Push image download failed: $e');
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

  static Future<void> _handleOpen(RemoteMessage message) async {
    final data = message.data;
    debugPrint('PUSH OPEN: $data');

    final type = (data['type'] ?? '').toString().trim();
    final nav = navKey.currentState;
    if (nav == null) return;

    if (type == 'event') {
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

    if (type == 'group' || type == 'group_join_request') {
      final groupId = (data['groupId'] ?? '').toString().trim();
      if (groupId.isEmpty) {
        nav.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const MainShell(initialIndex: 2)),
          (route) => false,
        );
        return;
      }

      String groupName = (data['groupName'] ?? 'Grupo').toString().trim();
      if (groupName.isEmpty) groupName = 'Grupo';

      if (groupName == 'Grupo') {
        try {
          final snap = await FirebaseFirestore.instance
              .collection('groups')
              .doc(groupId)
              .get();
          final n = (snap.data()?['name'] ?? '').toString().trim();
          if (n.isNotEmpty) groupName = n;
        } catch (_) {}
      }

      nav.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const MainShell(initialIndex: 2)),
        (route) => false,
      );
      await Future.delayed(const Duration(milliseconds: 200));

      if (type == 'group') {
        nav.push(
          MaterialPageRoute(
            builder: (_) => GroupChatPage(
              groupId: groupId,
              groupName: groupName,
            ),
          ),
        );
      }
      return;
    }

    if (type == 'chat' || type == 'private') {
      final conversationId = (data['conversationId'] ?? '').toString().trim();
      final otherUid = (data['otherUid'] ?? data['senderId'] ?? '')
          .toString()
          .trim();
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

      if (otherName.isEmpty) otherName = 'Usuário';

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
