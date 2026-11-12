/// Regras puras da lista de destinos da Share Extension (testável).
class ShareExtensionDestinationsLogic {
  ShareExtensionDestinationsLogic._();

  static const int peopleCap = 50;

  static const String originConversation = 'conversation';
  static const String originGroupMember = 'group_member';
  static const String originSearch = 'search';

  static String pairKey(String a, String b) {
    final list = [a, b]..sort();
    return '${list[0]}_${list[1]}';
  }

  static List<String> collectGroupMemberUids({
    required List<Map<String, dynamic>> groups,
    required String uid,
  }) {
    final out = <String>[];
    final seen = <String>{};
    for (final data in groups) {
      final raw = <dynamic>[
        ...((data['members'] is List) ? data['members'] as List : const []),
        data['ownerId'],
        ...((data['admins'] is List) ? data['admins'] as List : const []),
      ];
      for (final item in raw) {
        final id = (item ?? '').toString().trim();
        if (id.isEmpty || id == uid || !seen.add(id)) continue;
        out.add(id);
      }
    }
    return out;
  }

  static bool shouldIncludePerson({
    required String uid,
    required String otherUid,
    required Map<String, dynamic> otherData,
    required bool isContact,
    bool blocked = false,
    bool hiddenFromLists = false,
    bool banned = false,
  }) {
    final id = otherUid.trim();
    if (id.isEmpty || id == uid) return false;
    if (blocked) return false;
    if (hiddenFromLists) return false;
    if (banned) return false;
    if (otherData['hiddenFromLists'] == true) return false;
    if (otherData['isBanned'] == true) return false;
    if (otherData['exploreOnly'] == true && !isContact) return false;
    return true;
  }

  /// [conversations] primeiro, depois [groupMembers], depois [searchHits].
  /// Dedup por `otherUid` (ou `destinationId`).
  static List<Map<String, dynamic>> mergePeople({
    required List<Map<String, dynamic>> conversations,
    List<Map<String, dynamic>> groupMembers = const [],
    List<Map<String, dynamic>> searchHits = const [],
    int cap = peopleCap,
  }) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    void take(List<Map<String, dynamic>> list) {
      for (final item in list) {
        if (out.length >= cap) return;
        final key =
            (item['otherUid'] ?? item['destinationId'] ?? '').toString().trim();
        if (key.isEmpty || !seen.add(key)) continue;
        out.add(item);
      }
    }

    take(conversations);
    take(groupMembers);
    take(searchHits);
    return out;
  }
}
