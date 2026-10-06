/// Pure helpers for the blocked-users settings list (no Firestore).
class BlockedUsersListLogic {
  BlockedUsersListLogic._();

  /// Stable order from `users/{uid}.blocked`; empty/duplicate entries dropped.
  static List<String> orderedUids(dynamic blockedField) {
    final seen = <String>{};
    final out = <String>[];
    if (blockedField is! List) return out;
    for (final raw in blockedField) {
      final id = raw.toString().trim();
      if (id.isEmpty || !seen.add(id)) continue;
      out.add(id);
    }
    return out;
  }

  static String labelFromPublic(Map<String, dynamic>? data, String uid) {
    if (data != null) {
      for (final key in ['name', 'displayName', 'fullName']) {
        final value = (data[key] ?? '').toString().trim();
        if (value.isNotEmpty) return value;
      }
    }
    return uid;
  }
}
