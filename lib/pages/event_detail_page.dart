import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'public_profile_page.dart';
import '../l10n/app_texts.dart';
import '../services/event_view_service.dart';

class EventDetailPage extends StatefulWidget {
  final String eventId;
  const EventDetailPage({super.key, required this.eventId});

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}
class _EventDetailPageState extends State<EventDetailPage> {
  final _commentC = TextEditingController();
  final _viewRegistration = EventViewRegistrationGuard();
String? _replyToCommentId;
String? _replyToName;
String? _replyToText;


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
   if (ts == null) return AppTexts.t('events_no_date');
    final d = ts.toDate();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} • ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _joinEvent() async {
    final uid = _uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(AppTexts.t('event_detail_login_required'))),

      );
      return;
    }

    final eventRef = db.collection('events').doc(widget.eventId);
    final attendeeRef = eventRef.collection('attendees').doc(uid);

    try {
      final userSnap = await db.collection('publicUsers').doc(uid).get();
      final userData = userSnap.data() ?? {};

      final name = (userData['name'] ?? AppTexts.t('event_detail_user')).toString();
      final photoUrl = (userData['photoUrl'] ??
              userData['profilePhotoUrl'] ??
              '')
          .toString();

      await db.runTransaction((transaction) async {
        final attendeeSnap = await transaction.get(attendeeRef);
        if (attendeeSnap.exists) {
          throw StateError('already_joined');
        }

        final eventSnap = await transaction.get(eventRef);
        final eventData = eventSnap.data() ?? {};
        final current = eventData['attendeesCount'] is int
            ? eventData['attendeesCount'] as int
            : 0;
        final next = current + 1;

        transaction.set(attendeeRef, {
          'uid': uid,
          'name': name,
          'photoUrl': photoUrl,
          'joinedAt': FieldValue.serverTimestamp(),
        });

        transaction.set(
          eventRef,
          {
            'attendeesCount': next,
            'participantsCount': next,
            'attendeesUids': FieldValue.arrayUnion([uid]),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
     SnackBar(content: Text(AppTexts.t('event_detail_join_success'))),
      );
    } on StateError catch (e) {
      if (e.message == 'already_joined' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppTexts.t('event_detail_already_joined'))),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppTexts.t('event_detail_join_error')}: $e')),
      );
    }
  }
Future<void> _openDirections(String place, String city) async {
  final query = [place, city]
      .where((e) => e.trim().isNotEmpty)
      .join(', ');

  if (query.isEmpty) return;

  final uri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
  );

  await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  );
}
Future<void> _leaveEvent() async {
  final uid = _uid;
  if (uid == null) return;

  final eventRef = db.collection('events').doc(widget.eventId);
  final attendeeRef = eventRef.collection('attendees').doc(uid);

  try {
    await db.runTransaction((transaction) async {
      final attendeeSnap = await transaction.get(attendeeRef);
      if (!attendeeSnap.exists) {
        return;
      }

      final eventSnap = await transaction.get(eventRef);
      final eventData = eventSnap.data() ?? {};
      final current = eventData['attendeesCount'] is int
          ? eventData['attendeesCount'] as int
          : 0;
      final next = current > 0 ? current - 1 : 0;

      transaction.delete(attendeeRef);
      transaction.set(
        eventRef,
        {
          'attendeesCount': next,
          'participantsCount': next,
          'attendeesUids': FieldValue.arrayRemove([uid]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
    
SnackBar(content: Text(AppTexts.t('event_detail_leave_success'))),

    );
  } catch (e) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${AppTexts.t('event_detail_leave_error')}: $e')),
    );
  }
}

Future<void> _deleteComment(String commentId) async {
  final uid = _uid;
  if (uid == null) return;

  final confirm = await showDialog<bool>(
    context: context,
    builder: (_) {
      return AlertDialog(
       title: Text(
  AppTexts.t('event_detail_delete_comment_title'),
),
        content: Text(
  AppTexts.t('event_detail_delete_comment_text'),
),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
           child: Text(AppTexts.t('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
           child: Text(
  AppTexts.t('delete'),
  style: const TextStyle(color: Colors.red),
),

          ),
        ],
      );
    },
  );

  if (confirm != true) return;

  await db
      .collection('events')
      .doc(widget.eventId)
      .collection('comments')
      .doc(commentId)
      .update({
    'isDeleted': true,
    'deletedAt': FieldValue.serverTimestamp(),
  });
}

Future<void> _toggleCommentLike(String commentId, List likedBy) async {
  final uid = _uid;
  if (uid == null) return;

  final alreadyLiked = likedBy.contains(uid);

  final ref = db
      .collection('events')
      .doc(widget.eventId)
      .collection('comments')
      .doc(commentId);

  await ref.update({
    'likedBy': alreadyLiked
        ? FieldValue.arrayRemove([uid])
        : FieldValue.arrayUnion([uid]),
    'likesCount': FieldValue.increment(alreadyLiked ? -1 : 1),
  });
}



@override
void dispose() {
  _commentC.dispose();
  super.dispose();
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
       title: Text(
  AppTexts.t('event_detail_title'),

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
            return  Center(
              child: Text(
               AppTexts.t('event_detail_not_found'),
                style: TextStyle(color: _muted, fontWeight: FontWeight.w700),
              ),
            );
          }

          if (_uid != null) {
            _viewRegistration.registerOnce(
              eventId: widget.eventId,
              source: 'mobile_app',
            );
          }

        final title = (data['title'] ??
        data['eventTitle'] ??
        data['name'] ??
        'Evento')
    .toString();

final category = (data['category'] ??
        data['type'] ??
        '')
    .toString();

final city = (data['city'] ?? '').toString();
final state = (data['stateName'] ?? '').toString();




final place = (data['placeName'] ??
        data['placeDisplay'] ??
        data['address'] ??
        '')
    .toString();

final cc = (data['countryCode'] ?? '').toString();
final startAt = data['startAt'] as Timestamp?;

final desc = (data['description'] ??
        data['desc'] ??
        data['about'] ??
        data['sobre'] ??
        '')
    .toString();

final createdBy = (data['createdBy'] ?? '').toString();
final isEventOwner = _uid == createdBy;


          

final attendees = data['attendeesCount'] is int
    ? data['attendeesCount'] as int
    : 0;

        



          final coverUrl = (data['coverUrl'] ?? '').toString().trim();
          final rawPhotos = data['photoUrls'];

          final photoUrls = (rawPhotos is List)
              ? rawPhotos.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList()
              : <String>[];

          // carrossel = cover + fotos (até 6)
      final images = <String>[
  if (coverUrl.isNotEmpty) coverUrl,
  ...photoUrls,
]
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toSet()
    .toList();




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
                      '${shownImages.length} ${AppTexts.t('event_detail_photos')}',

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
                    
if (category.isNotEmpty)
  _InfoRow(icon: Icons.category_rounded, text: category),

                  if (city.isNotEmpty)
  _InfoRow(
  icon: Icons.location_city_rounded,
text: state.isNotEmpty
    ? '${_InfoRow.capitalize(city)}, $state'
    : _InfoRow.capitalize(city),


),


                    _InfoRow(icon: Icons.place_rounded, text: 
place.isEmpty ? AppTexts.t('event_detail_place_tbd') : place
),
                    const SizedBox(height: 10),

SizedBox(
  width: double.infinity,
  child: OutlinedButton.icon(
    onPressed: () => _openDirections(place, city),
    icon: const Icon(Icons.map_rounded),
    label: Text(
  AppTexts.t('event_detail_directions'),

      style: TextStyle(fontWeight: FontWeight.w800),
    ),
    style: OutlinedButton.styleFrom(
      foregroundColor: _remdyBlue,
      side: const BorderSide(color: _border),
      padding: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
  ),
),

                   

_InfoRow(
  icon: Icons.people_alt_rounded,
  text: '${attendees.toString()} ${AppTexts.t('event_detail_attending')}',

),


const SizedBox(height: 10),

StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
  stream: eventRef
      .collection('attendees')
      .limit(15)
      .snapshots(),
  builder: (context, attendeesSnap) {
    final docs = attendeesSnap.data?.docs ?? [];

    if (docs.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: docs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final attendeeData = docs[index].data();

          final photoUrl =
              (attendeeData['photoUrl'] ?? '').toString();

          final name =
              (attendeeData['name'] ?? 'Usuário').toString();

         if (photoUrl.isNotEmpty) {
  return GestureDetector(
    onTap: () {
    Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => PublicProfilePage(
      userUid: docs[index].id,
    ),
  ),
);

    },
    child: CircleAvatar(
      radius: 20,
      backgroundImage: NetworkImage(photoUrl),
    ),
  );
}


      return GestureDetector(
  onTap: () {
    Navigator.push(
  context,
  MaterialPageRoute(
    builder: (_) => PublicProfilePage(
      userUid: docs[index].id,
    ),
  ),
);

  },
  child: CircleAvatar(
    radius: 20,
    backgroundColor: const Color(0xFFE5E7EB),

            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: _text,
              ),
            ),
          ));
      
        },
      ),
    );
  },
),



if (desc.isNotEmpty) ...[
  const SizedBox(height: 14),
  Text(
  AppTexts.t('event_detail_about'),

    style: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w900,
      color: _text,
    ),
  ),
  const SizedBox(height: 6),
  Text(
    desc,
    style: const TextStyle(
      color: Color(0xFF374151),
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
  ),
],

                   


              // ✅ Botão participar (com estado "já vai")
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: (_uid == null)
                    ? const Stream.empty()
                    : eventRef.collection('attendees').doc(_uid).snapshots(),
                builder: (context, snap) {
                  final joined = snap.data?.exists == true;
                  final disabled = (_uid == null);

                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: disabled
    ? null
    : (joined ? _leaveEvent : _joinEvent),

                      style: ElevatedButton.styleFrom(
                        backgroundColor: joined ? Colors.grey : _remdyBlue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _uid == null
    ? AppTexts.t('event_detail_login_to_join')

    : (joined ? AppTexts.t('event_detail_leave')
 : AppTexts.t('event_detail_join')),

                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),

Container(
  padding: const EdgeInsets.all(16),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    border: Border.all(color: const Color(0xFFE5E7EB)),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [

StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
  stream: eventRef.collection('comments').snapshots(),
  builder: (context, snap) {
    final count = snap.data?.docs.length ?? 0;

    return Text(
      count == 0
          ?  AppTexts.t('event_detail_comments')
: '${AppTexts.t('event_detail_comments')} ($count)',

      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
    );
  },
),


      const SizedBox(height: 12),
if (_replyToName != null) ...[
  Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE5E7EB)),
    ),

    child: Row(
      children: [
        Expanded(
          child: Text(
           '${AppTexts.t('event_detail_replying_to')} $_replyToName',

            style: const TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        GestureDetector(
          onTap: () {
            setState(() {
              _replyToCommentId = null;
              _replyToName = null;
              _replyToText = null;
            });
          },
          child: const Icon(Icons.close, size: 18),
        ),
      ],
    ),
  ),
],


Row(
  children: [
    Expanded(
      child: TextField(
        controller: _commentC,
        decoration: InputDecoration(
          hintText: AppTexts.t('event_detail_write_comment'),

          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    ),

    const SizedBox(width: 10),

    IconButton(
      onPressed: () async {
        final text = _commentC.text.trim();
        if (text.isEmpty) return;

        final uid = _uid;
        if (uid == null) return;

        final me = await db.collection('publicUsers').doc(uid).get();
        final userData = me.data() ?? {};

        final eventSnap = await eventRef.get();
        final eventData = eventSnap.data() ?? {};
        final organizerId = (
          eventData['organizerId'] ??
          eventData['createdBy'] ??
          eventData['ownerId'] ??
          eventData['userId']
        )?.toString();
        final isOrganizer = organizerId == uid;

        await eventRef.collection('comments').add({
          'uid': uid,
          'name': userData['name'] ?? 'Usuário',
          'photoUrl': userData['photoUrl'] ?? '',
          'text': text,
          'createdAt': FieldValue.serverTimestamp(),
          'likesCount': 0,
          'likedBy': [],
          'replyToCommentId': _replyToCommentId,
'replyToName': _replyToName,
'replyToText': _replyToText,
          'readByOrganizer': isOrganizer,

        });

        _commentC.clear();
       setState(() {
  _replyToCommentId = null;
  _replyToName = null;
  _replyToText = null;
});


      },
      icon: const Icon(Icons.send),
    ),
  ],
),


      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: eventRef
            .collection('comments')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snap) {

          if (!snap.hasData) {
            return const SizedBox.shrink();
          }

          final docs = snap.data!.docs
              .where((doc) => doc.data()['isDeleted'] != true)
              .toList();

         if (docs.isEmpty) {
  return  Padding(
    padding: EdgeInsets.symmetric(vertical: 8),
    child: Text(
      AppTexts.t('event_detail_first_comment'),
      style: TextStyle(
        color: _muted,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}


          return Column(
            children: docs.map((doc) {
              final data = doc.data();


              final likedBy =
    List<String>.from(data['likedBy'] ?? []);

final likesCount =
    (data['likesCount'] ?? 0) as int;

final isLiked =
    likedBy.contains(_uid);




              final name =
                  (data['name'] ?? AppTexts.t('event_detail_user'));

              final text =
                  (data['text'] ?? '').toString();

              final photo =
                  (data['photoUrl'] ?? '').toString();

                  final replyToName =
    (data['replyToName'] ?? '').toString();

final replyToText =
    (data['replyToText'] ?? '').toString();


             
return GestureDetector(
  onTap: () {
    setState(() {
      _replyToCommentId = doc.id;
      _replyToName = name;
      _replyToText = text;
    });
  },


  onLongPress: () {
    final commentUid = (data['uid'] ?? '').toString();

    if (commentUid != _uid && !isEventOwner) return;

    _deleteComment(doc.id);
  },

  
  child: Container(
    margin: const EdgeInsets.only(bottom: 12),

                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [

                    CircleAvatar(
                      radius: 18,
                      backgroundImage:
                          photo.isNotEmpty
                              ? NetworkImage(photo)
                              : null,
                      child: photo.isEmpty
                          ? Text(name[0].toUpperCase())
                          : null,
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius:
                              BorderRadius.circular(14),
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [

                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight:
                                    FontWeight.w700,
                              ),
                            ),

                            const SizedBox(height: 4),

                            

const SizedBox(height: 2),



Text(
  _timeAgo(data['createdAt']),
  style: const TextStyle(
    fontSize: 12,
    color: _muted,
  ),
),

                           if (replyToName.isNotEmpty) ...[
  Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: const Color(0xFFEDEFF3),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${AppTexts.t('event_detail_replying_to')} $replyToName',

          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: _remdyBlue,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          replyToText,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            color: _muted,
          ),
        ),
      ],
    ),
  ),
],

Text(text),

                            const SizedBox(height: 8),

InkWell(
  onTap: () => _toggleCommentLike(doc.id, likedBy),
  child: Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        isLiked ? Icons.favorite : Icons.favorite_border,
        size: 18,
        color: isLiked ? Colors.red : _muted,
      ),
      const SizedBox(width: 4),
      Text(
        '$likesCount',
        style: TextStyle(
          color: isLiked ? Colors.red : _muted,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  ),
),

   const SizedBox(width: 14),

GestureDetector(
  onTap: () {
    setState(() {
      _replyToCommentId = doc.id;
      _replyToName = name;
      _replyToText = text;
    });
  },
  child: 
Text(
  AppTexts.t('event_detail_reply'),

    style: TextStyle(
      color: _remdyBlue,
      fontWeight: FontWeight.w700,
      fontSize: 13,
    ),
  ),
),

                         

                          ],
                        ),
                      ),
                    ),
                  
                  ],
                ),
              ),
);


            }).toList(),
  
          );
        },
      ),

    ],
  ),
),

                 ],
         
          ),
              ),
            ],
          );
        
        },
    ),
    );

  }
}
String _timeAgo(dynamic value) {
  final t = AppTexts.current;

  DateTime? date;

  if (value is Timestamp) {
    date = value.toDate();
  } else if (value is DateTime) {
    date = value;
  }

  if (date == null) return '';

  final diff = DateTime.now().difference(date);

  if (diff.inSeconds < 60) {
    return t.get('event_detail_now');
  }

  if (diff.inMinutes < 60) {
    return '${diff.inMinutes} ${t.get('event_detail_minutes_ago')}';
  }

  if (diff.inHours < 24) {
    return '${diff.inHours} ${t.get('event_detail_hours_ago')}';
  }

  return '${diff.inDays} ${t.get('event_detail_days_ago')}';
}







class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});

  static const Color _remdyBlue = Color(0xFF313A5F);

static String capitalize(String value) {

  if (value.isEmpty) return value;

  return value
      .split(' ')
      .map((w) =>
          w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}


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
