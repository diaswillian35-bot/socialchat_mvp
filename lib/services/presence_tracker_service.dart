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
  String _countryCode = 'ca';
  String _countryName = '';


  DocumentReference<Map<String, dynamic>> _publicDoc(String uid) =>
      _db.collection('publicUsers').doc(uid);


  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      _db.collection('users').doc(uid);


  Future<void> start() async {
    if (_started) return;


    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;


    _started = true;
    WidgetsBinding.instance.addObserver(this);


    _uid = user.uid;


    await _loadUserBasics();
    await _ping(isOnline: true);
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


  Future<void> stop() async {
    _stopTimer();


    final uid = _uid;
    _uid = null;


    WidgetsBinding.instance.removeObserver(this);
    _started = false;


    if (uid != null) {
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
    } catch (_) {}
  }


  Future<void> _ping({String? uidOverride, required bool isOnline}) async {
    final uid = uidOverride ?? _uid;
    if (uid == null) return;


    final now = FieldValue.serverTimestamp();


    try {
      await _publicDoc(uid).set({
        'uid': uid,
        'countryCode': _countryCode,
        'country': _countryName,
        'isOnline': isOnline,
        'lastSeenAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));


      await _userDoc(uid).set({
        'isOnline': isOnline,
        'lastSeenAt': now,
        'updatedAt': now,
      }, SetOptions(merge: true));
    } catch (_) {}
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ping(isOnline: true);
      _startTimer();
      return;
    }


    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _ping(isOnline: true);
      _stopTimer();
    }
  }
}
