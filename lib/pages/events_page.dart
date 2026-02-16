import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'event_details_page.dart';

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

  Stream<QuerySnapshot<Map<String, dynamic>>> _eventsStream() {
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

      // ✅ imagens (você pode editar depois no Firestore)
      'coverUrl': '', // foto principal
      'photoUrls': <String>[], // carrossel
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Evento teste criado ✅')),
    );
  }

  Future<void> _joinEvent(String eventId) async {
    final uid = _uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Você precisa estar logado.')),
      );
      return;
    }

    final eventRef = db.collection('events').doc(eventId);
    final attendeeRef = eventRef.collection('attendees').doc(uid);

    try {
      final snap = await attendeeRef.get();
      if (snap.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Você já está participando ✅')),
        );
        return;
      }

      await attendeeRef.set({
        'uid': uid,
        'joinedAt': FieldValue.serverTimestamp(),
      });

      await eventRef.set({
        'attendeesCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Confirmado! Você vai ao evento ✅')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao participar: $e')),
      );
    }
  }

  void _openDetails({
    required String eventId,
    required String title,
    required String cc,
    required String city,
    required String place,
    required Timestamp? startAt,
    required String desc,
    required int attendees,
    required String coverUrl,
    required List<String> photoUrls,
  }) {
    final images = <String>[
      if (coverUrl.trim().isNotEmpty) coverUrl.trim(),
      ...photoUrls.where((e) => e.trim().isNotEmpty).map((e) => e.trim()),
    ];

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

                // ✅ carrossel
                if (images.isNotEmpty) ...[
                  SizedBox(
                    height: 190,
                    child: PageView.builder(
                      itemCount: images.length > 6 ? 6 : images.length,
                      controller: PageController(viewportFraction: 1),
                      itemBuilder: (_, i) {
                        final url = images[i];
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: const Color(0xFFF1F5F9),
                              child: const Center(
                                child: Icon(Icons.broken_image_rounded, size: 32),
                              ),
                            ),
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                color: const Color(0xFFF1F5F9),
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

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

                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: (_uid == null)
                      ? const Stream.empty()
                      : db
                          .collection('events')
                          .doc(eventId)
                          .collection('attendees')
                          .doc(_uid)
                          .snapshots(),
                  builder: (context, snap) {
                    final joined = snap.data?.exists == true;
                    final disabled = (_uid == null) || joined;

                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: disabled ? null : () => _joinEvent(eventId),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: joined ? Colors.grey : _remdyBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          _uid == null
                              ? 'Faça login para participar'
                              : (joined ? 'Você vai ✔' : 'Participar'),
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        scrolledUnderElevation: 0,
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

          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Erro: ${snap.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
                ),
              ),
            );
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

              // ✅ imagens
              final coverUrl = (data['coverUrl'] ?? '').toString().trim();
              final rawPhotos = data['photoUrls'];
              final photoUrls = (rawPhotos is List)
                  ? rawPhotos.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList()
                  : <String>[];

              return InkWell(
                borderRadius: BorderRadius.circular(18),
               
onTap: () {
Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => EventDetailPage(eventId: d.id),
  ),
);
},


                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    children: [
                      // ✅ FOTO PRINCIPAL (layout antigo)
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(18),
                          bottomLeft: Radius.circular(18),
                        ),
                        child: Container(
                          width: 92,
                          height: 86,
                          color: const Color(0xFFF1F5F9),
                          child: coverUrl.isNotEmpty
                              ? Image.network(
                                  coverUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Icon(Icons.image_not_supported_rounded),
                                  ),
                                )
                              : const Center(
                                  child: Icon(Icons.photo_rounded, color: Color(0xFF94A3B8)),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
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
                              const SizedBox(height: 4),
                              Text(
                                place.isEmpty ? 'Local a definir' : place,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _muted,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // ✅ contador (direita)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Column(
                          children: [
                            Text(
                              _flagEmoji(cc.isEmpty ? 'BR' : cc),
                              style: const TextStyle(fontSize: 18),
                            ),
                            const SizedBox(height: 8),
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

  static const Color _remdyBlue = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: _remdyBlue),
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
