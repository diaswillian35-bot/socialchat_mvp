import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../widget/remdy_app.dart';
import 'create_group_page.dart';
import 'group_chat_page.dart';

class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key});

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  String _countryFilter = 'all'; // 'all' ou 'ca', 'br', etc.

  // ✅ lista simples de países (ajusta como quiser)
  final _countries = const <String>[
    'all',
    'ca',
    'br',
    'us',
    'fr',
    'es',
    'it',
    'pt',
    'uk',
    'ie',
    'au',
  ];

  String _labelCountry(String code) {
    if (code == 'all') return 'Todos';
    return code.toUpperCase();
  }

  String _prettyName(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return 'Grupo';
    return s[0].toUpperCase() + s.substring(1);
  }

  // ✅ filtra por "country" (igual você salva no CreateGroupPage)
  // ✅ ordena por updatedAt (se não existir, não quebra — só ordena “vazio” primeiro)
  Query<Map<String, dynamic>> _query() {
    final ref = FirebaseFirestore.instance.collection('groups');

    if (_countryFilter == 'all') {
      return ref.orderBy('updatedAt', descending: true);
    }

    return ref
        .where('country', isEqualTo: _countryFilter)
        .orderBy('updatedAt', descending: true);
  }

  // ✅ só pra exibir bonitinho
  String _countryBadge(String country) {
    final c = country.trim().toLowerCase();
    if (c.isEmpty) return '--';

    if (c.length <= 3) return c.toUpperCase();

    const map = <String, String>{
      'canada': 'CA',
      'brasil': 'BR',
      'brazil': 'BR',
      'estados unidos': 'US',
      'usa': 'US',
      'united states': 'US',
      'franca': 'FR',
      'france': 'FR',
      'espanha': 'ES',
      'spain': 'ES',
      'italia': 'IT',
      'italy': 'IT',
      'portugal': 'PT',
      'reino unido': 'UK',
      'uk': 'UK',
      'irelanda': 'IE',
      'ireland': 'IE',
      'australia': 'AU',
    };

    return (map[c] ?? c).toUpperCase();
  }

  int _membersCountFromData(Map<String, dynamic> data) {
    final m = data['members'];
    if (m is List) return m.length;

    final mc = data['membersCount'];
    if (mc is int) return mc;

    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const RemdyAppBar(title: 'Grupos'),
      body: Column(
        children: [
          // ✅ filtro país
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.public,
                      color: Color(0xFF6B7280), size: 18),
                  const SizedBox(width: 10),
                  const Text(
                    'País:',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _countryFilter,
                        isExpanded: true,
                        items: _countries
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(_labelCountry(c)),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _countryFilter = v);
                        },
                      ),
                    ),
                  ),
                ],
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
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Erro: ${snap.error}',
                        style: const TextStyle(color: Color(0xFF6B7280)),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Nenhum grupo ainda.',
                      style: TextStyle(color: Color(0xFF6B7280)),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final data = d.data();

                    final name =
                        _prettyName((data['name'] ?? '').toString());
                    final countryRaw = (data['country'] ?? '').toString();
                    final country = _countryBadge(countryRaw);
                    final membersCount = _membersCountFromData(data);

                    return InkWell(
                      borderRadius: BorderRadius.circular(16),

                      // ✅ abre o chat do grupo
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => GroupChatPage(
                              groupId: d.id,
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
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(12),
                                border:
                                    Border.all(color: const Color(0xFFE5E7EB)),
                              ),
                              child: const Icon(Icons.flag_rounded,
                                  color: Color(0xFF313A5F)),
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
                                      fontSize: 15,
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF111827),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'País: ${country.isEmpty ? '--' : country} · $membersCount membros',
                                    style: const TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: Color(0xFF9CA3AF)),
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
        backgroundColor: const Color(0xFF313A5F),
        foregroundColor: Colors.white,
        onPressed: () async {
          final ok = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CreateGroupPage()),
          );
          if (ok == true && mounted) setState(() {});
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
