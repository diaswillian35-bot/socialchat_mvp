import 'group_join_service.dart';

/// Contagem de solicitações pendentes de entrada (admin/owner only).
class GroupPendingJoinBadgeLogic {
  GroupPendingJoinBadgeLogic._();

  static bool isOwnerOrAdmin({
    required Map<String, dynamic> data,
    required String uid,
  }) {
    if (uid.isEmpty) return false;
    final ownerId = (data['ownerId'] ?? data['createdBy'] ?? '').toString().trim();
    if (ownerId.isNotEmpty && ownerId == uid) return true;
    final admins = data['admins'];
    if (admins is List && admins.map((e) => '$e'.trim()).contains(uid)) {
      return true;
    }
    return false;
  }

  static bool isApprovalPolicy(Map<String, dynamic> data) {
    return GroupJoinService.normalizeJoinPolicy(data['joinPolicy']) == 'approval';
  }

  /// Admin/owner de grupo com política de aprovação.
  static bool watchesPendingForGroup({
    required Map<String, dynamic> data,
    required String uid,
  }) {
    return isOwnerOrAdmin(data: data, uid: uid) && isApprovalPolicy(data);
  }

  /// Conta só `status == pending`. Deduplica por id do documento.
  static int countPendingDocs(
    Iterable<MapEntry<String, Map<String, dynamic>>> docs,
  ) {
    final seen = <String>{};
    var n = 0;
    for (final e in docs) {
      final id = e.key.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      final status = (e.value['status'] ?? '').toString().trim().toLowerCase();
      if (status == 'pending') n++;
    }
    return n;
  }

  static int sumGroupCounts(Map<String, int> byGroupId) {
    var total = 0;
    for (final v in byGroupId.values) {
      if (v > 0) total += v;
    }
    return total;
  }

  /// `null` se zero; senão `"1"`…`"99"` ou `"99+"`.
  static String? formatBadge(int count) {
    if (count <= 0) return null;
    if (count > 99) return '99+';
    return '$count';
  }
}
