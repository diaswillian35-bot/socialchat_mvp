/// Mirrors the server policy for menus only; Functions remain authoritative.
class GroupRolePolicy {
  static List<String> _list(dynamic value) => value is List
      ? value.map((v) => '$v'.trim()).where((v) => v.isNotEmpty).toList()
      : <String>[];
  static String roleOf(Map<String, dynamic> group, String uid) {
    if (uid.isEmpty) return 'outsider';
    if ('${group['ownerId'] ?? ''}'.trim() == uid) return 'owner';
    if (_list(group['admins']).contains(uid)) return 'admin';
    if (_list(group['moderators']).contains(uid) ||
        _list(group['mods']).contains(uid)) {
      return 'moderator';
    }
    return _list(group['members']).contains(uid) ? 'member' : 'outsider';
  }

  static bool can(Map<String, dynamic> group, String actorUid, String targetUid,
      String action) {
    final actor = roleOf(group, actorUid);
    final target = roleOf(group, targetUid);
    if (!['promote', 'demote', 'remove', 'ban'].contains(action)) return false;
    if (target == 'owner' || actorUid == targetUid) return false;
    if (actor == 'owner') return true;
    if (target == 'admin' || action == 'promote' || action == 'demote') {
      return false;
    }
    return actor == 'admin' || (actor == 'moderator' && target == 'member');
  }
}
