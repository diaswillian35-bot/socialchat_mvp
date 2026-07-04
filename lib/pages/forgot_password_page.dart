import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';


class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});


  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}


class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailC = TextEditingController();
  bool _loading = false;


  @override
  void dispose() {
    _emailC.dispose();
    super.dispose();
  }


  bool _isValidEmail(String email) {
    final e = email.trim();
    if (e.isEmpty) return false;
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(e);
  }


  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        duration: const Duration(seconds: 4),
      ),
    );
  }


  Future<void> _send() async {
    final email = _emailC.text.trim();


    if (_loading) return;


    if (email.isEmpty) return _toast("Digite seu e-mail.");
    if (!_isValidEmail(email)) return _toast("E-mail inválido.");


    setState(() => _loading = true);


    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
  email: email,
  actionCodeSettings: ActionCodeSettings(
    url: 'https://remdy.app/reset-done',
    handleCodeInApp: false,
    androidPackageName: 'com.example.socialchatmvp',
    androidInstallApp: true,
    androidMinimumVersion: '1',
    iOSBundleId: 'com.example.socialchatmvp',
  ),
);

      _toast("Enviei um e-mail para redefinir sua senha ✅");
      if (!mounted) return;
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      // Mensagens mais claras
      final code = e.code;
      if (code == 'user-not-found') {
        _toast("Não encontrei uma conta com esse e-mail.");
      } else if (code == 'invalid-email') {
        _toast("E-mail inválido.");
      } else if (code == 'too-many-requests') {
        _toast("Muitas tentativas. Tente novamente mais tarde.");
      } else {
        _toast(e.message ?? "Erro ao enviar e-mail.");
      }
    } catch (_) {
      _toast("Erro inesperado.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  @override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: Colors.white, // 🔥 fundo branco
    appBar: AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      iconTheme: const IconThemeData(color: Colors.black),
      title: const Text(
        "Recuperar senha",
        style: TextStyle(color: Colors.black),
      ),
    ),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [


                // 🔥 LOGO
                Image.asset(
                  'assets/remdy_logo.png',
                  height: 100,
                  fit: BoxFit.contain,
                ),


                const SizedBox(height: 24),


                // 🔥 CARD
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
                      const Text(
                        "Digite seu e-mail",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Vamos enviar um link para você criar uma nova senha.",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: _emailC,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'E-mail',
                          border: OutlineInputBorder(),
                        ),
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
                            : const Text("Enviar link"),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

}
