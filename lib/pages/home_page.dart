import 'dart:async';


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';


import 'language_users_page.dart' as lusers; // ✅ FIX: alias único
import 'profile_page.dart';
import 'invite_page.dart';
import 'login_page.dart';
import 'premium_page.dart';
import 'menu_page.dart';
import 'language_page.dart';


import 'package:socialchat_mvp/pages/notifications_page.dart';
import 'package:socialchat_mvp/pages/faq_page.dart';
import 'package:socialchat_mvp/pages/contact_page.dart';
import 'package:socialchat_mvp/pages/terms_page.dart';
import 'package:socialchat_mvp/pages/privacy_page.dart';
import 'package:socialchat_mvp/pages/about_page.dart';


class HomePage extends StatefulWidget {
  const HomePage({super.key});


  @override
  State<HomePage> createState() => _HomePageState();
}


class _HomePageState extends State<HomePage> {
  final db = FirebaseFirestore.instance;


  // ✅ controla o Drawer (você usa pra reabrir o menu)
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();


  // ✅ FCM token
  StreamSubscription<String>? _tokenSub;


  // ✅ Auth helpers
  String? get uidOrNull => FirebaseAuth.instance.currentUser?.uid;


  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      db.collection('users').doc(uid);


  @override
  void initState() {
    super.initState();
    _initFcmTokenFlow();
  }


  @override
  void dispose() {
    _tokenSub?.cancel();
    super.dispose();
  }


  Future<void> _initFcmTokenFlow() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final uid = uidOrNull;
      if (uid == null) return;


      try {
        await FirebaseMessaging.instance.requestPermission();
      } catch (_) {}


      await _saveFcmToken(uid);


      _tokenSub?.cancel();
      _tokenSub = FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        final uid2 = uidOrNull;
        if (uid2 == null) return;
        await _saveFcmToken(uid2, tokenOverride: newToken);
      });
    });
  }


  Future<void> _saveFcmToken(String uid, {String? tokenOverride}) async {
    try {
      final token = tokenOverride ?? await FirebaseMessaging.instance.getToken();
      if (token == null || token.trim().isEmpty) return;


      await _userDoc(uid).set({
        'fcmToken': token.trim(),
        'fcmUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }


  // ✅ UI constants (padrão Remdy)
  static const _bg = Colors.white;
  static const _text = Color(0xFF111827);
  static const _muted = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);


  static const _remdyBlue = Color(0xFF313A5F);
  static const _logoBlue = Color(0xFF264E9A);


  // ✅ Premium dialog (mantém)
  void showPremiumDialog(String countryName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
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
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7CC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFFFE08A)),
                      ),
                      child: const Icon(Icons.star_rounded, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Premium',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: _text,
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
                const SizedBox(height: 10),
                Text(
                  'Para conversar com $countryName, você precisa do Premium.',
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.35,
                    color: Color(0xFF374151),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFF1F5F9)),
                  ),
                  child: const Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.public, size: 18, color: Color(0xFF2563EB)),
                          SizedBox(width: 10),
                          Expanded(child: Text('Fale com todos os países liberados')),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.flash_on, size: 18, color: Color(0xFF2563EB)),
                          SizedBox(width: 10),
                          Expanded(child: Text('Sem bloqueio por país')),
                        ],
                      ),
                      SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(Icons.support_agent, size: 18, color: Color(0xFF2563EB)),
                          SizedBox(width: 10),
                          Expanded(child: Text('Prioridade no suporte')),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: _border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Fechar',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: const LinearGradient(
                            colors: [_remdyBlue, _logoBlue],
                          ),
                        ),
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const PremiumPage()),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Ver Premium',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  // ✅ Countries
  final countries = const [
    _Country(code: 'CA', name: 'Canadá', flag: 'CA'),
    _Country(code: 'BR', name: 'Brasil', flag: 'BR'),
    _Country(code: 'US', name: 'Estados Unidos', flag: 'US'),
    _Country(code: 'FR', name: 'França', flag: 'FR'),
    _Country(code: 'ES', name: 'Espanha', flag: 'ES'),
    _Country(code: 'IT', name: 'Itália', flag: 'IT'),
  ];


  // ✅ Actions
  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;


    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }


  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfilePage()),
    );
  }


  void _openCountry({required _Country item, required bool canOpen}) {
    if (!canOpen) {
      showPremiumDialog(item.name);
      return;
    }


    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => lusers.LanguageUsersPage( // ✅ FIX: usa alias correto
          languageCode: item.code,
          languageName: item.name,
          flag: item.flag,
        ),
      ),
    );
  }


  String _flagEmoji(String code) {
    final upper = code.toUpperCase();
    if (upper.length != 2) return '🏳️';
    final int first = upper.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final int second = upper.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCodes([first, second]);
  }


  @override
  Widget build(BuildContext context) {
    final uid = uidOrNull;


    // ✅ BLOQUEIO: sem login -> manda pro LoginPage (isso já está aqui)
    if (uid == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (_) => false,
        );
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }


    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDoc(uid).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};


        final int invites = (data['invitesCount'] is int)
            ? data['invitesCount'] as int
            : ((data['invites'] is int) ? data['invites'] as int : 0);


        final int limit =
            (data['invitesGoal'] is int) ? data['invitesGoal'] as int : 5;


        final name = (data['name'] ?? 'Usuário').toString();
        final isPremium = data['isPremium'] == true;


        final userCountryName = (data['country'] ?? '').toString();


        final now = DateTime.now();
        final since =
            Timestamp.fromDate(now.subtract(const Duration(seconds: 180)));


        final userCountryCodeRaw = (data['countryCode'] ?? '').toString().trim();
        final userCountryCode =
            userCountryCodeRaw.isEmpty ? 'ca' : userCountryCodeRaw.toLowerCase();


        final onlineStream = db
            .collection('publicUsers')
            .where('lastSeenAt', isGreaterThan: since)
            .snapshots();


        bool canOpenCountry(_Country item) {
          if (isPremium) return true;


          if (userCountryCode.isNotEmpty) {
            return item.code.trim().toLowerCase() ==
                userCountryCode.trim().toLowerCase();
          }


          if (userCountryName.isNotEmpty) {
            return item.name.toLowerCase() == userCountryName.toLowerCase();
          }


          return item.code == 'BR';
        }


        final photoUrl = (data['photoUrl'] ?? '').toString();


        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: _bg,


          // ✅ AppBar: menu esquerda / logo centro / foto direita
          appBar: AppBar(
            backgroundColor: _bg,
            elevation: 0,
            centerTitle: true,
            toolbarHeight: 88,
            leading: IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: () {
                // ✅ FIX: passa TODOS os parâmetros obrigatórios do MenuPage
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MenuPage(
                      name: name,
                      photoUrl: photoUrl,
                      isPremium: isPremium,
                      invites: invites,
                      limit: limit,


                      profilePage: const ProfilePage(),
                      invitePage: InvitePage(invites: invites, limit: limit, myUid: uid),
                      premiumPage: const PremiumPage(),
                      languagePage: const LanguagePage(),
                      notificationsPage: const NotificationsPage(),
                      faqPage: const FaqPage(),
                      contactPage: const ContactPage(),
                      termsPage: const TermsPage(),
                      policyPage: const PrivacyPage(),
                      aboutPage: const AboutPage(),


                      onLogout: _logout,
                    ),
                  ),
                );
              },
            ),
            title: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Image.asset(
                'assets/remdy_icon.png',
                height: 70,
                fit: BoxFit.contain,
              ),
            ),
            iconTheme: const IconThemeData(color: _muted),
            actions: [
              GestureDetector(
                onTap: _openProfile,
                child: Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage: photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
                    child: photoUrl.isEmpty
                        ? const Icon(Icons.person, size: 18, color: _muted)
                        : null,
                  ),
                ),
              ),
            ],
          ),


          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            children: [
              Text(
                'Olá, $name',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _text,
                ),
              ),
              const SizedBox(height: 10),


              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Agora ao vivo',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _text,
                      ),
                    ),
                    const SizedBox(height: 10),


                    Row(
                      children: [
                        Text(
                          _flagEmoji(userCountryCode.isNotEmpty ? userCountryCode : 'BR'),
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            userCountryName.isNotEmpty ? userCountryName : 'Seu país',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _text,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: onlineStream,
                          builder: (context, s) {
                            final docs = s.data?.docs ?? [];
                            final myCode = userCountryCode.trim().toLowerCase();


                            final n = docs.where((doc) {
                              final data = doc.data();
                              final code = (data['countryCode'] ?? '')
                                  .toString()
                                  .trim()
                                  .toLowerCase();
                              return code.isNotEmpty && code == myCode;
                            }).length;


                            return Row(
                              children: [
                                const Icon(Icons.circle, size: 10, color: Colors.green),
                                const SizedBox(width: 6),
                                Text(
                                  '$n online',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _muted,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),


                    const SizedBox(height: 10),


                    Row(
                      children: [
                        const Text('🌍', style: TextStyle(fontSize: 16)),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Mundo',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _text,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: onlineStream,
                          builder: (context, s) {
                            final docs = s.data?.docs ?? [];
                            final myCode = userCountryCode.trim().toLowerCase();


                            final n = docs.where((doc) {
                              final data = doc.data();
                              final code = (data['countryCode'] ?? '')
                                  .toString()
                                  .trim()
                                  .toLowerCase();
                              return code.isNotEmpty && code != myCode;
                            }).length;


                            return Row(
                              children: [
                                const Icon(Icons.circle, size: 10, color: Colors.green),
                                const SizedBox(width: 6),
                                Text(
                                  '$n online',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _muted,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),


              const SizedBox(height: 16),


              const Text(
                'Escolha um país',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _text,
                ),
              ),
              const SizedBox(height: 12),


              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: countries.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.88,
                ),
                itemBuilder: (context, i) {
                  final item = countries[i];
                  final canOpen = canOpenCountry(item);


                  return InkWell(
                    onTap: () => _openCountry(item: item, canOpen: canOpen),
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Opacity(
                        opacity: canOpen ? 1.0 : 0.45,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _flagEmoji(item.flag),
                              style: const TextStyle(fontSize: 30),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item.name,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF111827),
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (!canOpen) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: const Text(
                                  'Premium',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}


class _Country {
  final String code;
  final String name;
  final String flag;


  const _Country({
    required this.code,
    required this.name,
    required this.flag,
  });
}
