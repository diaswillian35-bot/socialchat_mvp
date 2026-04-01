import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';


import '../services/push_service.dart';
import '../l10n/app_texts.dart';


class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});


  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}


class _NotificationsPageState extends State<NotificationsPage> {
  final db = FirebaseFirestore.instance;


  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);


  static const LinearGradient _primaryGradient = LinearGradient(
    colors: [
      Color(0xFF313A5F),
      Color(0xFF264E9A),
    ],
  );


  String? get _uid => FirebaseAuth.instance.currentUser?.uid;


  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      db.collection('users').doc(uid);


  bool _saving = false;
  String _loadedLocaleCode = '';


  bool _enabled = true;
  bool _chat = true;
  bool _groups = true;
  bool _events = true;


  @override
  void initState() {
    super.initState();
    _load();
  }


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();


    final locale = Localizations.localeOf(context);
    final nextCode = '${locale.languageCode}_${locale.countryCode ?? ''}';


    if (_loadedLocaleCode == nextCode) return;
    _loadedLocaleCode = nextCode;


    AppTexts.load(locale).then((_) {
      if (mounted) setState(() {});
    });
  }


  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: child,
    );
  }


  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) return;


    try {
      final snap = await _userDoc(uid).get();
      final data = snap.data() ?? {};


      final enabled = (data['notifEnabled'] ?? true) == true;
      final chat = (data['notifChat'] ?? true) == true;
      final groups = (data['notifGroups'] ?? true) == true;
      final events = (data['notifEvents'] ?? true) == true;


      if (!mounted) return;
      setState(() {
        _enabled = enabled;
        _chat = chat;
        _groups = groups;
        _events = events;
      });
    } catch (_) {}
  }


  Future<void> _save() async {
    final t = AppTexts.current;
    final uid = _uid;
    if (uid == null) return;


    setState(() => _saving = true);


    try {
      await _userDoc(uid).set({
        'notifEnabled': _enabled,
        'notifChat': _chat,
        'notifGroups': _groups,
        'notifEvents': _events,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));


      if (_enabled) {
        final ok = await PushService.enableAndSyncToken(uid);
        if (!mounted) return;


        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? t.get('notifications_enabled')
                  : t.get('notifications_enabled_but_no_permission'),
            ),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        await PushService.disableAndClearToken(uid);
        if (!mounted) return;


        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(t.get('notifications_disabled')),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 1),
          ),
        );
      }


      if (Navigator.canPop(context)) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${t.get('save_error')}: $e'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(12),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final uid = _uid;


    if (uid == null) {
      return Scaffold(
        body: Center(child: Text(t.get('you_need_to_be_logged_in'))),
      );
    }


    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: true,
        title: Text(
          t.get('notifications'),
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.get('preferences'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: _text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t.get('notifications_preferences_subtitle'),
                    style: const TextStyle(
                      fontSize: 13,
                      color: _muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _enabled,
                    onChanged: (v) => setState(() => _enabled = v),
                    title: Text(
                      t.get('enable_notifications'),
                      style: const TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Text(
                      t.get('disable_notifications_subtitle'),
                      style: const TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Divider(height: 14),
                  Opacity(
                    opacity: _enabled ? 1 : 0.45,
                    child: Column(
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _chat,
                          onChanged:
                              _enabled ? (v) => setState(() => _chat = v) : null,
                          title: Text(
                            t.get('messages'),
                            style: const TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _groups,
                          onChanged: _enabled
                              ? (v) => setState(() => _groups = v)
                              : null,
                          title: Text(
                            t.get('groups'),
                            style: const TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _events,
                          onChanged: _enabled
                              ? (v) => setState(() => _events = v)
                              : null,
                          title: Text(
                            t.get('events'),
                            style: const TextStyle(
                              color: _text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 46,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: _primaryGradient,
                ),
                child: ElevatedButton.icon(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.save, color: Colors.white),
                  label: Text(
                    _saving ? t.get('saving') : t.get('save'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
