import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/app_texts.dart';
import 'pages/auth_gate.dart';
import 'pages/join_group_page.dart';
import 'services/app_orientation.dart';
import 'services/firebase_bootstrap.dart';
import 'services/group_join_service.dart';
import 'services/locale_controller.dart';
import 'services/photo_picker_config.dart';
import 'services/push_service.dart';
import 'services/remdy_link_router.dart';
import 'services/safe_remdy_navigation.dart';
import 'services/age_access_service.dart';
import 'pages/event_deep_link_page.dart';
import 'pages/portal_qr_login_approve_page.dart';
import 'services/event_deep_link_service.dart';
import 'services/invite_premium_service.dart';
import 'services/share_in_service.dart';
import 'services/share_extension_session_service.dart';
import 'widgets/keyboard_dismiss.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'utils/event_timezone.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Separate isolate: own Firebase registry; still must be idempotent.
  await ensureFirebaseInitialized();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  configurePhotoPicker();

  await ensureFirebaseInitialized();

  tzdata.initializeTimeZones();
  EventTimezone.markReady();

  // Vertical-only em celulares (antes de runApp; não altera o bootstrap Firebase).
  await AppOrientation.lockToPortraitUp();

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  await PushService.init();

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

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
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
    WidgetsBinding.instance.addObserver(this);
    RemdyLinkRouter.handler = _handleIncomingLink;
    _setupDeepLinks();
    // Share-in nativo (Android ACTION_SEND / iOS Share Extension).
    ShareInService.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (identical(RemdyLinkRouter.handler, _handleIncomingLink)) {
      RemdyLinkRouter.handler = null;
    }
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ShareInService.onAppResumed();
      ShareExtensionSessionService.ensureSession();
    }
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

    try {
      final result = await InvitePremiumService.applyInviteCode(ref);
      print('DEBUG main: applyInviteCode result = $result');
      if (result['applied'] == true || result['alreadyApplied'] == true) {
        await prefs.remove('pending_invite_ref');
      }
    } catch (e) {
      print('DEBUG main: applyInviteCode erro = $e');
    }
  }

  Future<void> _openGroupInviteByCode(String rawCode) async {
    final code = GroupJoinService.normalizeInviteCode(rawCode);
    if (code.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_group_code', code);

    // O convite permanece pendente e só será processado pelo AuthGate após 18+.
    if (!await AgeAccessService.currentUserIsVerified()) return;

    if (_openingGroupInvite && _lastGroupInviteCode == code) {
      return;
    }

    _openingGroupInvite = true;
    _lastGroupInviteCode = code;

    Future.delayed(const Duration(milliseconds: 700), () async {
      final nav = PushService.navKey.currentState;

      if (nav == null) {
        _openingGroupInvite = false;
        return;
      }

      // Sempre deixa MainShell sob JoinGroupPage — Voltar não fecha o app.
      await SafeRemdyNavigation.openOverShell(
        nav: nav,
        shellIndex: 2,
        page: JoinGroupPage(inviteCode: code),
      );
      _openingGroupInvite = false;
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
      await _openGroupInviteByCode(code);
      return;
    }

    // 🔹 GRUPO (legado): /group?code=CODIGO
    if (segments.isNotEmpty && segments.first.toLowerCase() == 'group') {
      final code = uri.queryParameters['code']?.trim() ?? '';
      if (code.isNotEmpty) {
        await _openGroupInviteByCode(code);
      }
      return;
    }

    if (segments.length >= 2 &&
        (segments.first.toLowerCase() == 'e' ||
            segments.first.toLowerCase() == 'events' ||
            segments.first.toLowerCase() == 'event')) {
      final eventId = segments[1].trim();

      if (eventId.isNotEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          await EventDeepLinkService.savePendingEventId(eventId);
          return;
        }

        final ctx = PushService.navKey.currentContext;
        if (ctx != null) {
          await EventDeepLinkService.openEventById(
            ctx,
            eventId: eventId,
          );
        } else {
          nav.push(
            MaterialPageRoute(
              builder: (_) => EventDeepLinkPage(eventId: eventId),
            ),
          );
        }
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

    // 🔹 CONVITE GERAL: /invite?ref=CODE  (também aceita ?code= para grupo)
    if (segments.isNotEmpty && segments.first.toLowerCase() == 'invite') {
      final ref = uri.queryParameters['ref']?.trim() ?? '';
      print('DEBUG main: ref capturado = $ref');
      final groupCode = uri.queryParameters['code'] ?? '';

      if (groupCode.trim().isNotEmpty) {
        await _openGroupInviteByCode(groupCode);
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
            // Remdy navy — ColorScheme.light (não fromSeed) evita surface/containers
            // lilás/rosa gerados pelo seed Material 3.
            primaryColor: const Color(0xFF313A5F),
            scaffoldBackgroundColor: Colors.white,
            canvasColor: Colors.white,
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF313A5F),
              onPrimary: Colors.white,
              primaryContainer: Color(0xFFE8EAF0),
              onPrimaryContainer: Color(0xFF313A5F),
              secondary: Color(0xFF313A5F),
              onSecondary: Colors.white,
              secondaryContainer: Color(0xFFE8EAF0),
              onSecondaryContainer: Color(0xFF313A5F),
              tertiary: Color(0xFF313A5F),
              onTertiary: Colors.white,
              tertiaryContainer: Color(0xFFE8EAF0),
              onTertiaryContainer: Color(0xFF313A5F),
              error: Color(0xFFB91C1C),
              onError: Colors.white,
              errorContainer: Color(0xFFFEE2E2),
              onErrorContainer: Color(0xFF7F1D1D),
              surface: Colors.white,
              onSurface: Color(0xFF111827),
              onSurfaceVariant: Color(0xFF6B7280),
              surfaceContainerHighest: Color(0xFFF1F5F9),
              outline: Color(0xFFE5E7EB),
              outlineVariant: Color(0xFFE5E7EB),
              shadow: Color(0xFF111827),
              scrim: Color(0xFF111827),
              inverseSurface: Color(0xFF111827),
              onInverseSurface: Colors.white,
              inversePrimary: Color(0xFFAEB6D4),
            ),
            cardTheme: const CardThemeData(
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
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
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              centerTitle: false,
            ),
            bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
            ),
            dialogTheme: const DialogThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
            ),
            popupMenuTheme: const PopupMenuThemeData(
              color: Colors.white,
              surfaceTintColor: Colors.transparent,
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(
              backgroundColor: Color(0xFF313A5F),
              foregroundColor: Colors.white,
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF313A5F),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE5E7EB),
                disabledForegroundColor: const Color(0xFF9CA3AF),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF313A5F),
                side: const BorderSide(color: Color(0xFF313A5F)),
                disabledForegroundColor: const Color(0xFF9CA3AF),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF313A5F),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            progressIndicatorTheme: const ProgressIndicatorThemeData(
              color: Color(0xFF313A5F),
            ),
          ),
          home: const AuthGate(),
          builder: (context, child) {
            return KeyboardLifecycleGuard(
              child: IosNumericKeyboardDoneBar(
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
        );
      },
    );
  }
}
