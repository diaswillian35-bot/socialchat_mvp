import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../widget/remdy_app.dart';
import 'create_group_page.dart';
import 'group_chat_page.dart'; // ✅ ajuste o path/nome se for diferente

class GroupsListPage extends StatefulWidget {
  const GroupsListPage({super.key});

  @override
  State<GroupsListPage> createState() => _GroupsListPageState();
}

class _GroupsListPageState extends State<GroupsListPage> {
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);

  String _selectedCountry = "all";

  // ✅ lista simples de países (minúsculo no filtro)
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

  // ✅ padroniza só pra exibir bonito
  String _pretty(String s) {
    final t = s.trim();
    if (t.isEmpty) return '';
    return t[0].toUpperCase() + t.substring(1);
  }

  Query<Map<String, dynamic>> _query() {
    final ref = FirebaseFirestore.instance.collection("groups");

    // ✅ ordena pelo mais recente (se não existir, cai pro createdAt)
    // Obs: orderBy exige que o campo exista, então vamos usar updatedAt
    // porque você já salva no create e atualiza no chat.
    if (_selectedCountry == "all") {
      return ref.orderBy("updatedAt", descending: true);
    }

    // ✅ seu campo é "country" (não countryCode)
    return ref
        .where("country", isEqualTo: _selectedCountry)
        .orderBy("updatedAt", descending: true);
  }

  Future<void> _openCreate() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CreateGroupPage()),
    );

    // se criou, dá um refresh visual (Stream já atualiza, mas isso evita delay)
    if (!mounted) return;
    if (ok == true) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: const RemdyAppBar(title: "Grupos"),

      body: Column(
        children: [
          // ✅ filtro país (padrão Remdy sem rosa)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Theme(
              data: Theme.of(context).copyWith(
                colorScheme: Theme.of(context).colorScheme.copyWith(
                      primary: _remdyBlue,
                    ),
                canvasColor: Colors.white,
              ),
              child: DropdownButtonFormField<String>(
                value: _selectedCountry,
                decoration: InputDecoration(
                  labelText: "Filtrar por país",
                  filled: true,
                  fillColor: const Color(0xFFF9FAFB),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: _remdyBlue),
                  ),
                  labelStyle: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                items: _countries.map((c) {
                  return DropdownMenuItem(
                    value: c["code"],
                    child: Text(
                      c["name"]!,
                      style: const TextStyle(
                        color: _text,
                        fontWeight: FontWeight.w700,
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

          // ✅ lista
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
                      'Erro: ${snap.error}',
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
                      style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final doc = docs[i];
                    final data = doc.data();

                    final name = (data["name"] ?? "Grupo").toString();
                    final country = (data["country"] ?? "").toString();
                    final members = (data["members"] is List)
                        ? (data["members"] as List).length
                        : 0;

                    final bio = (data["bio"] ?? "").toString();

                    return InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GroupChatPage(
                              groupId: doc.id,
                              groupName: name,
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
                              child: const Icon(
                                Icons.groups_rounded,
                                color: _remdyBlue,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: _text,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'País: ${country.isEmpty ? '--' : _pretty(country)} · $members membros',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _muted,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  if (bio.trim().isNotEmpty) ...[
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
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFF9CA3AF),
                            ),
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

      // ✅ botão criar grupo
      floatingActionButton: FloatingActionButton(
        backgroundColor: _remdyBlue,
        foregroundColor: Colors.white,
        onPressed: _openCreate,
        child: const Icon(Icons.add),
      ),
    );
  }
}
