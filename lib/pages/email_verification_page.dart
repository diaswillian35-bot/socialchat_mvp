import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';


import 'splash_page.dart';
import 'login_page.dart';


class EmailVerificationPage extends StatefulWidget {
  const EmailVerificationPage({super.key});


  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}


class _EmailVerificationPageState extends State<EmailVerificationPage> {
  bool _loading = false;


  void _toast(String msg, {bool success = false}) {
    if (!mounted) return;


    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 4),
        backgroundColor:
            success ? const Color(0xFF16A34A) : const Color(0xFF313A5F),
      ),
    );
  }


  Future<void> _checkNow() async {
    if (_loading) return;
    setState(() => _loading = true);


    try {
      final user = FirebaseAuth.instance.currentUser;


      if (user == null) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (_) => false,
        );
        return;
      }


      await user.reload();
      final freshUser = FirebaseAuth.instance.currentUser;


      if (freshUser != null && freshUser.emailVerified) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const SplashPage()),
          (_) => false,
        );
        return;
      }


      _toast(
        'Seu e-mail ainda não foi confirmado. Verifique sua caixa de entrada ou a pasta SPAM.',
      );
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? 'Erro ao verificar e-mail.');
    } catch (_) {
      _toast('Erro inesperado ao verificar e-mail.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _resendEmail() async {
    if (_loading) return;
    setState(() => _loading = true);


    try {
      final user = FirebaseAuth.instance.currentUser;


      if (user == null) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (_) => false,
        );
        return;
      }


      await user.sendEmailVerification();


      _toast(
        'E-mail reenviado. Verifique sua caixa de entrada ou a pasta SPAM.',
        success: true,
      );
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? 'Erro ao reenviar e-mail.');
    } catch (_) {
      _toast('Erro inesperado ao reenviar e-mail.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _backToLogin() async {
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}


    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }


  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';


    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          'Confirmar e-mail',
          style: TextStyle(color: Colors.black),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
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
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Image.asset(
                        'assets/remdy_logo.png',
                        height: 110,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Confirme seu e-mail',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      email.isEmpty
                          ? 'Enviamos um e-mail de confirmação para você.'
                          : 'Enviamos um e-mail de confirmação para:\n$email',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.4,
                        color: Color(0xFF374151),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Verifique sua caixa de entrada e também a pasta SPAM ou lixo eletrônico. Depois clique em "Já confirmei".',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(height: 22),
                    ElevatedButton(
                      onPressed: _loading ? null : _checkNow,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF313A5F),
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
                          : const Text('Já confirmei'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: _loading ? null : _resendEmail,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Reenviar e-mail'),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _loading ? null : _backToLogin,
                      child: const Text('Voltar para login'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
