import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'group_ban_service.dart';

/// Resultado de uma tentativa de entrada em grupo.
enum GroupJoinOutcome {
  joined,
  alreadyMember,
  pendingCreated,
  pendingExists,
  inviteOnlyDenied,
  invalidInvite,
  groupUnavailable,
  wrongJoinPolicy,
  banned,
  premiumRequired,
  groupFull,
  notAuthenticated,
  networkError,
  error,
}

class GroupJoinResult {
  const GroupJoinResult({
    required this.outcome,
    this.groupId,
    this.groupName,
    this.errorDetail,
  });

  final GroupJoinOutcome outcome;
  final String? groupId;
  final String? groupName;
  final String? errorDetail;

  bool get didEnterChat =>
      outcome == GroupJoinOutcome.joined ||
      outcome == GroupJoinOutcome.alreadyMember;

  /// Chave de tradução sugerida (lib/l10n).
  String get messageKey {
    switch (outcome) {
      case GroupJoinOutcome.joined:
        return 'group_joined_success';
      case GroupJoinOutcome.alreadyMember:
        return 'group_already_member';
      case GroupJoinOutcome.pendingCreated:
        return 'group_request_sent_to_admin';
      case GroupJoinOutcome.pendingExists:
        return 'group_awaiting_approval';
      case GroupJoinOutcome.inviteOnlyDenied:
        return 'group_invite_only_message';
      case GroupJoinOutcome.invalidInvite:
        return 'group_invite_invalid';
      case GroupJoinOutcome.groupUnavailable:
        return 'group_unavailable';
      case GroupJoinOutcome.wrongJoinPolicy:
        return 'group_invite_wrong_policy';
      case GroupJoinOutcome.banned:
        return 'group_cannot_join_banned';
      case GroupJoinOutcome.premiumRequired:
        return 'group_premium_other_country';
      case GroupJoinOutcome.groupFull:
        return 'group_unavailable';
      case GroupJoinOutcome.notAuthenticated:
        return 'group_login_to_join';
      case GroupJoinOutcome.networkError:
        return 'group_join_network_error';
      case GroupJoinOutcome.error:
        return 'group_error_join_prefix';
    }
  }
}

/// Entrada em grupos respeitando `joinPolicy` de forma única.
///
/// `inviteOnly` → somente Cloud Function [joinGroupByInviteCode] (Admin SDK).
/// `open` / `approval` → cliente + Firestore Rules.
class GroupJoinService {
  GroupJoinService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  static String normalizeInviteCode(String? code) =>
      (code ?? '').trim().toUpperCase();

  static String normalizeJoinPolicy(dynamic raw) {
    final p = (raw ?? 'open').toString().trim().toLowerCase();
    if (p == 'approval' || p == 'adminapproval') return 'approval';
    if (p == 'inviteonly' || p == 'invite_only' || p == 'invite-only') {
      return 'inviteOnly';
    }
    return 'open';
  }

  static List<String> _membersOf(Map<String, dynamic> data) {
    final raw = data['members'];
    if (raw is! List) return <String>[];
    return raw
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Preserva a lista `members` exatamente como no documento (necessário para
  /// as Rules `listOnlyAddedUid` / `hasAll`). Apenas acrescenta [uid] se
  /// ainda não estiver presente. NÃO filtrar vazios aqui — isso quebra o
  /// self-join open (permission-denied).
  static List<dynamic> membersAfterOpenJoin(
    Map<String, dynamic> groupData,
    String uid,
  ) {
    final raw = groupData['members'];
    final next = raw is List ? List<dynamic>.from(raw) : <dynamic>[];
    final already = next.any((e) => e.toString().trim() == uid);
    if (!already) next.add(uid);
    return next;
  }

  /// Preserva os contadores existentes e inicializa somente o novo membro.
  ///
  /// `set(..., merge: true)` trata uma chave como `unread.uid` como nome de
  /// campo literal. Além de poluir o documento, isso não satisfaz as Rules,
  /// que autorizam a alteração do mapa `unread`.
  static Map<String, dynamic> unreadAfterJoin(
    Map<String, dynamic> groupData,
    String uid,
  ) {
    final raw = groupData['unread'];
    final unread = raw is Map
        ? Map<String, dynamic>.from(
            raw.map((key, value) => MapEntry(key.toString(), value)),
          )
        : <String, dynamic>{};
    unread[uid] = 0;
    return unread;
  }

  /// Entra pelo código de convite (deep link / JoinGroupPage / pending).
  static Future<GroupJoinResult> joinByInviteCode({
    required String inviteCode,
    String? uid,
  }) async {
    final code = normalizeInviteCode(inviteCode);
    if (code.isEmpty) {
      return const GroupJoinResult(outcome: GroupJoinOutcome.invalidInvite);
    }

    final userUid = uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (userUid == null || userUid.isEmpty) {
      return const GroupJoinResult(outcome: GroupJoinOutcome.notAuthenticated);
    }

    try {
      final q = await _db
          .collection('groups')
          .where('inviteCode', isEqualTo: code)
          .limit(2)
          .get();

      if (q.docs.isEmpty) {
        return const GroupJoinResult(outcome: GroupJoinOutcome.invalidInvite);
      }

      if (q.docs.length > 1) {
        return const GroupJoinResult(
          outcome: GroupJoinOutcome.error,
          errorDetail: 'invite_code_conflict',
        );
      }

      final doc = q.docs.first;
      final data = doc.data();
      final policy = normalizeJoinPolicy(data['joinPolicy']);

      final banned = await GroupBanService.isUserBanned(
        groupId: doc.id,
        uid: userUid,
      );
      if (banned) {
        return GroupJoinResult(
          outcome: GroupJoinOutcome.banned,
          groupId: doc.id,
          groupName: (data['name'] ?? data['title'] ?? '').toString(),
        );
      }

      // inviteOnly: nunca escrever members no cliente — só a Function.
      if (policy == 'inviteOnly') {
        return _joinInviteOnlyViaCallable(code);
      }

      return joinByGroupId(
        groupId: doc.id,
        uid: userUid,
        inviteCode: code,
      );
    } on FirebaseFunctionsException catch (e) {
      return _mapFunctionsException(e);
    } on FirebaseException catch (e) {
      return _mapFirestoreException(e);
    } catch (e) {
      return GroupJoinResult(
        outcome: GroupJoinOutcome.error,
        errorDetail: e.toString(),
      );
    }
  }

  /// Entra por `groupId`. Sem código, `inviteOnly` é negado no app;
  /// com código válido, delega à Cloud Function (sem update direto).
  static Future<GroupJoinResult> joinByGroupId({
    required String groupId,
    String? uid,
    String? inviteCode,
  }) async {
    final userUid = uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (userUid == null || userUid.isEmpty) {
      return const GroupJoinResult(outcome: GroupJoinOutcome.notAuthenticated);
    }

    final presentedCode = normalizeInviteCode(inviteCode);
    final groupRef = _db.collection('groups').doc(groupId);

    try {
      // Peek policy first — inviteOnly never uses client member writes.
      final peek = await groupRef.get();
      if (!peek.exists) {
        return const GroupJoinResult(
          outcome: GroupJoinOutcome.groupUnavailable,
        );
      }
      final peekData = peek.data() ?? <String, dynamic>{};
      final peekPolicy = normalizeJoinPolicy(peekData['joinPolicy']);

      assert(() {
        debugPrint(
          'GroupJoin peek groupId=$groupId policy=$peekPolicy '
          'deleted=${peekData['deleted']}',
        );
        return true;
      }());

      final banned = await GroupBanService.isUserBanned(
        groupId: groupId,
        uid: userUid,
      );
      if (banned) {
        return GroupJoinResult(
          outcome: GroupJoinOutcome.banned,
          groupId: groupId,
          groupName: (peekData['name'] ?? peekData['title'] ?? '').toString(),
        );
      }

      if (peekPolicy == 'inviteOnly') {
        if (presentedCode.isEmpty) {
          return GroupJoinResult(
            outcome: GroupJoinOutcome.inviteOnlyDenied,
            groupId: groupId,
            groupName: (peekData['name'] ?? peekData['title'] ?? '').toString(),
          );
        }
        return _joinInviteOnlyViaCallable(presentedCode);
      }

      // Open: escrita de members somente pela Function transacional.
      // Firestore Rules não conseguem provar a ordem de um prefixo arbitrário.
      if (peekPolicy == 'open') {
        return _joinOpenViaCallable(groupId);
      }

      return await _db.runTransaction((tx) async {
        final snap = await tx.get(groupRef);
        if (!snap.exists) {
          return const GroupJoinResult(
            outcome: GroupJoinOutcome.groupUnavailable,
          );
        }

        final data = snap.data() ?? <String, dynamic>{};
        final name = (data['name'] ?? data['title'] ?? 'Grupo').toString();

        if (data['deleted'] == true) {
          return GroupJoinResult(
            outcome: GroupJoinOutcome.groupUnavailable,
            groupId: groupId,
            groupName: name,
          );
        }

        final docCode = normalizeInviteCode(
          (data['inviteCode'] ?? '').toString(),
        );

        if (presentedCode.isNotEmpty &&
            docCode.isNotEmpty &&
            presentedCode != docCode) {
          return GroupJoinResult(
            outcome: GroupJoinOutcome.invalidInvite,
            groupId: groupId,
            groupName: name,
          );
        }

        final members = _membersOf(data);
        if (members.contains(userUid)) {
          return GroupJoinResult(
            outcome: GroupJoinOutcome.alreadyMember,
            groupId: groupId,
            groupName: name,
          );
        }

        final policy = normalizeJoinPolicy(data['joinPolicy']);

        // Defesa extra: nunca self-join inviteOnly no cliente.
        if (policy == 'inviteOnly') {
          return GroupJoinResult(
            outcome: GroupJoinOutcome.inviteOnlyDenied,
            groupId: groupId,
            groupName: name,
          );
        }

        if (policy == 'approval') {
          final pendingRef =
              groupRef.collection('pendingRequests').doc(userUid);
          final pendingSnap = await tx.get(pendingRef);
          final pendingData = pendingSnap.data() ?? <String, dynamic>{};
          final status =
              (pendingData['status'] ?? '').toString().trim().toLowerCase();

          if (status == 'pending') {
            return GroupJoinResult(
              outcome: GroupJoinOutcome.pendingExists,
              groupId: groupId,
              groupName: name,
            );
          }

          final userSnap = await tx.get(_db.collection('users').doc(userUid));
          final userData = userSnap.data() ?? <String, dynamic>{};

          tx.set(
            pendingRef,
            {
              'uid': userUid,
              'name': (userData['name'] ?? '').toString(),
              'photoUrl': (userData['photoUrl'] ?? userData['avatarUrl'] ?? '')
                  .toString(),
              'status': 'pending',
              'createdAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );

          return GroupJoinResult(
            outcome: GroupJoinOutcome.pendingCreated,
            groupId: groupId,
            groupName: name,
          );
        }

        return GroupJoinResult(
          outcome: GroupJoinOutcome.wrongJoinPolicy,
          groupId: groupId,
          groupName: name,
        );
      });
    } on FirebaseFunctionsException catch (e) {
      return _mapFunctionsException(e);
    } on FirebaseException catch (e) {
      assert(() {
        debugPrint(
          'GroupJoin FirebaseException code=${e.code} message=${e.message}',
        );
        return true;
      }());
      return _mapFirestoreException(e, groupId: groupId);
    } catch (e) {
      assert(() {
        debugPrint('GroupJoin unexpected: $e');
        return true;
      }());
      return GroupJoinResult(
        outcome: GroupJoinOutcome.error,
        groupId: groupId,
        errorDetail: e.toString(),
      );
    }
  }

  static Future<GroupJoinResult> _joinOpenViaCallable(String groupId) async {
    try {
      final callable = _functions.httpsCallable('joinOpenGroup');
      final response = await callable.call(<String, dynamic>{
        'groupId': groupId,
      });
      return _resultFromCallableResponse(response.data);
    } on FirebaseFunctionsException catch (e) {
      return _mapFunctionsException(e);
    }
  }

  static Future<GroupJoinResult> _joinInviteOnlyViaCallable(String code) async {
    try {
      final callable = _functions.httpsCallable('joinGroupByInviteCode');
      final response = await callable.call(<String, dynamic>{
        'inviteCode': code,
      });

      return _resultFromCallableResponse(response.data);
    } on FirebaseFunctionsException catch (e) {
      return _mapFunctionsException(e);
    } on FirebaseException catch (e) {
      return _mapFirestoreException(e);
    }
  }

  static GroupJoinResult _resultFromCallableResponse(dynamic data) {
    if (data is! Map) {
      return const GroupJoinResult(outcome: GroupJoinOutcome.error);
    }
    final map = Map<String, dynamic>.from(
      data.map((k, v) => MapEntry(k.toString(), v)),
    );
    final groupId = (map['groupId'] ?? '').toString();
    final groupName = (map['groupName'] ?? '').toString();
    final alreadyMember = map['alreadyMember'] == true;
    final joined = map['joined'] == true;

    if (groupId.isEmpty) {
      return const GroupJoinResult(outcome: GroupJoinOutcome.error);
    }

    if (alreadyMember) {
      return GroupJoinResult(
        outcome: GroupJoinOutcome.alreadyMember,
        groupId: groupId,
        groupName: groupName,
      );
    }

    if (joined) {
      return GroupJoinResult(
        outcome: GroupJoinOutcome.joined,
        groupId: groupId,
        groupName: groupName,
      );
    }

    return GroupJoinResult(
      outcome: GroupJoinOutcome.error,
      groupId: groupId,
      groupName: groupName,
    );
  }

  static GroupJoinResult _mapFirestoreException(
    FirebaseException e, {
    String? groupId,
  }) {
    switch (e.code) {
      case 'permission-denied':
        return GroupJoinResult(
          outcome: GroupJoinOutcome.error,
          groupId: groupId,
          errorDetail: e.message ?? e.code,
        );
      case 'unavailable':
      case 'deadline-exceeded':
      case 'cancelled':
      case 'network-request-failed':
        return GroupJoinResult(
          outcome: GroupJoinOutcome.networkError,
          groupId: groupId,
          errorDetail: e.message ?? e.code,
        );
      case 'not-found':
        return GroupJoinResult(
          outcome: GroupJoinOutcome.groupUnavailable,
          groupId: groupId,
          errorDetail: e.message,
        );
      default:
        return GroupJoinResult(
          outcome: GroupJoinOutcome.error,
          groupId: groupId,
          errorDetail: e.message ?? e.code,
        );
    }
  }

  static GroupJoinResult _mapFunctionsException(FirebaseFunctionsException e) {
    switch (e.code) {
      case 'unauthenticated':
        return const GroupJoinResult(
          outcome: GroupJoinOutcome.notAuthenticated,
        );
      case 'invalid-argument':
      case 'not-found':
        return GroupJoinResult(
          outcome: GroupJoinOutcome.invalidInvite,
          errorDetail: e.message,
        );
      case 'permission-denied':
        final message = (e.message ?? '').toLowerCase();
        if (message.contains('premium-required') ||
            message.contains('premium required')) {
          return GroupJoinResult(
            outcome: GroupJoinOutcome.premiumRequired,
            errorDetail: e.message,
          );
        }
        return GroupJoinResult(
          outcome: GroupJoinOutcome.banned,
          errorDetail: e.message,
        );
      case 'failed-precondition':
        final msg = (e.message ?? '').toLowerCase();
        if (msg.contains('unavailable') || msg.contains('deleted')) {
          return GroupJoinResult(
            outcome: GroupJoinOutcome.groupUnavailable,
            errorDetail: e.message,
          );
        }
        if (msg.contains('invite-only') || msg.contains('invite only')) {
          return GroupJoinResult(
            outcome: GroupJoinOutcome.wrongJoinPolicy,
            errorDetail: e.message,
          );
        }
        return GroupJoinResult(
          outcome: GroupJoinOutcome.groupUnavailable,
          errorDetail: e.message,
        );
      case 'already-exists':
        return const GroupJoinResult(
          outcome: GroupJoinOutcome.alreadyMember,
        );
      case 'unavailable':
      case 'deadline-exceeded':
      case 'cancelled':
        return GroupJoinResult(
          outcome: GroupJoinOutcome.networkError,
          errorDetail: e.message ?? e.code,
        );
      case 'resource-exhausted':
        return GroupJoinResult(
          outcome: GroupJoinOutcome.groupFull,
          errorDetail: e.message,
        );
      default:
        return GroupJoinResult(
          outcome: GroupJoinOutcome.error,
          errorDetail: e.message ?? e.code,
        );
    }
  }
}
