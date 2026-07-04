import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import '../services/locale_controller.dart';


import 'forgot_password_page.dart';
import 'splash_page.dart';
import 'email_verification_page.dart';
import '../l10n/app_texts.dart';



class LoginPage extends StatefulWidget {
  const LoginPage({super.key});


  @override
  State<LoginPage> createState() => _LoginPageState();
}


class _LoginPageState extends State<LoginPage> {
  final _emailC = TextEditingController();
  final _passC = TextEditingController();
  final _confirmC = TextEditingController();
  



  
@override
void didChangeDependencies() {
  super.didChangeDependencies();

  final locale = WidgetsBinding.instance.platformDispatcher.locale;
  final nextCode = '${locale.languageCode}_${locale.countryCode ?? ''}';

  if (_loadedLocaleCode == nextCode) return;
  _loadedLocaleCode = nextCode;


  AppTexts.load(locale).then((_) {
    if (mounted) setState(() {});
  });
}




  bool _isLogin = true;
  bool _loading = false;


  bool _hidePass = true;
  bool _hideConfirm = true;


  bool _rememberMe = true;
  String _loadedLocaleCode = '';

  static const String _testEmail = 'diaswillian35@gmail.com';
  static const String _testPass = '123456';


  @override
  void initState() {
    super.initState();
    _bootLoginPage();
  }


  Future<void> _bootLoginPage() async {
      await _loadRemembered();
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
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        backgroundColor:
            success ? const Color(0xFF16A34A) : const Color(0xFF313A5F),
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


    final rx = RegExp(
      r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$',
    );
    return rx.hasMatch(e);
  }


  Future<void> _loadRemembered() async {
    final sp = await SharedPreferences.getInstance();
    final remember = sp.getBool('remember_me') ?? true;
    final savedEmail = sp.getString('remember_email') ?? '';


    if (!mounted) return;
    setState(() {
      _rememberMe = remember;
      if (remember && savedEmail.isNotEmpty) {
        _emailC.text = savedEmail;
      }
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


  Future<void> _clearStaleSession() async {
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}


    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
  }

String _generateInviteCode(String name, String uid) {
  final clean = name
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9 ]'), '')
      .replaceAll(RegExp(r'\s+'), '-');


  final base = clean.isEmpty ? 'REMDY' : clean.split('-').first;
  final short = uid.substring(0, 4).toUpperCase();


  return '$base-$short';
}







  Future<void> _ensureUserDoc(User user, {required bool isNewUser}) async {
    final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
    final snap = await ref.get();


    final email = (user.email ?? _emailC.text.trim()).trim().toLowerCase();
    final displayName = ((user.displayName ?? '').trim().isNotEmpty)
    ? (user.displayName ?? '').trim()
    : ((snap.data()?['name'] ?? '').toString().trim());
;
    final profilePhotoUrl = (user.photoURL ?? '').trim();


    if (!snap.exists) {



  await ref.set({
    'uid': user.uid,
    'email': email,
    'name': displayName,
    'profilePhotoUrl': profilePhotoUrl,
   'inviteCode': _generateInviteCode(
  displayName,
  user.uid,
),

    'countryCode': '',
    'homeCountryCode': '',
    'countryLocked': false,
    'isPremium': false,
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
    'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
  return;
}


    final d = snap.data() ?? {};


    final Map<String, dynamic> patch = {
      'uid': user.uid,
      'email': email,
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    };



    if (displayName.isNotEmpty) patch['name'] = displayName;
    if (profilePhotoUrl.isNotEmpty) {
      patch['profilePhotoUrl'] = profilePhotoUrl;
    }


    if (d['homeCountryCode'] == null) patch['homeCountryCode'] = '';
if (d['countryCode'] == null) patch['countryCode'] = '';
if (d['countryLocked'] == null) patch['countryLocked'] = false;
if (d['isPremium'] == null) patch['isPremium'] = false;


final currentInviteCode = (d['inviteCode'] ?? '').toString().trim();
if (currentInviteCode.isEmpty) {
  patch['inviteCode'] = _generateInviteCode(
    displayName,
    user.uid,
  );
}





    await ref.set(patch, SetOptions(merge: true));
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
    final email = _emailC.text.trim().toLowerCase();
    final pass = _passC.text;


    if (_loading) return;


    if (email.isEmpty) return _toast("Digite o e-mail.");
    if (!_isValidEmail(email)) return _toast("Digite um e-mail válido.");
    if (pass.length < 6) {
      return _toast("Senha precisa ter no mínimo 6 caracteres.");
    }


    if (!_isLogin) {
      final confirm = _confirmC.text;
      if (confirm.trim() != pass.trim()) {
        return _toast("As senhas não conferem.");
      }
    }


    setState(() => _loading = true);


    try {
      await _clearStaleSession();


      UserCredential cred;


      if (_isLogin) {
        cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: pass,
        );


        final user = cred.user;
        if (user == null) {
          _toast('Erro ao entrar.');
          return;
        }


        await user.reload();
        final freshUser = FirebaseAuth.instance.currentUser;


        


     

        await _ensureUserDoc(freshUser ?? user, isNewUser: false);
      } else {
        cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: pass,
        );


        final user = cred.user;
        if (user == null) {
          _toast('Erro ao criar conta.');
          return;
        }
await FirebaseAuth.instance.setLanguageCode(
  AppTexts.current.locale.languageCode,
);


       await user.sendEmailVerification();
await _ensureUserDoc(user, isNewUser: true);


if (!mounted) return;


Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (_) => const EmailVerificationPage(),
  ),
);


return;




      }


     await _saveRemembered();
await _goToApp();
return;

      } on FirebaseAuthException catch (e) {
      _toast(e.message ?? 'Erro ao autenticar.');
    } catch (_) {
      _toast('Erro inesperado.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  Future<void> _forgotPassword() async {
    final email = _emailC.text.trim().toLowerCase();


    if (email.isEmpty) return _toast("Digite seu e-mail primeiro.");
    if (!_isValidEmail(email)) return _toast("Digite um e-mail válido.");


    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _toast("Enviei um e-mail para redefinir sua senha.");
    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? "Erro ao enviar e-mail.");
    }
  }


  Future<void> _loginGoogle() async {
    if (_loading) return;
    setState(() => _loading = true);


    try {
      await _clearStaleSession();


      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;


      final googleAuth = await googleUser.authentication;


      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );


      final cred = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = cred.user;


      if (user == null) {
        _toast('Erro: usuário do Google veio vazio.');
        return;
      }


      final isNewUser = cred.additionalUserInfo?.isNewUser == true;


      await _ensureUserDoc(user, isNewUser: isNewUser);


      if (user.email != null && user.email!.trim().isNotEmpty) {
        _emailC.text = user.email!.trim();
      }


     await _saveRemembered();
await _goToApp();
return;

    } on FirebaseAuthException catch (e) {
      _toast(e.message ?? 'Erro no Google.');
    } catch (e) {
      _toast('Erro no Google: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


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
return;

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


 Future<void> _loginFacebook() async {
  setState(() => _loading = true);

  try {
    final result = await FacebookAuth.instance.login(
     permissions: ['email', 'public_profile'],
    );

    if (result.status != LoginStatus.success) {
      _toast('Login Facebook cancelado.');
      return;
    }

    final accessToken = result.accessToken;

    if (accessToken == null) {
      _toast('Erro ao obter token do Facebook.');
      return;
    }

    final credential = FacebookAuthProvider.credential(
      accessToken.tokenString,
    );


await FirebaseAuth.instance.signInWithCredential(credential);

final user = FirebaseAuth.instance.currentUser;

print("UID: ${user?.uid}");
print("EMAIL: ${user?.email}");
print("NAME: ${user?.displayName}");
print("PHOTO: ${user?.photoURL}");

await _goToApp();



return;

 } on FirebaseAuthException catch (e) {
  if (e.code == 'account-exists-with-different-credential') {
    _toast(
      'Esta conta já existe. Entre usando Google, Apple ou e-mail e senha.',
    );
    return;
  }

  _toast(e.message ?? 'Erro no login Facebook.');
} catch (e) {
  _toast('Erro no login Facebook.');
}
 finally {
    if (mounted) setState(() => _loading = false);
  }
}




  @override
Widget build(BuildContext context) {
 final t = AppTexts.current;
final title =
    _isLogin ? t.get('login_title') : t.get('create_account_title');

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
                      decoration: InputDecoration(
                        labelText: t.get('email'),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _passC,
                      obscureText: _hidePass,
                      decoration: InputDecoration(
                        labelText: t.get('password'),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () =>
                              setState(() => _hidePass = !_hidePass),
                          icon: Icon(
                            _hidePass ? Icons.visibility_off : Icons.visibility,
                          ),
                        ),
                      ),
                    ),
                    if (!_isLogin) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _confirmC,
                        obscureText: _hideConfirm,
                        decoration: InputDecoration(
                          labelText:t.get ('confirm_password'),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () => setState(
                              () => _hideConfirm = !_hideConfirm,
                            ),
                            icon: Icon(
                              _hideConfirm
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
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
    Expanded(
      child: Text(
        t.get('remember_me'),
        overflow: TextOverflow.ellipsis,
      ),
    ),
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
      child: Text(t.get('forgot_password')),
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
                          : Text(
  _isLogin
      ? t.get('login_button')
      : t.get('create_account_button'),
),

                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _loginGoogle,
                      icon: const Icon(Icons.g_mobiledata),
                      label:  Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child:Text(t.get('continue_google')),

                      ),
                    ),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _loginApple,
                      icon: const Icon(Icons.apple),
                      label:  Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child:Text(t.get('continue_apple')),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _loading ? null : _loginFacebook,
                      icon: const Icon(Icons.facebook),
                      label: Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(t.get('continue_facebook')),
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
  _isLogin
      ? t.get('no_account')
      : t.get('already_account'),
),

                      ),
                    ),
                    if (!_isLogin)
  Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Text(
      t.get('verify_email_notice'),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 12, color: Colors.black54),
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
