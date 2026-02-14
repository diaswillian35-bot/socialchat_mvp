import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';

class PresenceService with WidgetsBindingObserver {
  PresenceService._();
  static final PresenceService instance = PresenceService._();

  final _db = FirebaseFirestore.instance;

  Timer? _timer;
  bool _started = false;

  String? _uid;
  String _countryCode = 'ca'; // default seguro
  String _countryName = '';

  DocumentReference<Map<String, dynamic>> _publicDoc(String uid) =>
      _db.collection('publicUsers').doc(uid);

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);

  /// Chame UMA VEZ quando a MainShell abrir
  Future<void> start() async {
    if (_started) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return; // ✅ não trava _started

    _started = true;
    WidgetsBinding.instance.addObserver(this);

    _uid = user.uid;

    // tenta carregar countryCode/country do users/{uid} (não depende da Home)
    await _loadUserBasics();

    // marca online imediatamente
    await _ping(isOnline: true);

    // heartbeat: atualiza lastSeenAt a cada 25s (bom para regra de 90s)
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 25), (_) async {
      await _ping(isOnline: true);
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Chame quando sair/logoff ou se quiser parar de vez
  Future<void> stop() async {
    _stopTimer();

    final uid = _uid;
    _uid = null;

    WidgetsBinding.instance.removeObserver(this);
    _started = false;

    if (uid != null) {
      // ✅ offline só no stop/logout (opcional)
      await _ping(uidOverride: uid, isOnline: false);
    }
  }

  Future<void> _loadUserBasics() async {
    final uid = _uid;
    if (uid == null) return;

    try {
      final snap = await _userDoc(uid).get();
      final data = snap.data() ?? {};

      final cc = (data['countryCode'] ?? '').toString().trim().toLowerCase();
      final cn = (data['country'] ?? '').toString().trim();

      if (cc.isNotEmpty) _countryCode = cc;
      if (cn.isNotEmpty) _countryName = cn;
    } catch (_) {
      // mantém defaults
    }
  }

  Future<void> _ping({String? uidOverride, required bool isOnline}) async {
    final uid = uidOverride ?? _uid;
    if (uid == null) return;

    try {
      await _publicDoc(uid).set({
        'uid': uid,
        'countryCode': _countryCode, // ESSENCIAL pra contagem por país
        'country': _countryName,     // opcional
        'isOnline': isOnline,
        'lastSeenAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // não quebra o app se der erro de rede/rules
    }
  }

  // =========================
  // App lifecycle
  // =========================
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ✅ Quando volta pro app -> retoma ping + timer
    if (state == AppLifecycleState.resumed) {
      _ping(isOnline: true);
      _startTimer();
      return;
    }

    // ✅ Quando sai/pausa -> NÃO marque offline aqui
    // (isso é o que estava zerando sua contagem)
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      // opcional: dá uma última atualizada no lastSeen antes de parar timer
      _ping(isOnline: true);
      _stopTimer();
    }
  }
}
