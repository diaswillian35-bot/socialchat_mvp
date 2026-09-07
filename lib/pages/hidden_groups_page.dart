import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../services/group_hidden_prefs_service.dart';

/// Lista pessoal de grupos ocultos — só o UID atual pode desfazer.
class HiddenGroupsPage extends StatefulWidget {
  const HiddenGroupsPage({super.key});

  @override
  State<HiddenGroupsPage> createState() => _HiddenGroupsPageState();
}

class _HiddenGroupsPageState extends State<HiddenGroupsPage> {
  final _service = GroupHiddenPrefsService();
  bool _loading = true;
  List<_HiddenEntry> _entries = [];

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final ids = await _service.loadHiddenIds(uid);
    final entries = <_HiddenEntry>[];
    for (final id in ids) {
      String name = id;
      try {
        final doc = await FirebaseFirestore.instance
            .collection('groups')
            .doc(id)
            .get();
        final data = doc.data();
        if (data != null) {
          final n = (data['name'] ?? '').toString().trim();
          if (n.isNotEmpty) name = n;
        }
      } catch (_) {}
      entries.add(_HiddenEntry(id: id, name: name));
    }
    entries.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _unhide(_HiddenEntry entry) async {
    final uid = _uid;
    if (uid == null) return;
    final t = AppTexts.current;
    await _service.unhideGroup(uid: uid, groupId: entry.id);
    if (!mounted) return;
    setState(() => _entries.removeWhere((e) => e.id == entry.id));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.get('group_unhidden_success'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.get('group_hidden_list_title')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      t.get('group_hidden_list_empty'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final e = _entries[index];
                    return ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                      title: Text(
                        e.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      trailing: TextButton(
                        onPressed: () => _unhide(e),
                        child: Text(t.get('group_unhide')),
                      ),
                    );
                  },
                ),
    );
  }
}

class _HiddenEntry {
  const _HiddenEntry({required this.id, required this.name});
  final String id;
  final String name;
}
