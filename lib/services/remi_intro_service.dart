import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'remi_intro_logic.dart';

/// Persistência da apresentação da Remi: Firestore (fonte) + cache local por UID.
class RemiIntroService {
  RemiIntroService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    Future<SharedPreferences> Function()? prefsFactory,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance,
        _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  static final RemiIntroService instance = RemiIntroService();

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final Future<SharedPreferences> Function() _prefsFactory;

  String? get _uid => _auth.currentUser?.uid;

  Future<bool> hasLocalSeen(String uid) async {
    final prefs = await _prefsFactory();
    final raw = prefs.getInt(RemiIntroLogic.localVersionKey(uid));
    return RemiIntroLogic.hasSeenIntro(raw);
  }

  Future<void> cacheLocalSeen(
    String uid, {
    int version = RemiIntroLogic.currentVersion,
  }) async {
    final prefs = await _prefsFactory();
    final key = RemiIntroLogic.localVersionKey(uid);
    final prev = prefs.getInt(key);
    final next = RemiIntroLogic.nextStoredVersion(prev, target: version);
    await prefs.setInt(key, next);
  }

  Future<void> setPendingSync(String uid, bool pending) async {
    final prefs = await _prefsFactory();
    final key = RemiIntroLogic.localPendingSyncKey(uid);
    if (pending) {
      await prefs.setBool(key, true);
    } else {
      await prefs.remove(key);
    }
  }

  Future<bool> isPendingSync(String uid) async {
    final prefs = await _prefsFactory();
    return prefs.getBool(RemiIntroLogic.localPendingSyncKey(uid)) == true;
  }

  /// Lê Firestore. `null` = indisponível/erro (não assumir visto).
  Future<bool?> fetchRemoteSeen(
    String uid, {
    Duration timeout = const Duration(milliseconds: 1800),
  }) async {
    try {
      final snap = await _db.collection('users').doc(uid).get().timeout(timeout);
      if (!snap.exists) return false;
      final data = snap.data() ?? {};
      return RemiIntroLogic.hasSeenIntro(data['remiIntroVersion']);
    } catch (_) {
      return null;
    }
  }

  /// Decide se deve mostrar a apresentação (sem spinner longo).
  /// Ordem: cache local → Firestore → se offline e sem cache, mostrar.
  Future<bool> shouldShowIntro({String? uid}) async {
    final id = uid ?? _uid;
    if (id == null || id.isEmpty) return false;

    if (await hasLocalSeen(id)) {
      // Tenta sincronizar falhas anteriores em background.
      // ignore: unawaited_futures
      syncPendingIfNeeded(uid: id);
      return false;
    }

    final remote = await fetchRemoteSeen(id);
    if (remote == true) {
      await cacheLocalSeen(id);
      await setPendingSync(id, false);
      return false;
    }

    // remote == false → primeira vez; remote == null → offline/erro sem cache → mostrar
    return true;
  }

  /// Marca conclusão: local primeiro (rápido), Firestore em seguida sem prender a UI.
  /// Idempotente. Em falha remota, mantém pending e não bloqueia o usuário.
  Future<void> markIntroCompleted({
    String? uid,
    int version = RemiIntroLogic.currentVersion,
  }) async {
    final id = uid ?? _uid;
    if (id == null || id.isEmpty) return;

    await cacheLocalSeen(id, version: version);
    await setPendingSync(id, true);

    // Persistência remota em background — não atrasar navegação.
    // ignore: unawaited_futures
    _persistRemoteIntro(id, version);
  }

  Future<void> _persistRemoteIntro(String id, int version) async {
    try {
      final ref = _db.collection('users').doc(id);
      await _db
          .runTransaction((tx) async {
            final snap = await tx.get(ref);
            final data = snap.data() ?? {};
            final existing =
                RemiIntroLogic.parseIntroVersion(data['remiIntroVersion']);
            final next =
                RemiIntroLogic.nextStoredVersion(existing, target: version);
            tx.set(
              ref,
              {
                'remiIntroVersion': next,
                'remiIntroSeenAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          })
          .timeout(const Duration(seconds: 4));
      await setPendingSync(id, false);
    } catch (_) {
      try {
        await _db
            .collection('users')
            .doc(id)
            .set(
              {
                'remiIntroVersion': version,
                'remiIntroSeenAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            )
            .timeout(const Duration(seconds: 4));
        await setPendingSync(id, false);
      } catch (_) {
        // Mantém pending para syncPendingIfNeeded.
      }
    }
  }

  Future<void> syncPendingIfNeeded({String? uid}) async {
    final id = uid ?? _uid;
    if (id == null || id.isEmpty) return;
    if (!await isPendingSync(id)) return;
    if (!await hasLocalSeen(id)) return;

    try {
      final prefs = await _prefsFactory();
      final version =
          prefs.getInt(RemiIntroLogic.localVersionKey(id)) ??
              RemiIntroLogic.currentVersion;
      await _db.collection('users').doc(id).set(
        {
          'remiIntroVersion': version,
          'remiIntroSeenAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await setPendingSync(id, false);
    } catch (_) {
      // Mantém pending para tentativa futura.
    }
  }
}
