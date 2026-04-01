import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';


import 'login_page.dart';
import 'splash_page.dart';
import 'main_shell_page.dart';
import 'email_verification_page.dart';


class AuthGate extends StatelessWidget {
  const AuthGate({super.key});


  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SplashPage();
        }


        final user = snap.data;
        if (user == null) return const LoginPage();


        if (!user.emailVerified) {
          return const EmailVerificationPage();
        }


        return const MainShell();
      },
    );
  }
}
