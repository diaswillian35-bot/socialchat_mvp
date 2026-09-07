import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'login_page.dart';
import 'splash_page.dart';
import 'main_shell_page.dart';
import 'email_verification_page.dart';
import '../l10n/app_texts.dart';
import '../services/push_service.dart';
import '../services/event_deep_link_service.dart';
import '../services/invite_premium_service.dart';
import '../services/share_in_service.dart';
import '../services/share_extension_session_service.dart';
import '../services/share_extension_incoming_service.dart';
import '../services/presence_service.dart';
import '../services/remdy_deep_link_parser.dart';
import '../services/safe_remdy_navigation.dart';
import 'join_group_page.dart';
import 'age_verification_page.dart';
import '../services/age_verification.dart';
import '../services/google_sign_in_service.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static bool _applyingPendingGroup = false;
  static bool _applyingPendingInvite = false;

  /// Evita remount do MainShell a cada rebuild do FutureBuilder.
  String? _cachedUid;
  Future<DocumentSnapshot<Map<String, dynamic>>>? _userDocFuture;

  Future<DocumentSnapshot<Map<String, dynamic>>> _userDoc(String uid) {
    if (_cachedUid == uid && _userDocFuture != null) {
      return _userDocFuture!;
    }
    _cachedUid = uid;
    _userDocFuture =
        FirebaseFirestore.instance.collection('users').doc(uid).get();
    return _userDocFuture!;
  }

  Future<void> _applyPendingInviteIfAny(User user) async {
    if (_applyingPendingInvite) return;
    _applyingPendingInvite = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final ref = prefs.getString('pending_invite_ref') ?? '';

      print('DEBUG invite: entrou _applyPendingInviteIfAny');
      print('DEBUG invite: pendingRef = $ref');

      if (ref.isEmpty) return;

      final result = await InvitePremiumService.applyInviteCode(ref);
      print('DEBUG invite: applyInviteCode result = $result');

      if (result['applied'] == true || result['alreadyApplied'] == true) {
        await prefs.remove('pending_invite_ref');
        print('DEBUG invite: pending_invite_ref removido');
      }

      final ctx = PushService.navKey.currentContext;
      if (ctx == null) return;

      final t = AppTexts.current;
      String snackMessage;
      if (result['alreadyApplied'] == true) {
        snackMessage = t.get('invite_already_applied');
      } else if (result['applied'] == true && result['rewardGranted'] == true) {
        final days = result['rewardDays'];
        snackMessage = t
            .get('invite_applied_with_reward')
            .replaceAll('{ref}', ref)
            .replaceAll('{days}', '$days');
      } else if (result['applied'] == true) {
        snackMessage = t.get('invite_applied').replaceAll('{ref}', ref);
      } else {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(snackMessage),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      });
    } catch (e) {
      print('DEBUG invite: applyInviteCode erro = $e');
    } finally {
      _applyingPendingInvite = false;
    }
  }

  /// Reabre só a prévia do grupo após login/idade.
  /// Nunca chama join automaticamente — o pedido só nasce no toque em
  /// “Solicitar entrada” / Entrar na [JoinGroupPage].
  Future<void> _applyPendingGroupIfAny(User user) async {
    if (_applyingPendingGroup) return;
    _applyingPendingGroup = true;

    try {
      final prefs = await SharedPreferences.getInstance();
      final rawCode = prefs.getString('pending_group_code') ?? '';
      final code = RemdyDeepLinkParser.normalizeGroupCode(rawCode);

      print('DEBUG group: pending code = $code');

      if (code.isEmpty) {
        if (rawCode.isNotEmpty) {
          await prefs.remove('pending_group_code');
        }
        return;
      }

      // Consome a pendência antes de navegar (evita reentrada / auto-join).
      await prefs.remove('pending_group_code');

      final nav = PushService.navKey.currentState;
      if (nav == null) {
        // Sem navigator ainda: reinsere para a próxima tentativa pós-shell.
        await prefs.setString('pending_group_code', code);
        return;
      }

      await SafeRemdyNavigation.openOverShell(
        nav: nav,
        shellIndex: 2,
        page: JoinGroupPage(inviteCode: code),
      );

      print('DEBUG group: pending opened JoinGroupPage (preview only)');
    } finally {
      _applyingPendingGroup = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SplashPage();
        }

        final user = snap.data;
        if (user == null) {
          _cachedUid = null;
          _userDocFuture = null;
          return const LoginPage();
        }

        if (authRequiresEmailVerification(user)) {
          return const EmailVerificationPage();
        }
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: _userDoc(user.uid),
          builder: (context, userSnap) {
            if (userSnap.connectionState != ConnectionState.done) {
              return const SplashPage();
            }
            if (!AgeVerification.isVerified(userSnap.data?.data())) {
              return const AgeVerificationPage();
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              // Garante writer mesmo se MainShell ainda não montou.
              PresenceService.instance.start();
              _applyPendingInviteIfAny(user);
              _applyPendingGroupIfAny(user);
              EventDeepLinkService.applyPendingIfAny();
              ShareInService.applyPendingIfAny();
              ShareInService.pollNativePending();
              ShareExtensionSessionService.ensureSession();
              ShareExtensionIncomingService.consumePendingJobs();
            });
            return const MainShell();
          },
        );
      },
    );
  }
}
