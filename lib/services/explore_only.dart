import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import 'presence_service.dart';

/// Modo "Só explorar" (users/{uid}.exploreOnly, espelhado em publicUsers).
///
/// Ligado: a pessoa usa Locais, Eventos e Grupos, mas não aparece em
/// Conheça Pessoas / perto / novos na cidade / buscas, não publica presença,
/// não vê quem está online e ninguém inicia conversa com ela.
class ExploreOnly extends ChangeNotifier {
  ExploreOnly._();

  static final ExploreOnly instance = ExploreOnly._();

  static const String field = 'exploreOnly';

  bool _on = false;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _docSub;

  /// Estado do próprio usuário (cache síncrono; false em testes).
  static bool get isOn => instance._on;

  static bool isExploreOnlyData(Map<String, dynamic>? data) =>
      data != null && data[field] == true;

  void start() {
    _authSub ??= FirebaseAuth.instance.authStateChanges().listen((user) {
      _docSub?.cancel();
      _docSub = null;
      if (user == null) {
        _set(false);
        return;
      }
      _docSub = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen(
            (snap) => _set(isExploreOnlyData(snap.data())),
            onError: (_) {},
          );
    });
  }

  void _set(bool value) {
    if (value == _on) return;
    _on = value;
    notifyListeners();
  }

  /// Atualiza o cache local logo após salvar (antes do snapshot chegar).
  void setLocal(bool value) => _set(value);

  @visibleForTesting
  void debugSet(bool value) => _set(value);

  /// Grava em users e publicUsers. Presença é tratada pelo chamador.
  static Future<void> save(String uid, bool value) async {
    final db = FirebaseFirestore.instance;
    final now = FieldValue.serverTimestamp();
    await db
        .collection('users')
        .doc(uid)
        .set({field: value, 'updatedAt': now}, SetOptions(merge: true));
    await db
        .collection('publicUsers')
        .doc(uid)
        .set({field: value, 'updatedAt': now}, SetOptions(merge: true));
    instance._set(value);
  }

  /// Liga/desliga o modo (users + publicUsers) e para/retoma a presença,
  /// igual ao Editar perfil.
  static Future<void> setMode(String uid, bool value) async {
    await save(uid, value);
    if (value) {
      await PresenceService.instance.stop();
    } else {
      unawaited(PresenceService.instance.start());
    }
  }

  /// true (e avisa com SnackBar) se [otherUid] está no modo Só explorar e
  /// ainda não há conversa: ninguém inicia conversa com essa pessoa.
  static Future<bool> blocksNewChat(
    BuildContext context,
    String otherUid,
  ) async {
    if (otherUid.trim().isEmpty) return false;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(otherUid)
          .get();
      if (!isExploreOnlyData(snap.data())) return false;
    } catch (_) {
      return false;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.current.get('explore_only_no_chat'))),
      );
    }
    return true;
  }
}
