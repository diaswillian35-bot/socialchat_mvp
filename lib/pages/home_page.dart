import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../pages/system_inbox_page.dart';
import 'remi_chat_page.dart';
import 'remi_intro_page.dart';

import 'language_users_page.dart' as lusers;
import 'profile_page.dart';
import 'invite_page.dart';
import 'login_page.dart';
import 'premium_page.dart';
import 'menu_page.dart';
import 'language_page.dart';
import 'edit_profile_page.dart';
import '../l10n/app_texts.dart';

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

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  StreamSubscription<String>? _tokenSub;

  bool _syncedPublicOnce = false;
  Timer? _presenceTimer;
  bool _presenceStarted = false;
  String _localeLoaded = '';

  String? get uidOrNull => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      db.collection('users').doc(uid);

  DocumentReference<Map<String, dynamic>> _publicDoc(String uid) =>
      db.collection('publicUsers').doc(uid);
      


      Stream<int> _systemInboxUnreadCount(String uid) {
  return db
      .collection('users')
      .doc(uid)
      .collection('systemInbox')
      .where('isRead', isEqualTo: false)
      .snapshots()
      .map((snap) => snap.docs.length);
}


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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final locale = Localizations.localeOf(context);
    final nextCode = '${locale.languageCode}_${locale.countryCode ?? ''}';

    if (_localeLoaded == nextCode) return;
    _localeLoaded = nextCode;

    AppTexts.load(locale).then((_) {
      if (mounted) setState(() {});
    });
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
      _tokenSub =
          FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
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

  static const _bg = Colors.white;
  static const _text = Color(0xFF111827);
  static const _muted = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);

  static const _remdyBlue = Color(0xFF313A5F);
  static const _logoBlue = Color(0xFF264E9A);

  String _countryName(String code) {
    final t = AppTexts.current;

    switch (code.toLowerCase()) {
      case 'br':
        return t.get('country_brazil');
      case 'ca':
        return t.get('country_canada');
      case 'pt':
        return t.get('country_portugal');
      default:
        return t.get('your_country');
    }
  }

  List<_Country> get countries => [
        _Country(
          code: 'BR',
          name: AppTexts.current.get('country_brazil'),
          flag: 'BR',
        ),
        _Country(
          code: 'CA',
          name: AppTexts.current.get('country_canada'),
          flag: 'CA',
        ),
        _Country(
          code: 'PT',
          name: AppTexts.current.get('country_portugal'),
          flag: 'PT',
        ),
      ];

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
                    Expanded(
                      child: Text(
                        AppTexts.current.get('premium'),
                        style: const TextStyle(
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
                  '${AppTexts.current.get('premium_country_message_prefix')} $countryName, ${AppTexts.current.get('premium_country_message_suffix')}',
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
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.public,
                              size: 18, color: Color(0xFF2563EB)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(AppTexts.current
                                .get('premium_benefit_all_countries')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.flash_on,
                              size: 18, color: Color(0xFF2563EB)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(AppTexts.current
                                .get('premium_benefit_no_country_block')),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.support_agent,
                              size: 18, color: Color(0xFF2563EB)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(AppTexts.current
                                .get('premium_benefit_priority_support')),
                          ),
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
                          'Close',
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
                              MaterialPageRoute(
                                builder: (_) => const PremiumPage(),
                              ),
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
                          child: Text(
                            AppTexts.current.get('see_premium'),
                            style: const TextStyle(
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
        builder: (_) => lusers.LanguageUsersPage(
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

  Future<void> _ensurePublicCountryCodeOnce({
    required String uid,
    required String homeCode,
    required String name,
    required String photoUrl,
  }) async {
    if (_syncedPublicOnce) return;
    _syncedPublicOnce = true;

    try {
      await _publicDoc(uid).set({
        'uid': uid,
        'countryCode': homeCode,
        'name': name,
        'photoUrl': photoUrl,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final uid = uidOrNull;

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
      
if (!snap.hasData) {
  return const Scaffold(
    body: Center(child: CircularProgressIndicator()),
  );
}


        final data = snap.data!.data() ?? {};

        final homeCode = (data['homeCountryCode'] ?? '')
            .toString()
            .trim()
            .toLowerCase();

        if (homeCode.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const EditProfilePage()),
            );
          });
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final nameRaw = (data['name'] ?? '').toString().trim();
        final name = nameRaw.isEmpty ? t.get('user') : nameRaw;

        final now = DateTime.now();
        final premiumUntil = (data['premiumUntil'] as Timestamp?)?.toDate();
      final isMaster = data['isMaster'] == true;

final isPremiumActive =
    isMaster ||
    (data['isPremium'] == true) ||
    (premiumUntil != null && premiumUntil.isAfter(now));


        final int invites = (data['invitesCount'] is int)
            ? data['invitesCount'] as int
            : ((data['invites'] is int) ? data['invites'] as int : 0);

        final int limit =
            (data['invitesGoal'] is int) ? data['invitesGoal'] as int : 5;

        final photoUrl = (data['photoUrl'] ?? '').toString();

        final inviteCodeRaw = (data['inviteCode'] ?? '').toString().trim();
        final inviteCode = inviteCodeRaw.isEmpty ? uid : inviteCodeRaw;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ensurePublicCountryCodeOnce(
            uid: uid,
            homeCode: homeCode,
            name: name,
            photoUrl: photoUrl,
          );
        });

        final userCountryName = _countryName(homeCode);

  final countriesStream = db
    .collection('configCountries')
    .where('enabled', isEqualTo: true)
    .snapshots();



        final since =
            Timestamp.fromDate(now.subtract(const Duration(seconds: 30)));

        final onlineStream = db
            .collection('publicUsers')
            .where('lastSeenAt', isGreaterThan: since)
            .snapshots();

        bool canOpenCountry(_Country item) {
          if (isPremiumActive) return true;
          return item.code.trim().toLowerCase() == homeCode;
        }

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _bg,
            elevation: 0,
            centerTitle: true,
            toolbarHeight: 88,
      leading: IconButton(
  icon: StreamBuilder<int>(
    stream: _systemInboxUnreadCount(uid),
    builder: (context, snap) {
      final unread = snap.data ?? 0;

      return Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.menu_rounded),
          if (unread > 0)
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      );
    },
  ),
  onPressed: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MenuPage(
          name: name,
          photoUrl: photoUrl,
          isPremium: isPremiumActive,
          invites: invites,
          limit: limit,
          profilePage: const ProfilePage(),
          invitePage: InvitePage(
            invites: invites,
            limit: limit,
            myUid: uid,
            inviteCode: inviteCode,
          ),
          premiumPage: const PremiumPage(),
          languagePage: const LanguagePage(),
          notificationsPage: const NotificationsPage(),
          systemInboxPage: const SystemInboxPage(),
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
             Padding(
  padding: const EdgeInsets.only(right: 8),
  child: InkWell(
    borderRadius: BorderRadius.circular(999),
    onTap: () {
    Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => const RemiChatPage(
      language: 'English',
      goal: 'Daily Life',
      lesson: 'Small Talk',
    ),
  ),
);

    },
    child: Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _border),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.forum_rounded,
            size: 17,
            color: _remdyBlue,
          ),
          SizedBox(width: 6),
          Text(
            'Remi',
            style: TextStyle(
              color: _remdyBlue,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ],
      ),
    ),
  ),
),
 
              GestureDetector(
                onTap: _openProfile,
                child: Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.grey.shade200,
                    backgroundImage:
                        photoUrl.isNotEmpty ? NetworkImage(photoUrl) : null,
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
                '${t.get('hello')}, $name',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _text,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.get('live_now'),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _text,
                      ),
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Text(_flagEmoji(homeCode),
                            style: const TextStyle(fontSize: 16)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            userCountryName,
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

                            final n = docs.where((doc) {
                              final d = doc.data();
                              final code = (d['countryCode'] ?? '')
                                  .toString()
                                  .trim()
                                  .toLowerCase();
                              final isOnline = d['isOnline'] == true;
                              final hasUid =
                                  (d['uid'] ?? '').toString().trim().isNotEmpty;

                              return hasUid &&
                                  isOnline &&
                                  code.isNotEmpty &&
                                  code == homeCode;
                            }).length;

                            return Row(
                              children: [
                                const Icon(Icons.circle,
                                    size: 10, color: Colors.green),
                                const SizedBox(width: 6),
                                Text(
                                  '$n ${t.get('online')}',
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
                        Expanded(
                          child: Text(
                            isPremiumActive
                                ? t.get('world')
                                : t.get('world_premium'),
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

                            final world = docs.where((doc) {
                              final d = doc.data();
                              final code = (d['countryCode'] ?? '')
                                  .toString()
                                  .trim()
                                  .toLowerCase();
                              final isOnline = d['isOnline'] == true;
                              final hasUid =
                                  (d['uid'] ?? '').toString().trim().isNotEmpty;

                              return hasUid &&
                                  isOnline &&
                                  code.isNotEmpty &&
                                  code != homeCode;
                            }).length;

                            return Row(
                              children: [
                                const Icon(Icons.circle,
                                    size: 10, color: Colors.green),
                                const SizedBox(width: 6),
                                Text(
                                  '$world ${t.get('online')}',
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
              Text(
                t.get('choose_country'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: _text,
                ),
              ),
              const SizedBox(height: 12),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
  stream: countriesStream,
  builder: (context, countrySnap) {
   
if (countrySnap.connectionState == ConnectionState.waiting &&
    !countrySnap.hasData) {
  return const Center(child: CircularProgressIndicator());
}


    if (countrySnap.hasError) {
      return Center(child: Text('Erro países: ${countrySnap.error}'));
    }

    final countryDocs = countrySnap.data?.docs ?? [];

final sortedCountries = countryDocs.map((doc) {
  final d = doc.data();

  final code = (d['code'] ?? doc.id).toString().trim().toUpperCase();

return _Country(
  code: code,
  name: _countryName(code),
  flag: (d['flag'] ?? '').toString().trim(),

    premiumOnly: d['premiumOnly'] == true,
    betaOnly: d['betaOnly'] == true,
    order: d['order'] is num ? (d['order'] as num).toInt() : 999999,
  );
}).where((c) {
  return c.code.isNotEmpty && c.name.isNotEmpty;
}).toList();

sortedCountries.sort((a, b) {
  final aIsMine = a.code.toLowerCase() == homeCode;
  final bIsMine = b.code.toLowerCase() == homeCode;

  if (aIsMine != bIsMine) return aIsMine ? -1 : 1;

  return a.order.compareTo(b.order);
});



    if (sortedCountries.isEmpty) {
      return const Center(
        child: Text('Nenhum país disponível'),
      );
    }

    bool canOpenCountry(_Country item) {
      if (item.premiumOnly && !isPremiumActive) return false;
      if (isPremiumActive) return true;
      return item.code.trim().toLowerCase() == homeCode;
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sortedCountries.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.88,
      ),
      itemBuilder: (context, i) {
        final item = sortedCountries[i];
final canOpen = isPremiumActive ||
    item.code.trim().toLowerCase() == homeCode;


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
                    item.flag.isNotEmpty ? item.flag : _flagEmoji(item.code),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        t.get('premium'),
                        style: const TextStyle(
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
  final bool premiumOnly;
  final bool betaOnly;
  final int order;

  const _Country({
    required this.code,
    required this.name,
    required this.flag,
    this.premiumOnly = false,
    this.betaOnly = false,
    this.order = 999999,
  });
}