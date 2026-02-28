import 'dart:io';


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';


// ✅ Ajuste esses imports se seus caminhos forem diferentes
import '../pages/main_shell_page.dart';
import '../pages/group_chat_page.dart';


class PushService {
  // ✅ Use exatamente esse navKey no MaterialApp: navigatorKey: PushService.navKey
  static final navKey = GlobalKey<NavigatorState>();


  static bool _started = false;


  static Future<void> init() async {
    // Só pede permissão, sem mexer no resto
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {}
  }


  /// ✅ Chame 1x após login (com uid válido)
  static Future<void> start(String uid) async {
    if (_started) return;
    _started = true;


    // permissões + token
    await enableAndSyncToken(uid);


    // token refresh
    FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
      final token = t.trim();
      if (token.isEmpty) return;
      await _saveToken(uid, token);
    });


    // ✅ clicou na notificação (app em background)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      await _handleOpen(message);
    });


    // ✅ app abriu “frio” pelo push (killed)
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      await _handleOpen(initial);
    }
  }


  /// ✅ Liga push e garante token no Firestore
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


  /// ✅ Desliga push e limpa tokens do usuário
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
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }


  // =========================
  // Interno: salvar token
  // =========================
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


  // =========================
  // ✅ Interno: abrir pelo push
  // =========================
  static Future<void> _handleOpen(RemoteMessage message) async {
    final data = message.data;


    final type = (data['type'] ?? '').toString().trim();


    // ✅ Só vamos tratar GROUP
    if (type != 'group') return;


    final groupId = (data['groupId'] ?? '').toString().trim();
    if (groupId.isEmpty) return;


    // ✅ tenta buscar nome do grupo (pra abrir certinho)
    String groupName = 'Grupo';
    try {
      final snap = await FirebaseFirestore.instance.collection('groups').doc(groupId).get();
      final gd = snap.data();
      final n = (gd?['name'] ?? '').toString().trim();
      if (n.isNotEmpty) groupName = n;
    } catch (_) {}


    final nav = navKey.currentState;
    if (nav == null) return;


    // ✅ 1) garante MainShell na aba Grupos (index 2)
    nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainShell(initialIndex: 2)),
      (route) => false,
    );


    // ✅ 2) micro delay pra garantir que MainShell montou
    await Future.delayed(const Duration(milliseconds: 200));


    // ✅ 3) abre o chat do grupo
    nav.push(
      MaterialPageRoute(
        builder: (_) => GroupChatPage(
          groupId: groupId,
          groupName: groupName,
        ),
      ),
    );
  }
}
