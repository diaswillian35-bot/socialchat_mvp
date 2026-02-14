import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';


class PushService {
  // ✅ necessário para o main.dart usar: navigatorKey: PushService.navKey
  static final navKey = GlobalKey<NavigatorState>();


  static Future<void> init() async {
    // ✅ pede permissão (iOS) e mantém listeners do seu projeto
    try {
      await FirebaseMessaging.instance.requestPermission();
    } catch (_) {}
  }


  /// ✅ Liga push de verdade e garante token no Firestore
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


    // tenta pegar token e salvar
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.trim().isNotEmpty) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set(
          {
            'fcmToken': token.trim(),
            'fcmUpdatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    } catch (_) {}


    return authorized;
  }


  /// ✅ Desliga push (na prática) e limpa token no Firestore
  static Future<void> disableAndClearToken(String uid) async {
    try {
      await FirebaseMessaging.instance.setAutoInitEnabled(false);
    } catch (_) {}


    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set(
        {
          'fcmToken': FieldValue.delete(),
          'fcmUpdatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {}
  }
}
