import 'dart:async';


import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'l10n/app_texts.dart';
import 'pages/auth_gate.dart';
import 'pages/join_group_page.dart';
import 'services/locale_controller.dart';
import 'services/push_service.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();


  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );


  await LocaleController.instance.load();
  await AppTexts.load(LocaleController.instance.locale);


  runApp(const MyApp());
}


class MyApp extends StatefulWidget {
  const MyApp({super.key});


  @override
  State<MyApp> createState() => _MyAppState();
}


class _MyAppState extends State<MyApp> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;
Uri? _pendingUri;
bool _didTryProcessPending = false;


  @override
  void initState() {
    super.initState();
    _setupDeepLinks();
  }


Future<void> _setupDeepLinks() async {
  try {
    final initialUri = await _appLinks.getInitialLink();
    if (initialUri != null) {
      _pendingUri = initialUri;
      _tryProcessPendingLink();
    }
  } catch (_) {}


  _linkSub = _appLinks.uriLinkStream.listen((uri) {
    _pendingUri = uri;
    _tryProcessPendingLink();
  });
}

void _tryProcessPendingLink() {
  if (_didTryProcessPending && _pendingUri == null) return;


  WidgetsBinding.instance.addPostFrameCallback((_) {
    final uri = _pendingUri;
    final nav = PushService.navKey.currentState;


    if (uri == null || nav == null) {
      Future.delayed(const Duration(milliseconds: 500), _tryProcessPendingLink);
      return;
    }


    _didTryProcessPending = true;
    _pendingUri = null;
    _handleIncomingLink(uri);
  });
}


void _handleIncomingLink(Uri uri) {
  final nav = PushService.navKey.currentState;
  if (nav == null) return;


  final segments = uri.pathSegments;


  // 🔹 GRUPO: /g/CODIGO
  // 🔹 CONVITE GERAL: /invite?ref=UID
if (segments.isNotEmpty && segments.first.toLowerCase() == 'invite') {
  final ref = uri.queryParameters['ref']?.trim() ?? '';
  if (ref.isEmpty) return;


  Clipboard.setData(ClipboardData(text: ref));


  WidgetsBinding.instance.addPostFrameCallback((_) {
    ScaffoldMessenger.of(nav.context).showSnackBar(
      SnackBar(
        content: Text('Convite detectado: $ref'),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
      ),
    );
  });


  return;
}





  // ✅ convite geral: /invite?ref=UID
  if (segments.isNotEmpty && segments.first.toLowerCase() == 'invite') {
    final ref = uri.queryParameters['ref']?.trim() ?? '';
    if (ref.isEmpty) return;


    Clipboard.setData(ClipboardData(text: ref));


    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(nav.context).showSnackBar(
        SnackBar(
          content: Text('Convite detectado: $ref'),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(12),
        ),
      );
    });
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
