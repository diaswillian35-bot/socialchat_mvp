import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';


import 'login_page.dart';
import 'splash_page.dart';
import 'main_shell_page.dart';
import 'email_verification_page.dart';
import '../l10n/app_texts.dart';
import '../services/group_join_service.dart';
import '../services/push_service.dart';
import '../services/event_deep_link_service.dart';
import '../services/invite_premium_service.dart';
import '../services/share_in_service.dart';
import '../services/share_extension_session_service.dart';
import 'group_chat_page.dart';


class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  static bool _applyingPendingGroup = false;
  static bool _applyingPendingInvite = false;

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
        snackMessage =
            t.get('invite_applied').replaceAll('{ref}', ref);
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


Future<void> _applyPendingGroupIfAny(User user) async {
  if (_applyingPendingGroup) return;
  _applyingPendingGroup = true;

  try {
  final prefs = await SharedPreferences.getInstance();
  final rawCode = prefs.getString('pending_group_code') ?? '';
  final code = GroupJoinService.normalizeInviteCode(rawCode);

  print('DEBUG group: pending code = $code');

  if (code.isEmpty) {
    if (rawCode.isNotEmpty) {
      await prefs.remove('pending_group_code');
    }
    return;
  }

  final result = await GroupJoinService.joinByInviteCode(
    inviteCode: code,
    uid: user.uid,
  );

  // Limpa após processamento concluído ou erro definitivo.
  await prefs.remove('pending_group_code');

  final ctx = PushService.navKey.currentContext;
  if (ctx == null) return;

  String message;
  try {
    final t = AppTexts.current;
    if (result.outcome == GroupJoinOutcome.error) {
      message =
          '${t.get(result.messageKey)} ${result.errorDetail ?? ''}'.trim();
    } else if (result.outcome == GroupJoinOutcome.pendingCreated) {
      message = t.get('group_request_pending_toast');
    } else {
      message = t.get(result.messageKey);
    }
  } catch (_) {
    message = result.messageKey;
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
      ),
    );

    if (result.didEnterChat &&
        result.groupId != null &&
        result.groupId!.isNotEmpty) {
      final groupName = (result.groupName ?? '').trim().isEmpty
          ? 'Grupo'
          : result.groupName!.trim();

      Navigator.push(
        ctx,
        MaterialPageRoute(
          builder: (_) => GroupChatPage(
            groupId: result.groupId!,
            groupName: groupName,
          ),
        ),
      );
    }
  });

  print('DEBUG group: pending outcome = ${result.outcome}');
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
if (user == null) return const LoginPage();

final isEmailPasswordLogin = user.providerData.any(
  (p) => p.providerId == 'password',
);

if (isEmailPasswordLogin && !user.emailVerified) {
  return const EmailVerificationPage();
}

WidgetsBinding.instance.addPostFrameCallback((_) {
  _applyPendingInviteIfAny(user);
  _applyPendingGroupIfAny(user);
  EventDeepLinkService.applyPendingIfAny();
  // Auth + primeiro frame: processa fila prefs e poll do App Group.
  ShareInService.applyPendingIfAny();
  ShareInService.pollNativePending();
  ShareExtensionSessionService.ensureSession();
});

return const MainShell();

      },
    );
  }
}
