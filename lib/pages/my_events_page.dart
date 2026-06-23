import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../l10n/app_texts.dart';
import '../pages/edit_event_page.dart';

class MyEventsPage extends StatelessWidget {
  const MyEventsPage({super.key});

  static const Color _bg = Color(0xFFF6F7FB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _remdyBlue = Color(0xFF313A5F);
static const Color _border = Color(0xFFE5E7EB);

  String _fmtDate(Timestamp? ts) {
    if (ts == null) return 'Sem data';

    final d = ts.toDate();
    String two(int n) => n.toString().padLeft(2, '0');

    return '${two(d.day)}/${two(d.month)}/${d.year} • ${two(d.hour)}:${two(d.minute)}';
  }

  Color _statusColor(String status) {
    if (status == 'approved') return Colors.green;
    if (status == 'rejected') return Colors.red;
    return Colors.orange;
  }

Color _cardColor(String status) {
  if (status == 'cancelled') {
    return const Color(0xFFF3F4F6);
  }
  return Colors.white;
}

String _statusText(String status) {
  if (status == 'approved') return AppTexts.current.get('my_events_approved');
  if (status == 'rejected') return AppTexts.current.get('my_events_rejected');
  if (status == 'cancelled') return AppTexts.current.get('my_events_cancelled');
  return AppTexts.current.get('my_events_pending');
}


  Future<void> _cancelEvent(BuildContext context, String eventId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
       title: Text(
  AppTexts.current.get('my_events_cancel_title'),
),

       content: Text(
  AppTexts.current.get('my_events_cancel_message'),
),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
           
child: Text(
  AppTexts.current.get('back'),
),

          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
           child: Text(
  AppTexts.current.get('my_events_cancel_button'),
),

          ),
        ],
      ),
    );

    if (ok != true) return;

    await FirebaseFirestore.instance.collection('events').doc(eventId).set({
      'status': 'cancelled',
      'isActive': false,
      'cancelledAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
  content: Text(
    AppTexts.current.get('my_events_cancelled'),
  ),
),

    );
  }

  @override
  Widget build(BuildContext context) {
  final t = AppTexts.current.get;  
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          
t('my_events_title')
,
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: uid == null
          ?  Center(child: Text(t('my_events_login_required')))
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                

.collection('events')
.where('createdBy', isEqualTo: uid)
.orderBy('startAt', descending: true)
.snapshots(),





              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snap.hasError) {
                  return Center(child: Text('Erro: ${snap.error}'));
                }

                final docs = snap.data?.docs ?? [];

                if (docs.isEmpty) {
                  return Center(
                    child: Text(
                      t('my_events_empty'),
                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();

                    final title = (data['title'] ?? 'Evento').toString();
                    final city = (data['city'] ?? '').toString();
                    final place = (data['placeName'] ?? '').toString();
                    final category = (data['category'] ?? '').toString();
                    final status = (data['status'] ?? 'pending').toString();
                    final attendees = data['attendeesCount'] is int
                        ? data['attendeesCount'] as int
                        : 0;

                    final sponsorInterested =
                        data['sponsorInterested'] == true;

     return Card(
  color: _cardColor(status),
  surfaceTintColor: Colors.white,
  elevation: 1.5,

                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: const TextStyle(
                                      color: _text,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _statusColor(status).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _statusText(status),
                                    style: TextStyle(
                                      color: _statusColor(status),
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$category • $city',
                              style: const TextStyle(
                                color: _muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (place.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                place,
                                style: const TextStyle(
                                  color: _muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              _fmtDate(data['startAt'] as Timestamp?),
                              style: const TextStyle(
                                color: _text,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$attendees ${t('my_events_attending')}',
                              style: const TextStyle(
                                color: _muted,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (sponsorInterested) ...[
                              const SizedBox(height: 8),
                              const Text(
                                '💰 Interesse em patrocinar',
                                style: TextStyle(
                                  color: _remdyBlue,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
  foregroundColor: _remdyBlue,
  backgroundColor: Colors.white,
  side: const BorderSide(color: _border),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  ),
),



                                 onPressed: status == 'cancelled'
    ? null
    : () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EditEventPage(eventId: doc.id),
          ),
        );
      },

                                    icon: const Icon(Icons.edit_outlined),
                                    label: Text(t('my_events_edit')),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
  foregroundColor: _remdyBlue,
  backgroundColor: Colors.white,
  side: const BorderSide(color: _border),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(12),
  ),
),



                                    onPressed: status == 'cancelled'
                                        ? null
                                        : () => _cancelEvent(context, doc.id),
                                    icon: const Icon(Icons.cancel_outlined),
                                    label: Text(t('my_events_cancel')),
                                  ),
                                ),
                              ],
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
