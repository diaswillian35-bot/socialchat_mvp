import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'create_group_page.dart';
import 'group_chat_page.dart';

class GroupsListPage extends StatefulWidget {
  const GroupsListPage({super.key});

  @override
  State<GroupsListPage> createState() => _GroupsListPageState();
}

class _GroupsListPageState extends State<GroupsListPage> {
  // ✅ Remdy style
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _logoBlue = Color(0xFF264E9A);

  String _selectedCountry = "all";

  final List<Map<String, String>> _countries = const [
    {"code": "all", "name": "Todos"},
    {"code": "canada", "name": "Canadá"},
    {"code": "brasil", "name": "Brasil"},
    {"code": "estados unidos", "name": "Estados Unidos"},
    {"code": "espanha", "name": "Espanha"},
    {"code": "franca", "name": "França"},
    {"code": "portugal", "name": "Portugal"},
    {"code": "italia", "name": "Itália"},
    {"code": "uk", "name": "Reino Unido"},
    {"code": "irlanda", "name": "Irlanda"},
    {"code": "australia", "name": "Austrália"},
  ];

  String _pretty(String s) {
    final t = s.trim();
    if (t.isEmpty) return '--';
    if (t.length == 1) return t.toUpperCase();
    return t[0].toUpperCase() + t.substring(1);
  }

  int _membersCount(Map<String, dynamic> data) {
    final m = data["members"];
    if (m is List) return m.length;
    final mc = data["membersCount"];
    if (mc is int) return mc;
    return 0;
  }

  Query<Map<String, dynamic>> _query() {
    final ref = FirebaseFirestore.instance.collection("groups");

    if (_selectedCountry == "all") {
      return ref.orderBy("updatedAt", descending: true);
    }

    return ref
        .where("country", isEqualTo: _selectedCountry)
        .orderBy("updatedAt", descending: true);
  }

  Future<void> _openCreate() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateGroupPage()),
    );
    if (!mounted) return;
    if (ok == true) setState(() {});
  }

  InputDecoration _dropDec() {
    return InputDecoration(
      labelText: "Filtrar por país",
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _logoBlue),
      ),
      labelStyle: const TextStyle(
        color: _muted,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,

      // ✅ AppBar Remdy (sem rosa / sem tema do sistema)
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: const Text(
          " Grupo ",
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ),

      body: Column(
        children: [
          // ✅ Card topo Remdy
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_remdyBlue, _logoBlue]),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Row(
                children: [
                  Icon(Icons.groups_rounded, color: Colors.white),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Entre em grupos para conversar\nfazer amigos e combinar encontros.",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ✅ Dropdown Remdy (força cores, remove roxo/rosa)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(context).colorScheme.copyWith(
                      primary: _logoBlue,
                    ),
                canvasColor: Colors.white,
              ),
              child: DropdownButtonFormField<String>(
                value: _selectedCountry,
                decoration: _dropDec(),
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _muted),
                items: _countries.map((c) {
                  return DropdownMenuItem(
                    value: c["code"],
                    child: Text(
                      c["name"]!,
                      style: const TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _selectedCountry = v);
                },
              ),
            ),
          ),

          // ✅ Lista de grupos
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _query().snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                    child: Text(
                      "Erro: ${snap.error}",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _muted),
                    ),
                  );
                }

                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      "Nenhum grupo encontrado",
                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data();

                    final name = (data["name"] ?? "Grupo").toString().trim();
                    final bio = (data["bio"] ?? "").toString().trim();
                    final country = (data["country"] ?? "").toString().trim();
                    final city = (data["city"] ?? "").toString();
                    final members = _membersCount(data);

                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GroupChatPage(
                              groupId: doc.id,
                              groupName: name.isEmpty ? "Grupo" : name,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: _border),
                              ),
                              child: const Icon(Icons.flag_rounded, color: _remdyBlue),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name.isEmpty ? "Grupo" : name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _text,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
  'País: ${country.isEmpty ? '--' : _pretty(country)} · $city · $members membros',

                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _muted,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  if (bio.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      bio,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _muted,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Color(0xFF9CA3AF)),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        backgroundColor: _remdyBlue,
        foregroundColor: Colors.white,
        onPressed: _openCreate,
        child: const Icon(Icons.add),
      ),
    );
  }
}
