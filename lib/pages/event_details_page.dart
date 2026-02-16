import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class EventDetailPage extends StatefulWidget {
  final String eventId;
  const EventDetailPage({super.key, required this.eventId});

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  final db = FirebaseFirestore.instance;

  static const _bg = Colors.white;
  static const _text = Color(0xFF111827);
  static const _muted = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);
  static const _remdyBlue = Color(0xFF313A5F);

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

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

  Future<void> _joinEvent() async {
    final uid = _uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Você precisa estar logado.')),
      );
      return;
    }

    final eventRef = db.collection('events').doc(widget.eventId);
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

  @override
  Widget build(BuildContext context) {
    final eventRef = db.collection('events').doc(widget.eventId);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Evento',
          style: TextStyle(color: _text, fontWeight: FontWeight.w900),
        ),
        iconTheme: const IconThemeData(color: _muted),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: eventRef.snapshots(),
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

          final data = snap.data?.data();
          if (data == null) {
            return const Center(
              child: Text(
                'Evento não encontrado.',
                style: TextStyle(color: _muted, fontWeight: FontWeight.w700),
              ),
            );
          }

          final title = (data['title'] ?? 'Evento').toString();
          final city = (data['city'] ?? '').toString();
          final place = (data['placeName'] ?? '').toString();
          final cc = (data['countryCode'] ?? '').toString();
          final startAt = data['startAt'] as Timestamp?;
          final desc = (data['description'] ?? '').toString();
          final attendees = (data['attendeesCount'] is int) ? data['attendeesCount'] as int : 0;

          final coverUrl = (data['coverUrl'] ?? '').toString().trim();
          final rawPhotos = data['photoUrls'];

          final photoUrls = (rawPhotos is List)
              ? rawPhotos.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList()
              : <String>[];

          // carrossel = cover + fotos (até 6)
          final images = <String>[
            if (coverUrl.isNotEmpty) coverUrl,
            ...photoUrls,
          ].where((e) => e.trim().isNotEmpty).toList();

          final shownImages = images.length > 6 ? images.take(6).toList() : images;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
            children: [
              // ✅ Carrossel topo
              if (shownImages.isNotEmpty) ...[
                SizedBox(
                  height: 230,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: PageView.builder(
                      itemCount: shownImages.length,
                      itemBuilder: (context, i) {
                        final url = shownImages[i];
                        return Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFFF1F5F9),
                            child: const Center(
                              child: Icon(Icons.broken_image_rounded, size: 34),
                            ),
                          ),
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              color: const Color(0xFFF1F5F9),
                              child: const Center(child: CircularProgressIndicator()),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.photo_library_rounded, size: 16, color: _muted),
                    const SizedBox(width: 6),
                    Text(
                      '${shownImages.length} foto(s)',
                      style: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ] else ...[
                // sem foto -> placeholder
                Container(
                  height: 150,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                  ),
                  child: const Center(
                    child: Icon(Icons.photo_rounded, size: 36, color: Color(0xFF94A3B8)),
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // ✅ Card infos
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(_flagEmoji(cc.isEmpty ? 'BR' : cc), style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: _text,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _InfoRow(icon: Icons.schedule_rounded, text: _fmtDate(startAt)),
                    if (city.isNotEmpty) _InfoRow(icon: Icons.location_city_rounded, text: city),
                    _InfoRow(icon: Icons.place_rounded, text: place.isEmpty ? 'Local a definir' : place),
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
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ✅ Botão participar (com estado "já vai")
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: (_uid == null)
                    ? const Stream.empty()
                    : eventRef.collection('attendees').doc(_uid).snapshots(),
                builder: (context, snap) {
                  final joined = snap.data?.exists == true;
                  final disabled = (_uid == null) || joined;

                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: disabled ? null : _joinEvent,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: joined ? Colors.grey : _remdyBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _uid == null ? 'Faça login para participar' : (joined ? 'Você vai ✔' : 'Participar'),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  );
                },
              ),
            ],
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
