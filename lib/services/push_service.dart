import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';


class PushService {
  // ✅ necessário para o main.dart usar: navigatorKey: PushService.navKey
  static final navKey = GlobalKey<NavigatorState>();


  static bool _tokenRefreshListening = false;


  static Future<void> init() async {
    // ✅ pede permissão (iOS) e mantém listeners do seu projeto
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {}
  }


  /// ✅ Liga push e garante token no Firestore
  /// Retorna true se tiver permissão (autorizado/provisional).
  static Future<bool> enableAndSyncToken(String uid) async {
    // liga o AutoInit (Android principalmente)
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


    // ✅ 1) salva token atual
    await _saveToken(uid);


    // ✅ 2) escuta refresh de token (MUITO importante no Android)
    _listenTokenRefresh(uid);


    return authorized;
  }


  /// ✅ Desliga push (na prática) e limpa token no Firestore
  static Future<void> disableAndClearToken(String uid) async {
    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
    } catch (_) {}


    // tenta apagar token local (não é garantido em todos devices)
    try {
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}


    // remove token "principal" do user (mantém seu padrão)
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'fcmToken': FieldValue.delete(),
          'fcmUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}


    // opcional: você pode também limpar a subcoleção users/{uid}/fcmTokens
    // (eu deixei sem mexer pra não quebrar nada do seu sistema atual)
  }


  // =========================
  // ✅ NOVO (grupo / multi-device)
  // =========================


  static Future<void> _saveToken(String uid) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.trim().isEmpty) return;


      final t = token.trim();


      // ✅ mantém compatível com o que você já usa hoje
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'fcmToken': t,
          'fcmUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );


      // ✅ recomendado p/ grupos: salvar por-device (não sobrescreve emulador/celular)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('fcmTokens')
          .doc(t)
          .set({
        'token': t,
        'platform': 'unknown', // se quiser, depois colocamos android/ios
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }


  static void _listenTokenRefresh(String uid) {
    if (_tokenRefreshListening) return;
    _tokenRefreshListening = true;


    try {
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        final t = newToken.trim();
        if (t.isEmpty) return;


        // atualiza user principal
        try {
          await FirebaseFirestore.instance.collection('users').doc(uid).set(
            {
              'fcmToken': t,
              'fcmUpdatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        } catch (_) {}


        // atualiza por-device
        try {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('fcmTokens')
              .doc(t)
              .set({
            'token': t,
            'platform': 'unknown',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (_) {}
      });
    } catch (_) {}
  }
}
