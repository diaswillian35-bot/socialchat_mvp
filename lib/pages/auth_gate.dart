import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';


import 'login_page.dart';
import 'splash_page.dart';
import 'main_shell_page.dart';
import 'email_verification_page.dart';
import '../services/push_service.dart';
import 'group_chat_page.dart';


class AuthGate extends StatelessWidget {
  const AuthGate({super.key});


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


  Future<void> _applyPendingInviteIfAny(User user) async {
    final prefs = await SharedPreferences.getInstance();
    final ref = prefs.getString('pending_invite_ref') ?? '';


    print('DEBUG invite: entrou _applyPendingInviteIfAny');
    print('DEBUG invite: pendingRef = $ref');


    if (ref.isEmpty) return;


    final firestore = FirebaseFirestore.instance;


    final inviterQuery = await firestore
        .collection('users')
        .where('inviteCode', isEqualTo: ref)
        .limit(1)
        .get();


    print('DEBUG invite: inviterQuery docs = ${inviterQuery.docs.length}');


    if (inviterQuery.docs.isEmpty) return;


    final inviterUid = inviterQuery.docs.first.id;
    print('DEBUG invite: inviterUid = $inviterUid');


    if (user.uid == inviterUid) {
      print('DEBUG invite: auto convite bloqueado');
      return;
    }


    final userRef = firestore.collection('users').doc(user.uid);
    final inviterRef = firestore.collection('users').doc(inviterUid);


    final userSnap = await userRef.get();
    final userData = userSnap.data() ?? {};


    final alreadyInvited = (userData['invitedBy'] ?? '').toString().trim();
    print('DEBUG invite: alreadyInvited = $alreadyInvited');


    if (alreadyInvited.isNotEmpty) return;


    String snackMessage = '🎉 Convite aplicado: $ref';


    await firestore.runTransaction((tx) async {
      final inviterSnap = await tx.get(inviterRef);
      final inviterData = inviterSnap.data() ?? {};


      final currentInvites = (inviterData['invitesCount'] is num)
          ? (inviterData['invitesCount'] as num).toInt()
          : 0;


      final currentRewardLevel = (inviterData['inviteRewardLevel'] is num)
          ? (inviterData['inviteRewardLevel'] as num).toInt()
          : 0;


      final newInvitesCount = currentInvites + 1;
      final nextRewardLevel = _rewardLevelForInviteCount(newInvitesCount);
      final rewardDays = _rewardDaysForInviteCount(newInvitesCount);


      print('DEBUG invite: currentInvites = $currentInvites');
      print('DEBUG invite: newInvitesCount = $newInvitesCount');
      print('DEBUG invite: currentRewardLevel = $currentRewardLevel');
      print('DEBUG invite: nextRewardLevel = $nextRewardLevel');
      print('DEBUG invite: rewardDays = $rewardDays');
      print('DEBUG invite: vai salvar invitedBy no user ${user.uid}');


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


        snackMessage =
            '🎉 Convite aplicado: $ref • Recompensa liberada: $rewardDays dia(s)';
      }


      tx.set(inviterRef, inviterPatch, SetOptions(merge: true));
    });


    print('DEBUG invite: transaction concluída');


    await prefs.remove('pending_invite_ref');
    print('DEBUG invite: pending_invite_ref removido');


    final ctx = PushService.navKey.currentContext;
    if (ctx != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(snackMessage),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      });
    }
  }


Future<void> _applyPendingGroupIfAny(User user) async {
  final prefs = await SharedPreferences.getInstance();
  final code = prefs.getString('pending_group_code') ?? '';

  print('DEBUG group: pending code = $code');

  if (code.isEmpty) return;

  final firestore = FirebaseFirestore.instance;

  final groupQuery = await firestore
      .collection('groups')
      .where('inviteCode', isEqualTo: code)
      .limit(1)
      .get();

  if (groupQuery.docs.isEmpty) return;

  final groupDoc = groupQuery.docs.first;
  final groupRef = groupDoc.reference;

  final uid = user.uid;

  final groupData = groupDoc.data();
final members = (groupData['members'] ?? []) as List;

if (members.contains(uid)) {
  await prefs.remove('pending_group_code');
  return;
}


  await groupRef.update({
    'members': FieldValue.arrayUnion([uid]),
    'membersCount': FieldValue.increment(1),
  });

await prefs.remove('pending_group_code');

final ctx = PushService.navKey.currentContext;
if (ctx != null) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(
 

        content: Text('🎉 Você entrou no grupo!'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
      
    );
     {
  Navigator.push(
    ctx,
    MaterialPageRoute(
      

builder: (_) {
  final groupData = groupDoc.data();
  final groupName = (groupData['name'] ?? groupData['title'] ?? 'Grupo').toString();


  return GroupChatPage(
    groupId: groupDoc.id,
    groupName: groupName,
  );
},

    ),
  );
};

  });
}

print('DEBUG group: entrou no grupo com sucesso');

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


      

WidgetsBinding.instance.addPostFrameCallback((_) {
  _applyPendingInviteIfAny(user);
  _applyPendingGroupIfAny(user);
});


        if (!user.emailVerified) {
          return const EmailVerificationPage();
        }


        return const MainShell();
      },
    );
  }
}
