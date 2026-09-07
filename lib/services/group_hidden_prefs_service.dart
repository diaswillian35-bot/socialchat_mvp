import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Preferência por UID: grupos ocultos somente para o usuário atual.
///
/// Fonte local (SharedPreferences) é autoritativa no aparelho.
/// Espelho Firestore em `users/{uid}/hiddenGroups/{groupId}` quando Rules
/// permitirem (subcoleção owner-only). Falha remota não reverte o hide local.
class GroupHiddenPrefsService {
  GroupHiddenPrefsService({
    FirebaseFirestore? firestore,
    Future<SharedPreferences> Function()? prefsFactory,
    bool enableRemote = true,
  })  : _db = firestore,
        _prefsFactory = prefsFactory ?? SharedPreferences.getInstance,
        _enableRemote = enableRemote;

  final FirebaseFirestore? _db;
  final Future<SharedPreferences> Function() _prefsFactory;
  final bool _enableRemote;

  static String prefsKey(String uid) => 'group_hidden_ids_$uid';

  CollectionReference<Map<String, dynamic>>? _col(String uid) {
    if (!_enableRemote && _db == null) return null;
    final db = _db ?? FirebaseFirestore.instance;
    return db.collection('users').doc(uid).collection('hiddenGroups');
  }

  Future<Set<String>> loadHiddenIds(String uid) async {
    if (uid.trim().isEmpty) return {};
    final prefs = await _prefsFactory();
    final local = prefs.getStringList(prefsKey(uid)) ?? const <String>[];
    final out = local.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();

    final col = _col(uid);
    if (col == null) return out;

    try {
      final snap = await col.get();
      for (final d in snap.docs) {
        if (d.id.trim().isNotEmpty) out.add(d.id.trim());
      }
      if (out.length != local.length ||
          !out.every((id) => local.contains(id))) {
        await prefs.setStringList(prefsKey(uid), out.toList()..sort());
      }
    } catch (_) {
      // Rules ainda não deployadas ou offline: mantém local.
    }
    return out;
  }

  Future<void> hideGroup({
    required String uid,
    required String groupId,
    String? groupName,
  }) async {
    final u = uid.trim();
    final g = groupId.trim();
    if (u.isEmpty || g.isEmpty) return;

    final prefs = await _prefsFactory();
    final current = (prefs.getStringList(prefsKey(u)) ?? <String>[])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    current.add(g);
    await prefs.setStringList(prefsKey(u), current.toList()..sort());

    final col = _col(u);
    if (col == null) return;
    try {
      await col.doc(g).set({
        'groupId': g,
        if (groupName != null && groupName.trim().isNotEmpty)
          'name': groupName.trim(),
        'hiddenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Preferência local já gravada.
    }
  }

  Future<void> unhideGroup({
    required String uid,
    required String groupId,
  }) async {
    final u = uid.trim();
    final g = groupId.trim();
    if (u.isEmpty || g.isEmpty) return;

    final prefs = await _prefsFactory();
    final current = (prefs.getStringList(prefsKey(u)) ?? <String>[])
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty && e != g)
        .toList()
      ..sort();
    await prefs.setStringList(prefsKey(u), current);

    final col = _col(u);
    if (col == null) return;
    try {
      await col.doc(g).delete();
    } catch (_) {}
  }

  /// Se ainda for membro, ocultar da lista pessoal não é permitido sem sair.
  static bool canHideWhileMember({required bool isMember}) => !isMember;
}
