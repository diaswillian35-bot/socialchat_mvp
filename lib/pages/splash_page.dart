import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'email_verification_page.dart';

import 'main_shell_page.dart'; // contém MainShell (mantido)
import 'login_page.dart';
import 'edit_profile_page.dart';
import 'auth_gate.dart';


class SplashPage extends StatefulWidget {
  const SplashPage({super.key});


  @override
  State<SplashPage> createState() => _SplashPageState();
}


class _SplashPageState extends State<SplashPage> {
  bool _navigated = false;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _go());
  }


  Future<void> _go() async {
    if (_navigated) return;


    try {
      await Future.delayed(const Duration(milliseconds: 1200));


      final user = FirebaseAuth.instance.currentUser;


      // 1) Sem login => LoginPage
      if (user == null) {
        
        _replace(const LoginPage());
        return;
      }
await user.reload();
final freshUser = FirebaseAuth.instance.currentUser;

if (freshUser == null) {
  _replace(const LoginPage());
  return;
}

if (!freshUser.emailVerified) {
  _replace(const EmailVerificationPage());
  return;
}


      // 2) Com login => checa perfil no Firestore
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();


      final data = doc.data() ?? {};


      // Se ainda não travou país / não definiu homeCountryCode
      final home = (data['homeCountryCode'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final locked = (data['countryLocked'] == true);


      if (!doc.exists || home.isEmpty || !locked) {
        _replace(const EditProfilePage());
        return;
      }


      final profileComplete = (data['profileComplete'] == true);


      // Se não completou perfil => EditProfilePage
      if (!profileComplete) {
        _replace(const EditProfilePage());
        return;
      }


      // 3) Tudo ok => segue fluxo atual
      _replace(const AuthGate());
    } catch (_) {
      _replace(const LoginPage());
    }
  }


  void _replace(Widget page) {
    if (!mounted || _navigated) return;
    _navigated = true;


    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
  }


  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image(
                image: AssetImage('assets/remdy_logo.png'),
                width: 170,
                height: 170,
                fit: BoxFit.contain,
              ),
              SizedBox(height: 20),
              SizedBox(height: 18),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(
                    Color(0xFF313A5F),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
