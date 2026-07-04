import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'create_event_page.dart';
import 'my_events_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import 'event_detail_page.dart';
import '../l10n/app_texts.dart';

class EventsPage extends StatefulWidget {
  final String? openEventId;

  const EventsPage({
    super.key,
    this.openEventId,
  });

  @override
  State<EventsPage> createState() => _EventsPageState();
}


class _EventsPageState extends State<EventsPage> {
  final TextEditingController _searchC = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  String _searchText = '';
  int _selectedCategory = 0;
  int _selectedEventScope = 0;

  
bool _openedDeepEvent = false;
 // 0 cidade, 1 região, 2 país

  static const Color _bg = Color(0xFFF6F7FB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _logoBlue = Color(0xFF264E9A);

  final db = FirebaseFirestore.instance;
  final _commentC = TextEditingController();

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;
@override
void dispose() {
  _searchC.dispose();
  _searchFocus.dispose();
  super.dispose();
}


  String _getRegionFromCity(String city) {
    final c = city.toLowerCase();

    if (c.contains('toronto') ||
        c.contains('north york') ||
        c.contains('york') ||
        c.contains('scarborough') ||
        c.contains('etobicoke') ||
        c.contains('mississauga') ||
        c.contains('brampton')) {
      return 'gta';
    }

    if (c.contains('ottawa')) return 'ottawa';

    return 'default';
  }

  String _fmtDate(Timestamp? ts) {
    if (ts == null) return AppTexts.t('events_no_date');


    final d = ts.toDate();

    String two(int n) => n.toString().padLeft(2, '0');

    return '${two(d.day)}/${two(d.month)}/${d.year} • ${two(d.hour)}:${two(d.minute)}';
  }

Future<void> _openMap({
  required String place,
  required String city,
}) async {
  final query = '$place $city'.trim();

  if (query.isEmpty) return;

  final uri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
  );

  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppTexts.t('events_map_error'))),

    );
  }
}



String _getEventBadge(Timestamp? ts) {
  if (ts == null) return '';

  final now = DateTime.now();
  final date = ts.toDate();

  final today = DateTime(now.year, now.month, now.day);
  final eventDay = DateTime(date.year, date.month, date.day);

  final diff = eventDay.difference(today).inDays;

if (diff == 0) return AppTexts.t('events_today_badge');
if (diff == 1) return AppTexts.t('events_tomorrow_badge');


  return '';
}

 Stream<QuerySnapshot<Map<String, dynamic>>> _loadEvents({
    required String country,
    required String city,
  }) {
    final regionKey = _getRegionFromCity(city);

   if (_selectedEventScope == 0) {
  return db
      .collection('events')
      .where('isActive', isEqualTo: true)
      .where('countryCode', isEqualTo: country)
      .where('scope', isEqualTo: 'city')
      .where(
        'cityKey',
        isEqualTo: city.trim().toLowerCase(),
      )
      .where(
        'startAt',
        isGreaterThan: Timestamp.now(),
      )
      .orderBy('startAt')
.limit(50)
.snapshots();

}

if (_selectedEventScope == 1) {
  return db
    .collection('events')
    .where('isActive', isEqualTo: true)
    .where('countryCode', isEqualTo: country)
    .where('regionKey', isEqualTo: regionKey)
    .where('startAt', isGreaterThan: Timestamp.now())
    .orderBy('startAt')
    .limit(50)
    .snapshots();

}





    return db
        .collection('events')
      .where('isActive', isEqualTo: true)
.where('countryCode', isEqualTo: country)

.where('startAt', isGreaterThan: Timestamp.now()) // 🔥 AQUI
.orderBy('startAt')
.limit(50)
.snapshots();

  }

  Future<void> _joinEvent(String eventId) async {
    final uid = _uid;
    if (uid == null) return;

    final eventRef = db.collection('events').doc(eventId);
    final attendeeRef = eventRef.collection('attendees').doc(uid);

    final doc = await attendeeRef.get();
    if (doc.exists) return;

    await attendeeRef.set({
      'uid': uid,
      'joinedAt': FieldValue.serverTimestamp(),
    });

    await eventRef.update({
      'attendeesCount': FieldValue.increment(1),
      'attendeesUids': FieldValue.arrayUnion([uid]),
    });
  }

  Future<void> _leaveEvent(String eventId) async {
    final uid = _uid;
    if (uid == null) return;

    final eventRef = db.collection('events').doc(eventId);
    final attendeeRef = eventRef.collection('attendees').doc(uid);

    final doc = await attendeeRef.get();
    if (!doc.exists) return;

    await attendeeRef.delete();

    final eventSnap = await eventRef.get();
    final current = (eventSnap.data()?['attendeesCount'] ?? 0) as int;

    await eventRef.update({
      'attendeesCount': current > 0 ? current - 1 : 0,
      'attendeesUids': FieldValue.arrayRemove([uid]),
    });
  }

  void _openEventGallery(List<String> images, int initialIndex) {
    if (images.isEmpty) return;

    showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding: EdgeInsets.zero,
          child: Stack(
            children: [
              PageView.builder(
                controller: PageController(initialPage: initialIndex),
                itemCount: images.length,
                itemBuilder: (context, index) {
                  return InteractiveViewer(
                    child: Center(
                      child: Image.network(
                        images[index],
                        fit: BoxFit.contain,
                      ),
                    ),
                  );
                },
              ),
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openDetails({
    required String eventId,
    required String title,
    required String city,
    required String place,
    required Timestamp? startAt,
    required String desc,
    required int attendees,
    required List<String> photoUrls,
    required bool sponsored,
    

  }) {
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
             color: sponsored ? const Color(0xFFFFFBEB) : Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _border),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                if (photoUrls.isNotEmpty) ...[
                  SizedBox(
                    height: 210,
                    child: PageView.builder(
                      itemCount: photoUrls.length,
                      itemBuilder: (_, i) {
                        return GestureDetector(
                          onTap: () => _openEventGallery(photoUrls, i),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.network(
                              photoUrls[i],
                              fit: BoxFit.cover,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: _text,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _InfoRow(icon: Icons.schedule_rounded, text: _fmtDate(startAt)),
                if (city.isNotEmpty)
                  _InfoRow(icon: Icons.location_city_rounded, text: city),
               if (place.isNotEmpty)
  InkWell(
    onTap: () => _openMap(place: place, city: city),
    child: _InfoRow(icon: Icons.place_rounded, text: place),
  ),

                _InfoRow(
                  icon: Icons.people_alt_rounded,
                 
text: '$attendees ${AppTexts.t('events_attending')}',

                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      desc,
                      style: const TextStyle(
                        color: Color(0xFF374151),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
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

                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _uid == null
                            ? null
                            : () async {
                                if (joined) {
                                  await _leaveEvent(eventId);
                                } else {
                                  await _joinEvent(eventId);
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              joined ? const Color(0xFFEFF6FF) : _remdyBlue,
                          foregroundColor: joined ? _remdyBlue : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          joined
    ? AppTexts.t('events_cancel_attendance')
    : AppTexts.t('events_join'),

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

  Widget _topHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Image.asset(
              'assets/remdy_logo.png',
              height: 60,
            ),
          ),
          const SizedBox(height: 12),
         Text(
 AppTexts.t('events_title'),

            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w900,
              color: _text,
            ),
          ),
          const SizedBox(height: 8),
         Text(
  AppTexts.t('events_subtitle'),

  style: TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: _muted,
  ),
),

          
          const SizedBox(height: 12),
Align(
  alignment: Alignment.centerRight,
  child: TextButton.icon(
    onPressed: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const MyEventsPage(),
        ),
      );
    },
    icon: const Icon(Icons.event_note_rounded),
    
label: Text(AppTexts.t('events_my_events')),

  ),
),

        ],
      ),
    );
  }

  Widget _searchBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 5,10, 6),
      child: TextField(
        
controller: _searchC,

focusNode: _searchFocus,

        style: const TextStyle(fontSize: 13),
  textInputAction: TextInputAction.search,
onSubmitted: (v) {
  setState(() {
    _searchText = v.toLowerCase().trim();
  });
},

        decoration: InputDecoration(
         hintText: AppTexts.t('events_search_hint'),
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: const BorderSide(color: _border),
          ),
        ),
      ),
    );
  }

  Widget _categoryChip(int index, String label) {
    final selected = _selectedCategory == index;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: () {
          setState(() {
            _selectedCategory = index;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? _remdyBlue : Colors.grey.shade200,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.black,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryFilters() {
    return SizedBox(
      height: 35,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        children: [
_categoryChip(0, AppTexts.t('events_all')),
_categoryChip(1, AppTexts.t('events_today')),
_categoryChip(2, AppTexts.t('events_week')),
_categoryChip(3, AppTexts.t('events_general')),
_categoryChip(4, AppTexts.t('events_music')),
_categoryChip(5, AppTexts.t('events_sports')),
_categoryChip(6, AppTexts.t('events_restaurant')),
_categoryChip(7, AppTexts.t('events_culture')),
_categoryChip(8, AppTexts.t('events_languages')),




        ],
      ),
    );
  }

  Widget _scopeChip(int index, String label) {
    final selected = _selectedEventScope == index;

    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedEventScope = index;
          });
        },
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 5),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: selected ? _remdyBlue : _muted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _scopeFilters(String city) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF2F7),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
         _scopeChip(
  0,
  city.isNotEmpty ? city : AppTexts.t('events_city'),
),
_scopeChip(
  1,
  AppTexts.t('events_nearby'),
),
_scopeChip(
  2,
  AppTexts.t('events_country'),
),

          ],
        ),
      ),
    );
  }

Widget _attendeeAvatars(List<String> uids, int attendees) {
  final previewUids = uids.take(3).toList();

  if (previewUids.isEmpty) {
    return Text(
      '+$attendees',
      style: const TextStyle(
        color: _muted,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    );
  }

  return Row(
    children: [
      SizedBox(
        width: previewUids.length * 22,
        height: 26,
        child: Stack(
          children: List.generate(previewUids.length, (i) {
            return Positioned(
              left: i * 18,
              child: FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                future: db.collection('publicUsers').doc(previewUids[i]).get(),
                builder: (context, snap) {
                  final data = snap.data?.data() ?? {};
              
                  final photo = (data['photoUrl'] ??
                          data['profilePhotoUrl'] ??
                          '')
                      .toString();

                  return GestureDetector(
  onTap: () {
    // abrir perfil depois
  },
  child: CircleAvatar(

                    radius: 12,
                    backgroundColor: const Color(0xFFE5E7EB),
                    backgroundImage:
                        photo.isNotEmpty ? NetworkImage(photo) : null,
                    child: photo.isEmpty
                        ? const Icon(Icons.person, size: 13)
                        : null,
                  ),
                  );
                },
              ),
            );
          }),
        ),
      ),
      const SizedBox(width: 4),
      Text(
        '+$attendees',
        style: const TextStyle(
          color: _muted,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    ],
  );
}

String _capitalize(String value) {
  if (value.isEmpty) return value;

  return value
      .split(' ')
      .map((w) =>
          w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}


void _shareEvent({
  required String eventId,
  required String title,
  required String city,
  required Timestamp? startAt,
}) {
  final link = 'https://remdy.app/e/$eventId';

  final text = '''
🎉 $title

${city.isNotEmpty ? '📍 $city' : ''}
🗓️ ${_fmtDate(startAt)}

${AppTexts.t('events_share_text')}
$link
''';

  Share.share(text);
}


  Widget _eventCard({
  required String eventId,
  required String title,
  required String city,
  required String state,
  required String place,
  required Timestamp? startAt,
  required String desc,
  required String imageUrl,
  required String category,
  required int attendees,
  required List<String> attendeesUids,
  required List<String> photoUrls,
 required bool sponsored,
}) {
  final cityDisplay = city.isNotEmpty
      ? (state.isNotEmpty
          ? '${_capitalize(city)}, $state'
          : _capitalize(city))
      : AppTexts.t('events_regional_event');

  return Container(

    margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.08),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => EventDetailPage(
        eventId: eventId,
      ),
    ),
  );
},

        child: Container(
          constraints: const BoxConstraints(minHeight: 126),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
  children: [
SizedBox(
  width: 118,
  height: 104,
  child: photoUrls.isNotEmpty
      ? PageView.builder(
          itemCount: photoUrls.length > 5 ? 5 : photoUrls.length,
          itemBuilder: (context, index) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                photoUrls[index],
                fit: BoxFit.cover,
              ),
            );
          },
        )
      : Container(
          decoration: BoxDecoration(
            color: const Color(0xFFEFF2F7),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Icon(Icons.event_rounded),
        ),
),


    // 🔥 BADGE
    Positioned(
      top: 6,
      left: 6,
      child: Builder(
        builder: (_) {
          final badge = _getEventBadge(startAt);
          if (badge.isEmpty) return const SizedBox();

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: badge == AppTexts.t('events_today_badge')
    ? Colors.red
    : Colors.orange,

              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              badge,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          );
        },
      ),
    ),



  ],
),


              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    


  if (sponsored)
    Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.amber,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
  AppTexts.t('events_sponsored'),

        style: TextStyle(
          color: Colors.black,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),

  Text(
    category.isNotEmpty ? category : AppTexts.t('events_default_category'),


                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _logoBlue,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 15,
                        height: 1.15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),

                    const SizedBox(height: 6),

                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 14,
                          color: _muted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                          cityDisplay,

                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_month_rounded,
                          size: 14,
                          color: _muted,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _fmtDate(startAt),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    _attendeeAvatars(attendeesUids, attendees),
                  ],
                ),
              ),

              const SizedBox(width: 8),
              InkWell(
  onTap: () {
    _shareEvent(
      eventId: eventId,
      title: title,
      city: city,
      startAt: startAt,
    );
  },
  borderRadius: BorderRadius.circular(999),
  child: Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(999),
    ),
    child: const Icon(
      Icons.ios_share_rounded,
      size: 17,
      color: _remdyBlue,
    ),
  ),
),

const SizedBox(width: 6),


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

                  return InkWell(
                    onTap: () async {
                      if (joined) {
                        await _leaveEvent(eventId);
                      } else {
                        await _joinEvent(eventId);
                      }
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: joined ? const Color(0xFFEFF6FF) : _remdyBlue,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                       joined
    ? AppTexts.t('events_confirmed')
    : AppTexts.t('events_join'),
                        style: TextStyle(
                          color: joined ? _remdyBlue : Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

bool _passesCategoryFilter(Map<String, dynamic> data) {
  final startAt = data['startAt'] is Timestamp
      ? data['startAt'] as Timestamp
      : null;

  final rawCategory = (data['category'] ?? '').toString();

  final category = rawCategory
      .toLowerCase()
      .trim()
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('ã', 'a')
      .replaceAll('â', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c');

  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final tomorrowStart = todayStart.add(const Duration(days: 1));
  final weekEnd = todayStart.add(const Duration(days: 7));

  final eventDate = startAt?.toDate();

  // Todos
  if (_selectedCategory == 0) return true;

  // Hoje
  if (_selectedCategory == 1) {
    if (eventDate == null) return false;
    return eventDate.isAfter(todayStart) && eventDate.isBefore(tomorrowStart);
  }

  // Semana
  if (_selectedCategory == 2) {
    if (eventDate == null) return false;
    return eventDate.isAfter(todayStart) && eventDate.isBefore(weekEnd);
  }

  // Geral
  if (_selectedCategory == 3) {
    return category == 'geral' || category == 'general';
  }

  // Música / Show
  if (_selectedCategory == 4) {
    return category == 'musica' ||
        category == 'music' ||
        category == 'show';
  }

  // Esportes
  if (_selectedCategory == 5) {
    return category == 'esporte' ||
        category == 'esportes' ||
        category == 'sports' ||
        category == 'sport';
  }

  // Restaurante / Café / Food
  if (_selectedCategory == 6) {
    return category == 'restaurante' ||
        category == 'restaurant' ||
        category == 'cafe' ||
        category == 'coffee' ||
        category == 'comida' ||
        category == 'food';
  }

  // Cultura
  if (_selectedCategory == 7) {
    return category == 'cultura' || category == 'culture';
  }

  // Idiomas
  if (_selectedCategory == 8) {
    return category == 'idiomas' ||
        category == 'languages' ||
        category == 'language';
  }

  return true;
}


Widget _eventsList({
  required String country,
  required String city,
  required double? myLat,
  required double? myLng,
}) {

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
  stream: _loadEvents(country: country, city: city),
  builder: (context, snap) {

        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          return Center(child: Text('Erro: ${snap.error}'));
        }

        final allDocs = snap.data?.docs ?? [];

        
final docs = allDocs.where((doc) {

  final data = doc.data();

final search = _searchText.trim();

if (search.isNotEmpty) {
  final title =
      (data['title'] ?? '').toString().toLowerCase();

  final city =
      (data['city'] ?? '').toString().toLowerCase();




  final state =
      (data['stateName'] ?? '').toString().toLowerCase();

  final country =
      (data['countryName'] ?? '').toString().toLowerCase();

  final place =
      (data['placeName'] ?? '').toString().toLowerCase();


  final match =
      title.contains(search) ||
      city.contains(search) ||
      state.contains(search) ||
      country.contains(search) ||
      place.contains(search);

  if (!match) return false;
}



final startAt =
    data['startAt'] is Timestamp
        ? data['startAt'] as Timestamp
        : null;

if (startAt != null) {
  final expireAt =
      startAt.toDate().add(const Duration(days: 1));

  if (expireAt.isBefore(DateTime.now())) {
    return false;
  }
}

 

 if (!_passesCategoryFilter(data)) return false;

 if (_selectedEventScope == 2) {
  final userLat = myLat;
  final userLng = myLng;

  final eventCityName =
      (data['city'] ?? '').toString().toLowerCase().trim();
  final currentCityName = city.toLowerCase().trim();

  if (eventCityName == currentCityName) return false;

  if (userLat != null && userLng != null) {
    final eventLatRaw = data['lat'];
    final eventLngRaw = data['lng'];

    if (eventLatRaw is num && eventLngRaw is num) {
      final distance = _distanceKm(
        userLat,
        userLng,
        eventLatRaw.toDouble(),
        eventLngRaw.toDouble(),
      );

      if (distance <= 100) return false;
    }
  }
}



// 🔥 evitar mostrar a mesma cidade no "Ao redor"
if (_selectedEventScope == 1) {

final userLat = myLat;
final userLng = myLng;

if (userLat == null || userLng == null) return false;


  final eventLatRaw = data['lat'];
  final eventLngRaw = data['lng'];

  if (eventLatRaw is! num || eventLngRaw is! num) return false;

 final distance = _distanceKm(
  userLat,
  userLng,
  eventLatRaw.toDouble(),
  eventLngRaw.toDouble(),
);


  final eventCityName = (data['city'] ?? '').toString().toLowerCase().trim();
  final currentCityName = city.toLowerCase().trim();

  if (eventCityName == currentCityName) return false;

  if (distance > 100) return false;
}





  if (_searchText.isEmpty) return true;

  final title = (data['title'] ?? '').toString().toLowerCase();
  final eventCitySearch = (data['city'] ?? '').toString().toLowerCase();
  
final eventState = (data['stateName'] ?? '').toString();

  final place = (data['placeName'] ?? '').toString().toLowerCase();
  final category = (data['category'] ?? '').toString().toLowerCase();

  return title.contains(_searchText) ||
      eventCitySearch.contains(_searchText) ||
      place.contains(_searchText) ||
      category.contains(_searchText);
}).toList();
docs.sort((a, b) {
  final aSponsored = a.data()['sponsored'] == true ? 1 : 0;
  final bSponsored = b.data()['sponsored'] == true ? 1 : 0;

  return bSponsored.compareTo(aSponsored);
});



        if (docs.isEmpty) {
          return Center(
            child: Text(
             _selectedEventScope == 0
    ? AppTexts.t('events_empty_city')
    : _selectedEventScope == 1
        ? AppTexts.t('events_empty_nearby')
        : AppTexts.t('events_empty_country'),


              style: TextStyle(
                color: _muted,
                fontWeight: FontWeight.w800,
              ),
            ),
          );
        }

        if (_selectedEventScope == 2) {
  final grouped = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};

  for (final doc in docs) {
    final data = doc.data();
    final state = (data['stateName'] ?? '').toString().trim();
    final key = state.isEmpty ? AppTexts.t('events_country') : state;

    grouped.putIfAbsent(key, () => []);
    grouped[key]!.add(doc);
  }

  final items = <Widget>[];

  grouped.forEach((state, stateDocs) {
    items.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
        child: Text(
          state,
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
      ),
    );

    for (final doc in stateDocs) {
      final data = doc.data();

      final title = (data['title'] ?? 'Evento').toString();
      final eventCity = (data['city'] ?? '').toString();
      final eventState = (data['stateName'] ?? '').toString();
      final place = (data['placeName'] ?? '').toString();
      final category = (data['category'] ?? 'Evento').toString();
      final desc = (data['description'] ?? '').toString();

      final startAt =
          data['startAt'] is Timestamp ? data['startAt'] as Timestamp : null;

      final attendees =
          data['attendeesCount'] is int ? data['attendeesCount'] as int : 0;

      final rawPhotos = data['photoUrls'];

      final photoUrls = rawPhotos is List
          ? rawPhotos
              .map((e) => e.toString())
              .where((e) => e.trim().isNotEmpty)
              .toList()
          : <String>[];

      final coverUrl = (data['coverUrl'] ?? '').toString().trim();

      final imageUrl = coverUrl.isNotEmpty
          ? coverUrl
          : (photoUrls.isNotEmpty ? photoUrls.first : '');

      final rawAttendeesUids = data['attendeesUids'];

      final attendeesUids = rawAttendeesUids is List
          ? rawAttendeesUids.map((e) => e.toString()).toList()
          : <String>[];

      items.add(
        _eventCard(
          eventId: doc.id,
          title: title,
          city: eventCity,
          state: eventState,
          place: place,
          startAt: startAt,
          desc: desc,
          imageUrl: imageUrl,
          category: category,
          attendees: attendees,
          attendeesUids: attendeesUids,
          photoUrls: photoUrls,
          sponsored: data['sponsored'] == true,
        ),
      );
    }
  });

  return ListView(
    padding: const EdgeInsets.only(top: 10, bottom: 90),
    children: items,
  );
}

return ListView.builder(
  padding: const EdgeInsets.only(top: 10, bottom: 90),
  itemCount: docs.length,
  itemBuilder: (context, index) {
    final doc = docs[index];
    final data = doc.data();

    final title = (data['title'] ?? 'Evento').toString();
    final eventCity = (data['city'] ?? '').toString();
    final eventState = (data['stateName'] ?? '').toString();
    final place = (data['placeName'] ?? '').toString();

    final category = (data['category'] ?? 'Evento').toString();
    final desc = (data['description'] ?? '').toString();

    final startAt =
        data['startAt'] is Timestamp ? data['startAt'] as Timestamp : null;

    final attendees =
        data['attendeesCount'] is int ? data['attendeesCount'] as int : 0;

    final rawPhotos = data['photoUrls'];

    final photoUrls = rawPhotos is List
        ? rawPhotos
            .map((e) => e.toString())
            .where((e) => e.trim().isNotEmpty)
            .toList()
        : <String>[];

    final coverUrl = (data['coverUrl'] ?? '').toString().trim();

    final imageUrl = coverUrl.isNotEmpty
        ? coverUrl
        : (photoUrls.isNotEmpty ? photoUrls.first : '');

    final rawAttendeesUids = data['attendeesUids'];

    final attendeesUids = rawAttendeesUids is List
        ? rawAttendeesUids.map((e) => e.toString()).toList()
        : <String>[];

    return _eventCard(
      eventId: doc.id,
      title: title,
      city: eventCity,
      state: eventState,
      place: place,
      startAt: startAt,
      desc: desc,
      imageUrl: imageUrl,
      category: category,
      attendees: attendees,
      attendeesUids: attendeesUids,
      photoUrls: photoUrls,
      sponsored: data['sponsored'] == true,
    );
  },
);

      },
    );
  }

  
double _distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const earthRadius = 6371.0;

  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;

  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLng / 2) *
          sin(dLng / 2);

  final c = 2 * atan2(sqrt(a), sqrt(1 - a));
  return earthRadius * c;
}

@override
Widget build(BuildContext context) {
  final uid = _uid;

  return Scaffold(
    backgroundColor: _bg,
    floatingActionButton: FloatingActionButton(
      heroTag: null,
      backgroundColor: _remdyBlue,
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const CreateEventPage(),
          ),
        );
      },
      child: const Icon(Icons.add, color: Colors.white),
    ),
    body: SafeArea(
      child: uid == null
          ? Center(
              child: Text(AppTexts.t('events_login_required')),
            )
          : FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              future: db.collection('users').doc(uid).get(),
              builder: (context, userSnap) {
                if (userSnap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final userData = userSnap.data?.data() ?? {};

                final myCountry = (userData['homeCountryCode'] ??
                        userData['countryCode'] ??
                        userData['country'] ??
                        'ca')
                    .toString()
                    .trim()
                    .toLowerCase();

                final myCity = (userData['cityName'] ??
                        userData['city'] ??
                        '')
                    .toString()
                    .trim();

                final myLat = (userData['lat'] as num?)?.toDouble();
                final myLng = (userData['lng'] as num?)?.toDouble();

                return Column(
                  children: [
                    _topHeader(),
                    _searchBox(),
                    _categoryFilters(),
                    _scopeFilters(myCity),
                    Expanded(
                      child: _eventsList(
                        country: myCountry,
                        city: myCity,
                        myLat: myLat,
                        myLng: myLng,
                      ),
                    ),
                  ],
                );
              },
            ),
    ),
  );
}
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoRow({
    required this.icon,
    required this.text,
  });

  static const Color _remdyBlue = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
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

