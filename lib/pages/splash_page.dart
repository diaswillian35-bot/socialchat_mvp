import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'main_shell_page.dart'; // contém MainShell
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

      // 2) Com login => checa perfil no Firestore
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final data = doc.data();
      final profileComplete = (data?['profileComplete'] == true);

      // Se não existe doc ou não completou perfil => EditProfilePage
      if (!doc.exists || !profileComplete) {
        _replace(const EditProfilePage());
        return;
      }

      // 3) Tudo ok => Home
      _replace(const AuthGate()); // ✅ FIX aqui
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
            // LOGO
            Image(
              image: AssetImage('assets/remdy_logo.png'),
              width: 170, // 👈 maior e mais impactante
              height: 170,
              fit: BoxFit.contain,
            ),

            SizedBox(height: 20),

            // TEXTO
            

            SizedBox(height: 18),

            // LOADING
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
  strokeWidth: 2,
  valueColor: AlwaysStoppedAnimation(Color(0xFF313A5F)), // azul Remdy
),

            ),
          ],
        ),
      ),
    ),
  );
}
}