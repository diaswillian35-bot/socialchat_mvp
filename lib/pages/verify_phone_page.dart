import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../widgets/remdy_keyboard_caps.dart';

/// b44: selo de verificado por SMS (sem selfie).
/// O telefone é vinculado no Firebase Auth e a callable markPhoneVerified lê o
/// número no servidor (nunca o que o app manda). O número não aparece a ninguém.
class VerifyPhonePage extends StatefulWidget {
  const VerifyPhonePage({super.key});

  @override
  State<VerifyPhonePage> createState() => _VerifyPhonePageState();
}

class _VerifyPhonePageState extends State<VerifyPhonePage> {
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _primary = Color(0xFF313A5F);

  final _phoneC = TextEditingController();
  final _codeC = TextEditingController();
  String? _verificationId;
  bool _busy = false;

  FirebaseFunctions get _fn => FirebaseFunctions.instanceFor(region: 'us-central1');

  @override
  void dispose() {
    _phoneC.dispose();
    _codeC.dispose();
    super.dispose();
  }

  void _snack(String key, {Map<String, String> vars = const {}}) {
    var s = AppTexts.current.get(key);
    vars.forEach((k, v) => s = s.replaceAll('{$k}', v));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(s)));
  }

  String _normalizedPhone() {
    final raw = _phoneC.text.replaceAll(RegExp(r'[^\d+]'), '');
    return raw.startsWith('+') ? raw : '+$raw';
  }

  Future<void> _sendCode() async {
    final phone = _normalizedPhone();
    if (!RegExp(r'^\+\d{8,15}$').hasMatch(phone)) {
      _snack('verify_phone_invalid');
      return;
    }
    setState(() => _busy = true);
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phone,
      verificationCompleted: (cred) => _link(cred),
      verificationFailed: (e) {
        if (!mounted) return;
        setState(() => _busy = false);
        _snack('verify_error');
      },
      codeSent: (id, _) {
        if (!mounted) return;
        setState(() {
          _verificationId = id;
          _busy = false;
        });
        _snack('verify_code_sent', vars: {'phone': phone});
      },
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<void> _confirmCode() async {
    final id = _verificationId;
    final code = _codeC.text.trim();
    if (id == null || code.length < 4) return;
    await _link(PhoneAuthProvider.credential(verificationId: id, smsCode: code));
  }

  Future<void> _link(PhoneAuthCredential cred) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      if ((user.phoneNumber ?? '').isEmpty) {
        await user.linkWithCredential(cred);
      } else {
        await user.updatePhoneNumber(cred);
      }
      await _fn.httpsCallable('markPhoneVerified').call(<String, dynamic>{});
      if (!mounted) return;
      _snack('verify_done');
      Navigator.of(context).maybePop();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      _snack(e.code == 'credential-already-in-use' || e.code == 'provider-already-linked'
          ? 'verify_phone_in_use'
          : 'verify_error');
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final reason = e.details is Map ? (e.details as Map)['reason'] : null;
      _snack(reason == 'phone_in_use' ? 'verify_phone_in_use' : 'verify_error');
    } catch (_) {
      if (mounted) _snack('verify_error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    setState(() => _busy = true);
    try {
      await _fn.httpsCallable('unlinkVerifiedPhone').call(<String, dynamic>{});
      await FirebaseAuth.instance.currentUser?.reload();
      if (mounted) _snack('verify_removed');
    } catch (_) {
      if (mounted) _snack('verify_error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          t.get('verify_profile_title'),
          style: const TextStyle(color: _text, fontWeight: FontWeight.w900),
        ),
      ),
      body: uid.isEmpty
          ? const SizedBox.shrink()
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance.collection('publicUsers').doc(uid).snapshots(),
              builder: (context, snap) {
                final verified = snap.data?.data()?['verified'] == true;
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        Icon(verified ? Icons.verified : Icons.verified_outlined,
                            color: verified ? _primary : _muted, size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            verified ? t.get('verified_badge_label') : t.get('verify_profile_title'),
                            style: const TextStyle(color: _text, fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      t.get('verify_profile_info'),
                      style: const TextStyle(color: _muted, fontWeight: FontWeight.w600, height: 1.3),
                    ),
                    const SizedBox(height: 18),
                    if (verified)
                      TextButton(
                        key: const Key('verify_remove'),
                        onPressed: _busy ? null : _remove,
                        child: Text(t.get('verify_remove')),
                      )
                    else ...[
                      TextField(
                        key: const Key('verify_phone_field'),
                        controller: _phoneC,
                        enabled: !_busy && _verificationId == null,
                        keyboardType: TextInputType.phone,
                        textCapitalization: RemdyKeyboardCaps.none,
                        decoration: InputDecoration(
                          hintText: t.get('verify_phone_hint'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_verificationId != null) ...[
                        TextField(
                          key: const Key('verify_code_field'),
                          controller: _codeC,
                          enabled: !_busy,
                          keyboardType: TextInputType.number,
                          textCapitalization: RemdyKeyboardCaps.none,
                          decoration: InputDecoration(
                            hintText: t.get('verify_code_hint'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          key: const Key('verify_action'),
                          onPressed: _busy ? null : (_verificationId == null ? _sendCode : _confirmCode),
                          child: Text(_verificationId == null ? t.get('verify_send_code') : t.get('verify_confirm')),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }
}
