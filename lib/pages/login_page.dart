import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'forgot_password_page.dart';

import 'splash_page.dart';


class LoginPage extends StatefulWidget {
  const LoginPage({super.key});


  @override
  State<LoginPage> createState() => _LoginPageState();
}


class _LoginPageState extends State<LoginPage> {
  final _emailC = TextEditingController();
  final _passC = TextEditingController();
  final _confirmC = TextEditingController();


  bool _isLogin = true; // true = entrar | false = criar conta
  bool _loading = false;


  bool _hidePass = true;
  bool _hideConfirm = true;


  bool _rememberMe = true;


  // ✅ CONTAS DE TESTE
  static const String _testEmail = 'diaswillian35@gmail.com';
  static const String _testPass = '123456';


  @override
  void initState() {
    super.initState();
    _loadRemembered();
  }


  @override
  void dispose() {
    _emailC.dispose();
    _passC.dispose();
    _confirmC.dispose();
    super.dispose();
  }


  void _toast(String message, {bool success = false}) {
  if (!mounted) return;


  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            success ? Icons.check_circle : Icons.info_outline,
            color: Colors.white,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: success
          ? const Color(0xFF16A34A) // verde sucesso
          : const Color(0xFF313A5F), // azul Remdy
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      duration: const Duration(seconds: 3),
    ),
  );
}



  bool _isValidEmail(String email) {
    final e = email.trim();
    if (e.isEmpty) return false;
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(e);
  }


  Future<void> _loadRemembered() async {
    final sp = await SharedPreferences.getInstance();
    final remember = sp.getBool('remember_me') ?? true;
    final savedEmail = sp.getString('remember_email') ?? '';


    if (!mounted) return;
    setState(() {
      _rememberMe = remember;
      if (remember && savedEmail.isNotEmpty) _emailC.text = savedEmail;
    });
  }


  Future<void> _saveRemembered() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool('remember_me', _rememberMe);
    if (_rememberMe) {
      await sp.setString('remember_email', _emailC.text.trim());
    } else {
      await sp.remove('remember_email');
    }
  }


  Future<void> _ensureUserDoc(User user, {required bool isNewUser}) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await ref.get();


    final email = (user.email ?? _emailC.text.trim()).trim().toLowerCase();


    if (!snap.exists) {
      await ref.set({
        'uid': user.uid,
        'email': email,
        'name': (user.displayName ?? '').toString(),
        'photoUrl': (user.photoURL ?? '').toString(),
        'countryCode': 'ca',
        'isPremium': false,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return;
    }


    await ref.set({
      'email': email,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
      // atualiza nome/foto se vier do Google e estiver vazio no seu doc
      'name': (user.displayName ?? '').toString(),
      'photoUrl': (user.photoURL ?? '').toString(),
    }, SetOptions(merge: true));


    if (isNewUser) {
      final d = snap.data() ?? {};
      final Map<String, dynamic> patch = {};


      if (d['uid'] == null) patch['uid'] = user.uid;
      if (d['name'] == null) patch['name'] = (user.displayName ?? '').toString();
      if (d['photoUrl'] == null) patch['photoUrl'] = (user.photoURL ?? '').toString();
      if (d['countryCode'] == null) patch['countryCode'] = 'ca';
      if (d['isPremium'] == null) patch['isPremium'] = false;
      if (d['createdAt'] == null) patch['createdAt'] = FieldValue.serverTimestamp();


      if (patch.isNotEmpty) {
        patch['updatedAt'] = FieldValue.serverTimestamp();
        patch['lastSeenAt'] = FieldValue.serverTimestamp();
        await ref.set(patch, SetOptions(merge: true));
      }
    }
  }


  Future<void> _goToApp() async {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const SplashPage()),
      (_) => false,
    );
  }


  Future<void> _submitEmailPass() async {
    final email = _emailC.text.trim();
    final pass = _passC.text;


    if (_loading) return;


    if (email.isEmpty) return _toast("Digite o e-mail.");
    if (!_isValidEmail(email)) return _toast("E-mail inválido.");
    if (pass.length < 6) return _toast("Senha precisa ter no mínimo 6 caracteres.");


    if (!_isLogin) {
      final confirm = _confirmC.text;
      if (confirm.trim() != pass.trim()) return _toast("As senhas não conferem.");
    }


    setState(() => _loading = true);


    try {
      UserCredential cred;


      if (_isLogin) {
        cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: pass,
        );


        final user = cred.user;
        if (user != null) {
          await _ensureUserDoc(user, isNewUser: false);
        }
      } else {
        cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: pass,
        );


        await cred.user?.sendEmailVerification();


        final user = cred.user;
        if (user != null) {
          await _ensureUserDoc(user, isNewUser: true);
        }
      }


      await _saveRemembered();
      await _goToApp();
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? 'Erro ao autenticar.');
    } catch (_) {
      _toast('Erro inesperado.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _forgotPassword() async {
    final email = _emailC.text.trim();
    if (email.isEmpty) return _toast("Digite seu e-mail primeiro.");
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _toast("Enviei um e-mail para redefinir sua senha.");
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? "Erro ao enviar e-mail.");
    }
  }


  // ✅ Google Sign-In (funcionando)
  Future<void> _loginGoogle() async {
    if (_loading) return;
    setState(() => _loading = true);


    try {
      // 1) abre o seletor do Google
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        // usuário cancelou
        return;
      }


      // 2) pega tokens
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );


      // 3) login no Firebase
      final cred = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = cred.user;


      if (user == null) {
        _toast('Erro: usuário do Google veio vazio.');
        return;
      }


      final isNewUser = (cred.additionalUserInfo?.isNewUser == true);


      // 4) garante user doc
      await _ensureUserDoc(user, isNewUser: isNewUser);


      // 5) “lembrar e-mail” (opcional)
      if (user.email != null && user.email!.trim().isNotEmpty) {
        _emailC.text = user.email!.trim();
      }
      await _saveRemembered();


      await _goToApp();
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? 'Erro no Google.');
    } catch (e) {
      _toast('Erro no Google: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  // ✅ Entrar como Teste
  Future<void> _loginTest() async {
    if (_loading) return;


    setState(() => _loading = true);
    try {
      final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _testEmail,
        password: _testPass,
      );


      final user = cred.user;
      if (user != null) {
        await _ensureUserDoc(user, isNewUser: false);
      }


      _emailC.text = _testEmail;
      await _saveRemembered();
      await _goToApp();
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? "Erro ao entrar com Teste.");
      _toast("Dica: crie o usuário $_testEmail no Firebase Auth (Email/Senha).");
    } catch (_) {
      _toast("Erro inesperado no modo Teste.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  void _loginApple() {
    _toast("Apple: deixei o botão. Depois configuramos com calma.");
  }


  void _loginFacebook() {
    _toast("Facebook: deixei o botão. Depois configuramos com calma.");
  }


  @override
  Widget build(BuildContext context) {
    final title = _isLogin ? "Entrar" : "Criar conta";


    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
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
                    )
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 14),


                    Center(
                      child: Image.asset(
                        'assets/remdy_logo.png',
                        height: 120,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 16),


                    TextField(
                      controller: _emailC,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'E-mail',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),


                    TextField(
                      controller: _passC,
                      obscureText: _hidePass,
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _hidePass = !_hidePass),
                          icon: Icon(_hidePass ? Icons.visibility_off : Icons.visibility),
                        ),
                      ),
                    ),


                    if (!_isLogin) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _confirmC,
                        obscureText: _hideConfirm,
                        decoration: InputDecoration(
                          labelText: 'Confirmar senha',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _hideConfirm = !_hideConfirm),
                            icon: Icon(_hideConfirm ? Icons.visibility_off : Icons.visibility),
                          ),
                        ),
                      ),
                    ],


                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Checkbox(
                          value: _rememberMe,
                          onChanged: (v) => setState(() => _rememberMe = v ?? true),
                        ),
                        const Text("Lembrar de mim"),
                        const Spacer(),
                        TextButton(
  onPressed: (!_isLogin || _loading)
      ? null
      : () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const ForgotPasswordPage(),
            ),
          );
        },
  child: const Text("Esqueceu a senha?"),
),

                      ],
                    ),
                    const SizedBox(height: 6),


                    ElevatedButton(
                      onPressed: _loading ? null : _submitEmailPass,
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
                          : Text(_isLogin ? "Entrar" : "Criar conta"),
                    ),


                    const SizedBox(height: 10),


                    // ✅ Google (novo)
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _loginGoogle,
                      icon: const Icon(Icons.g_mobiledata),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text("Continue with Google"),
                      ),
                    ),


                    const SizedBox(height: 10),


                    


                    const SizedBox(height: 14),


                    OutlinedButton.icon(
                      onPressed: _loading ? null : _loginApple,
                      icon: const Icon(Icons.apple),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text("Continue with Apple"),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _loginFacebook,
                      icon: const Icon(Icons.facebook),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text("Continue with Facebook"),
                      ),
                    ),


                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: _loading
                            ? null
                            : () {
                                setState(() {
                                  _isLogin = !_isLogin;
                                  _passC.clear();
                                  _confirmC.clear();
                                });
                              },
                        child: Text(
                          _isLogin ? " Não tem conta? Criar agora" : "Já tem conta? Entrar",
                        ),
                      ),
                    ),


                    if (!_isLogin)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          "Ao criar conta, você receberá um e-mail de verificação.",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
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
