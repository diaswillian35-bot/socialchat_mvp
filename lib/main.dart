import 'dart:async';


import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'l10n/app_texts.dart';
import 'pages/auth_gate.dart';
import 'pages/join_group_page.dart';
import 'services/locale_controller.dart';
import 'services/push_service.dart';
import 'pages/event_deep_link_page.dart';
import 'pages/portal_qr_login_approve_page.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();


  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );


  await LocaleController.instance.load();

final deviceLocale = WidgetsBinding.instance.platformDispatcher.locale;

await AppTexts.load(deviceLocale);




  runApp(const MyApp());
}


class MyApp extends StatefulWidget {
  const MyApp({super.key});


  @override
  State<MyApp> createState() => _MyAppState();
}


class _MyAppState extends State<MyApp> {
  bool _openingGroupInvite = false;
String _lastGroupInviteCode = '';

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;


  Uri? _pendingUri;
  bool _didTryProcessPending = false;


  @override
  void initState() {
    super.initState();
    print('DEBUG main: initState MyApp');
    _setupDeepLinks();
  }


  Future<void> _setupDeepLinks() async {
    print('DEBUG main: entrou _setupDeepLinks');


    try {
      final initialUri = await _appLinks.getInitialLink();
      print('DEBUG main: initialUri = $initialUri');


      if (initialUri != null) {
        _pendingUri = initialUri;
        _tryProcessPendingLink();
      }
    } catch (e) {
      print('DEBUG main: erro getInitialLink = $e');
    }


    _linkSub = _appLinks.uriLinkStream.listen(
      (uri) {
        print('DEBUG main: uriLinkStream uri = $uri');
        _pendingUri = uri;
        _tryProcessPendingLink();
      },
      onError: (e) {
        print('DEBUG main: erro uriLinkStream = $e');
      },
    );
  }


  void _tryProcessPendingLink() {
    if (_didTryProcessPending && _pendingUri == null) return;


    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uri = _pendingUri;
      final nav = PushService.navKey.currentState;


      if (uri == null || nav == null) {
        Future.delayed(
          const Duration(milliseconds: 500),
          _tryProcessPendingLink,
        );
        return;
      }


      _didTryProcessPending = true;
      _pendingUri = null;
      _handleIncomingLink(uri);
    });
  }


  int _rewardDaysForInviteCount(int count) {
    if (count >= 100) return 90;
    if (count >= 50) return 60;
    if (count >= 20) return 30;
    if (count >= 10) return 7;
    if (count >= 3) return 1;
    return 0;
  }


  int _rewardLevelForInviteCount(int count) {
    if (count >= 100) return 100;
    if (count >= 50) return 50;
    if (count >= 20) return 20;
    if (count >= 10) return 10;
    if (count >= 3) return 3;
    return 0;
  }


  Future<void> _saveInviteRef(String ref) async {
    print('DEBUG main: entrou _saveInviteRef com ref = $ref');


    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_invite_ref', ref);


    final saved = prefs.getString('pending_invite_ref') ?? '';
    print('DEBUG main: pending_invite_ref salvo = $saved');


    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print('DEBUG main: user null, saindo mas ref ficou salvo');
      return;
    }


    final firestore = FirebaseFirestore.instance;


    final inviterQuery = await firestore
        .collection('users')
        .where('inviteCode', isEqualTo: ref)
        .limit(1)
        .get();


    print('DEBUG main: inviterQuery docs = ${inviterQuery.docs.length}');


    if (inviterQuery.docs.isEmpty) return;


    final inviterUid = inviterQuery.docs.first.id;
    if (user.uid == inviterUid) return;


    final userRef = firestore.collection('users').doc(user.uid);
    final inviterRef = firestore.collection('users').doc(inviterUid);


    await firestore.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      final inviterSnap = await tx.get(inviterRef);


      final userData = userSnap.data() ?? {};
      final inviterData = inviterSnap.data() ?? {};


      final currentInvitedBy =
          (userData['invitedBy'] ?? '').toString().trim();
      if (currentInvitedBy.isNotEmpty) return;


      final currentInvites = (inviterData['invitesCount'] is num)
          ? (inviterData['invitesCount'] as num).toInt()
          : 0;


      final currentRewardLevel = (inviterData['inviteRewardLevel'] is num)
          ? (inviterData['inviteRewardLevel'] as num).toInt()
          : 0;


      final newInvitesCount = currentInvites + 1;
      final nextRewardLevel = _rewardLevelForInviteCount(newInvitesCount);
      final rewardDays = _rewardDaysForInviteCount(newInvitesCount);


      tx.set(userRef, {
        'invitedBy': inviterUid,
        'invitedByCode': ref,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));


      final Map<String, dynamic> inviterPatch = {
        'invitesCount': newInvitesCount,
        'updatedAt': FieldValue.serverTimestamp(),
      };


      if (nextRewardLevel > currentRewardLevel && rewardDays > 0) {
        DateTime baseDate = DateTime.now();


        final premiumUntilRaw = inviterData['premiumUntil'];
        if (premiumUntilRaw is Timestamp) {
          final existing = premiumUntilRaw.toDate();
          if (existing.isAfter(baseDate)) {
            baseDate = existing;
          }
        }


        final newPremiumUntil = baseDate.add(Duration(days: rewardDays));


        inviterPatch['premiumType'] = 'trial';
        inviterPatch['premiumUntil'] = Timestamp.fromDate(newPremiumUntil);
        inviterPatch['inviteRewardLevel'] = nextRewardLevel;


        if (nextRewardLevel >= 100) {
          inviterPatch['isAmbassador'] = true;
        }
      }


      tx.set(inviterRef, inviterPatch, SetOptions(merge: true));
    });
  }


  Future<void> _handleIncomingLink(Uri uri) async {
  print('DEBUG main: _handleIncomingLink uri = $uri');


  final nav = PushService.navKey.currentState;
  if (nav == null) return;


  final segments = uri.pathSegments;
  print('DEBUG main: segments = $segments');
  print('DEBUG main: query ref = ${uri.queryParameters['ref']}');


  // 🔹 GRUPO: /g/CODIGO
  if (segments.length >= 2 && segments.first.toLowerCase() == 'g') {
    final code = segments[1].trim();
    if (code.isEmpty) return;
    
if (_openingGroupInvite &&
    _lastGroupInviteCode == code) {
  return;
}

_openingGroupInvite = true;
_lastGroupInviteCode = code;



Future.delayed(const Duration(milliseconds: 700), () {
  final nav = PushService.navKey.currentState;
  
if (nav == null) {
  _openingGroupInvite = false;
  return;
}


  nav.pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => JoinGroupPage(inviteCode: code),
    ),
    (route) => false,
  );
  _openingGroupInvite = false;
});




    return;
  }
if (segments.length >= 2 && segments.first.toLowerCase() == 'e') {
  final eventId = segments[1].trim();

  if (eventId.isNotEmpty) {
    nav.pushReplacement(
      MaterialPageRoute(
        builder: (_) => EventDeepLinkPage(eventId: eventId),
      ),
    );
  }

  return;
}

if (segments.length >= 2 &&
    segments.first.toLowerCase() == 'portal-login') {
  final sessionId = segments[1].trim();

  if (sessionId.isNotEmpty) {
    nav.push(
      MaterialPageRoute(
        builder: (_) => PortalQrLoginApprovePage(sessionId: sessionId),
      ),
    );
  }

  return;
}


  // 🔹 CONVITE GERAL: /invite?ref=CODE
  if (segments.isNotEmpty && segments.first.toLowerCase() == 'invite') {
    final ref = uri.queryParameters['ref']?.trim() ?? '';
    print('DEBUG main: ref capturado = $ref');
    final groupCode = uri.queryParameters['code'] ?? '';

if (groupCode.trim().isNotEmpty) {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('pending_group_code', groupCode.trim());

  print('DEBUG group invite saved = $groupCode');
}



    if (ref.isEmpty) return;


    // copia pro clipboard (opcional)
    Clipboard.setData(ClipboardData(text: ref));


    // 🔥 AGORA COM AWAIT (ESSENCIAL)
    await _saveInviteRef(ref);


    // 🔍 verifica se salvou mesmo
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('pending_invite_ref') ?? '';


    print('DEBUG main: confirm saved = $saved');


    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(nav.context).showSnackBar(
        SnackBar(
          content: Text('Convite salvo: $saved'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(12),
        ),
      );
    });


    return;
  }
}



  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleController.instance,
      builder: (context, _) {
       return MaterialApp(
  key: ValueKey(LocaleController.instance.locale.toString()),

          debugShowCheckedModeBanner: false,
          navigatorKey: PushService.navKey,
          locale: LocaleController.instance.locale,
          supportedLocales: LocaleController.supportedLocales,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: ThemeData(
            useMaterial3: true,
            primaryColor: const Color(0xFF313A5F),
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF313A5F),
            ).copyWith(
              primary: const Color(0xFF313A5F),
              secondary: const Color(0xFF313A5F),
              tertiary: const Color(0xFF313A5F),
            ),
            snackBarTheme: const SnackBarThemeData(
              backgroundColor: Color(0xFF313A5F),
              contentTextStyle: TextStyle(
                color: Colors.white,
              ),
            ),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.white,
              foregroundColor: Color(0xFF111827),
              elevation: 0,
              centerTitle: false,
            ),
            bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: Colors.white,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Colors.white,
            ),
            popupMenuTheme: const PopupMenuThemeData(
              color: Colors.white,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF313A5F),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          home: const AuthGate(),
        );
      },
    );
  }
}
