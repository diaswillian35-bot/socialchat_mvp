import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';


import 'main_shell_page.dart'; // contém MainShell (mantido)
import 'login_page.dart';
import 'edit_profile_page.dart';
import 'auth_gate.dart';


// ✅ usa seu controller (já existe em lib/services/locale_controller.dart)
import '../services/locale_controller.dart';


class SplashPage extends StatefulWidget {
  const SplashPage({super.key});


  @override
  State<SplashPage> createState() => _SplashPageState();
}


class _SplashPageState extends State<SplashPage> {
  bool _navigated = false;
  bool _languageHandled = false;


  // ✅ mesma lista do seu LanguagePage (discreto e global)
  static const List<_LangItem> _langs = <_LangItem>[
    _LangItem('en', 'English'),
    _LangItem('pt', 'Português'),
    _LangItem('es', 'Español'),
    _LangItem('fr', 'Français'),
  ];


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _go());
  }


  Future<void> _go() async {
    if (_navigated) return;


    try {
      // ✅ 0) Antes de tudo: garante idioma definido no primeiro acesso
      await _ensureLanguageChosen();


      // (mantém seu delay do splash)
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
      _replace(const AuthGate()); // ✅ mantém seu fluxo atual
    } catch (_) {
      _replace(const LoginPage());
    }
  }


  /// ✅ Primeiro acesso: se não tiver idioma salvo, abre escolha rápida (discreta)
  Future<void> _ensureLanguageChosen() async {
    if (_languageHandled) return;
    _languageHandled = true;


    try {
      final prefs = await SharedPreferences.getInstance();


      // Seu controller salva em "app_lang"
      final saved = (prefs.getString('app_lang') ?? '').trim().toLowerCase();


      // Se já tem idioma salvo, só garante aplicar e sair
      if (saved.isNotEmpty) {
        await LocaleController.instance.setLocale(saved);
        return;
      }


      // ✅ Não tem idioma salvo -> abre seletor rápido
      if (!mounted) return;


      final picked = await _showLanguagePicker();


      // Se usuário fechou sem escolher, default = en (global)
      final code = (picked ?? 'en').trim().toLowerCase();


      await LocaleController.instance.setLocale(code);


      // (redundante mas seguro) grava direto também
      await prefs.setString('app_lang', code);
    } catch (_) {
      // Se der qualquer erro aqui, mantém inglês (default global)
      try {
        await LocaleController.instance.setLocale('en');
      } catch (_) {}
    }
  }


  Future<String?> _showLanguagePicker() async {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: const Icon(Icons.language_rounded,
                          color: Color(0xFF313A5F)),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Choose your language',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF111827),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      splashRadius: 18,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'You can change it later in the Menu.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 10),
                ..._langs.map((e) {
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.circle_outlined,
                        color: Color(0xFF313A5F)),
                    title: Text(
                      e.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    onTap: () => Navigator.pop(context, e.code),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
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
                width: 170,
                height: 170,
                fit: BoxFit.contain,
              ),


              SizedBox(height: 20),


              // TEXTO
              // (mantido como estava — sem texto)


              SizedBox(height: 18),


              // LOADING
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(
                    Color(0xFF313A5F), // azul Remdy
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


class _LangItem {
  final String code;
  final String label;
  const _LangItem(this.code, this.label);
}
