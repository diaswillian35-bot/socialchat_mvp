import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EventsPage extends StatefulWidget {
  const EventsPage({super.key});

  @override
  State<EventsPage> createState() => _EventsPageState();
}

class _EventsPageState extends State<EventsPage> {
  final db = FirebaseFirestore.instance;

  static const _bg = Colors.white;
  static const _text = Color(0xFF111827);
  static const _muted = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);

  static const _remdyBlue = Color(0xFF313A5F);
  static const _logoBlue = Color(0xFF264E9A);

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Coleção sugerida:
  /// events/{eventId}
  /// {
  ///  title: "Brasil x Canadá",
  ///  city: "Toronto",
  ///  countryCode: "ca",
  ///  placeName: "Bar X",
  ///  startAt: Timestamp,
  ///  description: "...",
  ///  isActive: true,
  ///  createdAt: serverTimestamp,
  ///  createdBy: uid,
  ///  attendeesCount: 0
  /// }
  Stream<QuerySnapshot<Map<String, dynamic>>> _eventsStream() {
    // Mostra eventos ativos, ordenados pelo mais próximo
    return db
        .collection('events')
        .where('isActive', isEqualTo: true)
        .orderBy('startAt', descending: false)
        .limit(50)
        .snapshots();
  }

  String _flagEmoji(String code) {
    final upper = code.trim().toUpperCase();
    if (upper.length != 2) return '🏳️';
    final int first = upper.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final int second = upper.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCodes([first, second]);
  }

  String _fmtDate(Timestamp? ts) {
    if (ts == null) return 'Sem data';
    final d = ts.toDate();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} • ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _createEventStub() async {
    // Stub: por enquanto só cria um evento de teste rápido.
    // Depois trocamos por uma tela “Criar evento”.
    final uid = _uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Você precisa estar logado.')),
      );
      return;
    }

    final now = DateTime.now().add(const Duration(hours: 2));
    await db.collection('events').add({
      'title': 'Encontro Remdy (teste)',
      'city': 'Toronto',
      'countryCode': 'ca',
      'placeName': 'Local a definir',
      'startAt': Timestamp.fromDate(now),
      'description': 'Evento de teste. Depois vamos criar a tela completa.',
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': uid,
      'attendeesCount': 0,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Evento teste criado ✅')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text(
          'Eventos',
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
          ),
        ),
        iconTheme: const IconThemeData(color: _muted),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(colors: [_remdyBlue, _logoBlue]),
        ),
        child: FloatingActionButton.extended(
          onPressed: _createEventStub,
          backgroundColor: Colors.transparent,
          elevation: 0,
          label: const Text(
            'Criar',
            style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
          ),
          icon: const Icon(Icons.add, color: Colors.white),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _eventsStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data?.docs ?? [];

          if (docs.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _border),
                  color: Colors.white,
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_busy_rounded, size: 38, color: _muted),
                    SizedBox(height: 10),
                    Text(
                      'Nenhum evento ainda',
                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Toque em “Criar” para adicionar o primeiro evento.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();

              final title = (data['title'] ?? 'Evento').toString();
              final city = (data['city'] ?? '').toString();
              final place = (data['placeName'] ?? '').toString();
              final cc = (data['countryCode'] ?? '').toString();
              final startAt = data['startAt'] as Timestamp?;
              final desc = (data['description'] ?? '').toString();
              final attendees = (data['attendeesCount'] is int) ? data['attendeesCount'] as int : 0;

              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  // Por enquanto: só mostra detalhes simples
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) {
                      return SafeArea(
                        child: Container(
                          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.14),
                                blurRadius: 22,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Container(
                                  width: 44,
                                  height: 5,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE5E7EB),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  Text(_flagEmoji(cc.isEmpty ? 'BR' : cc), style: const TextStyle(fontSize: 20)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: _text,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () => Navigator.pop(context),
                                    icon: const Icon(Icons.close_rounded),
                                    splashRadius: 18,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _InfoRow(icon: Icons.schedule_rounded, text: _fmtDate(startAt)),
                              if (city.isNotEmpty) _InfoRow(icon: Icons.location_city_rounded, text: city),
                              if (place.isNotEmpty) _InfoRow(icon: Icons.place_rounded, text: place),
                              _InfoRow(icon: Icons.people_alt_rounded, text: '$attendees participando'),
                              if (desc.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                Text(
                                  desc,
                                  style: const TextStyle(
                                    color: Color(0xFF374151),
                                    fontWeight: FontWeight.w600,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.pop(context);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Participar: em breve ✅')),
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _remdyBlue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: const Text(
                                    'Participar',
                                    style: TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Center(
                          child: Text(
                            _flagEmoji(cc.isEmpty ? 'BR' : cc),
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                                color: _text,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_fmtDate(startAt)}${city.isNotEmpty ? " • $city" : ""}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _muted,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            if (place.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                place,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _muted,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ]
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9FAFB),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                        ),
                        child: Text(
                          '$attendees',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: _text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF2563EB)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF374151),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
