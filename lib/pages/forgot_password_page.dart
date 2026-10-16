import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../services/password_recovery.dart';
import '../widgets/keyboard_safe_body.dart';
import '../widgets/remdy_keyboard_caps.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key, this.sendResetEmail});

  /// Test hook. Production uses [FirebaseAuth.sendPasswordResetEmail].
  final Future<void> Function(String email)? sendResetEmail;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailC = TextEditingController();
  bool _loading = false;
  bool _emptyEmail = false;
  PasswordRecoveryStatus? _status;

  @override
  void dispose() {
    _emailC.dispose();
    super.dispose();
  }

  Future<void> _firebaseSend(String email) {
    return FirebaseAuth.instance.sendPasswordResetEmail(email: email);
  }

  Future<void> _send() async {
    if (_loading) return;
    final email = _emailC.text;
    if (email.trim().isEmpty) {
      setState(() {
        _emptyEmail = true;
        _status = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _emptyEmail = false;
      _status = null;
    });

    final status = await PasswordRecovery.request(
      email: email,
      send: widget.sendResetEmail ?? _firebaseSend,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _status = status;
    });
  }

  String _statusMessage(AppTexts t) {
    if (_emptyEmail) return t.get('password_reset_empty_email');
    switch (_status) {
      case PasswordRecoveryStatus.invalidEmail:
        return t.get('password_reset_invalid_email');
      case PasswordRecoveryStatus.genericSent:
        return t.get('password_reset_generic');
      case PasswordRecoveryStatus.networkError:
        return t.get('password_reset_network');
      case PasswordRecoveryStatus.retryLater:
        return t.get('password_reset_later');
      case null:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final message = _statusMessage(t);
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        leading: IconButton(
          tooltip: t.get('password_reset_back'),
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          t.get('password_reset_title'),
          style: const TextStyle(color: Colors.black),
        ),
      ),
      body: SafeArea(
        child: KeyboardSafeFormBody(
          child: Column(
            children: [
              Image.asset(
                'assets/remdy_logo.png',
                height: 100,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 18,
                      spreadRadius: 2,
                      offset: const Offset(0, 10),
                      color: Colors.black.withOpacity(0.06),
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      t.get('password_reset_prompt'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      t.get('password_reset_help'),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _emailC,
                      textCapitalization: RemdyKeyboardCaps.none,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.done,
                      scrollPadding: const EdgeInsets.only(bottom: 120),
                      decoration: InputDecoration(
                        labelText: t.get('email'),
                        border: const OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                    const SizedBox(height: 14),
                    ElevatedButton(
                      onPressed: _loading ? null : _send,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A8A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(t.get('password_reset_send')),
                    ),
                    if (message.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          message,
                          key: const Key('password-reset-status'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
