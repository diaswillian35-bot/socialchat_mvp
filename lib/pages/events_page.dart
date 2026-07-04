import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'event_detail_page.dart';
import '../l10n/app_texts.dart';


class EventsPage extends StatefulWidget {


  const EventsPage({super.key});



  @override
  State<EventsPage> createState() => _EventsPageState();
}


class _EventsPageState extends State<EventsPage> {

  
  String _selectedCity = '';

  int _selectedEventScope = 0; // 0 cidade, 1 região, 2 país


@override
void initState() {
  super.initState();
  _loadSavedCity();
}

  Future<void> _loadSavedCity() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;

  final doc =
      await FirebaseFirestore.instance.collection('users').doc(uid).get();

  final data = doc.data();
  if (data == null) return;

  final savedCity = (data['cityName'] ??
          data['city'] ??
          '')
      .toString()
      .trim();

  if (savedCity.isNotEmpty && mounted) {
    setState(() {
      _selectedCity = savedCity;
    });
  }
}


  final db = FirebaseFirestore.instance;


  static const _bg = Colors.white;
  static const _text = Color(0xFF111827);
  static const _muted = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);


  static const _remdyBlue = Color(0xFF313A5F);
  static const _logoBlue = Color(0xFF264E9A);


  String _loadedLocaleCode = '';


  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

Future<String> _myCityName() async {
  final uid = _uid;
  if (uid == null) return '';

  final snap = await db.collection('users').doc(uid).get();
  final data = snap.data() ?? {};

  return (data['cityName'] ??
          data['city'] ??
          '')
      .toString()
      .trim();
}




  @override
  void didChangeDependencies() {
    super.didChangeDependencies();


    final locale = Localizations.localeOf(context);
    final nextCode = '${locale.languageCode}_${locale.countryCode ?? ''}';


    if (_loadedLocaleCode == nextCode) return;
    _loadedLocaleCode = nextCode;


    AppTexts.load(locale).then((_) {
      if (mounted) setState(() {});
    });
  }



Stream<QuerySnapshot<Map<String, dynamic>>> _eventsStream(
  String country,
  String city,
) {
  final base = db
      .collection('events')
      .where('isActive', isEqualTo: true)
      .where('countryCode', isEqualTo: country);

  if (city.trim().isNotEmpty) {
    return base
        .where('city', isEqualTo: city)
        .orderBy('startAt')
        .limit(50)
        .snapshots();
  }

  return base
      .orderBy('startAt')
      .limit(50)
      .snapshots();
}

Future<QuerySnapshot<Map<String, dynamic>>> _loadEventsWithFallback(
  String country,
  String city,
) async {
  return db
      .collection('events')
      .where('isActive', isEqualTo: true)
      .where('countryCode', isEqualTo: country)
      .where('scope', isEqualTo: 'city')
      .where('city', isEqualTo: city.trim())
      .limit(50)
      .get();
}





  String _flagEmoji(String code) {
    final upper = code.trim().toUpperCase();
    if (upper.length != 2) return '🏳️';
    final int first = upper.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final int second = upper.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCodes([first, second]);
  }


  String _fmtDate(Timestamp? ts) {
    final t = AppTexts.current;
    if (ts == null) return t.get('no_date');
    final d = ts.toDate();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} • ${two(d.hour)}:${two(d.minute)}';
  }

String _eventBadge(Timestamp? ts, int attendees) {
  final t = AppTexts.current;

  if (attendees >= 10) return '🔥 ${t.get('popular')}';

  if (ts == null) return '';

  final now = DateTime.now();
  final d = ts.toDate();

  final today = DateTime(now.year, now.month, now.day);
  final eventDay = DateTime(d.year, d.month, d.day);

  final diff = eventDay.difference(today).inDays;

  if (diff == 0) return t.get('today');
  if (diff == 1) return t.get('tomorrow');

  return '';
}

Widget _eventScopeChip(int index, String label) {

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
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 12,
              color: selected ? _remdyBlue : _muted,
            ),
          ),
        ),
      ),
    ),
  );
}

String _getRegionFromCity(String city) {
  final c = city.toLowerCase();

  if (c.contains('toronto') ||
      c.contains('north york') ||
      c.contains('scarborough') ||
      c.contains('etobicoke') ||
      c.contains('mississauga') ||
      c.contains('brampton')) {
    return 'gta';
  }

  if (c.contains('ottawa')) return 'ottawa';

  return 'default';
}

  Future<void> _createEventStub() async {
    final t = AppTexts.current;
    final uid = _uid;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t.get('you_need_to_be_logged_in'))),
      );
      return;
    }


    final now = DateTime.now().add(const Duration(hours: 2));


    await db.collection('events').add({
      'title': t.get('remdy_meeting_test'),
      'city': 'Toronto',
    'regionKey': 'gta',
'scope': 'city',
'countryCode': 'ca',
 
      'placeName': t.get('place_to_be_defined'),
      'startAt': Timestamp.fromDate(now),
      'description': t.get('event_test_description'),
      'isActive': true,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': uid,
      'attendeesCount': 0,
      'coverUrl': '',
      'photoUrls': <String>[],
    });


    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t.get('test_event_created'))),
    );
  }



Future<void> _joinEvent(String eventId) async {
  final uid = _uid;
  if (uid == null) return;

  final eventRef = db.collection('events').doc(eventId);
  final attendeeRef = eventRef.collection('attendees').doc(uid);

  final doc = await attendeeRef.get();

  // 🚫 já entrou → não faz nada
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

  // 🚫 não está dentro → não faz nada
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
    required String cc,
    required String city,
    required String place,
    required Timestamp? startAt,
    required String desc,
    required int attendees,
    required String coverUrl,
    required List<String> photoUrls,
  }) {
    final t = AppTexts.current;


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
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: _border),
  boxShadow: const [
    BoxShadow(
      color: Color(0x0A000000),
      blurRadius: 14,
      offset: Offset(0, 8),
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
                if (images.isNotEmpty) ...[
                  SizedBox(
                    height: 190,
                    child: PageView.builder(
                      itemCount: images.length > 6 ? 6 : images.length,
                      controller: PageController(viewportFraction: 1),
                      itemBuilder: (_, i) {
                        final url = images[i];
                       

return GestureDetector(
  onTap: () => _openEventGallery(images, i),
  child: ClipRRect(
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
                        )
);
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Text(
                      _flagEmoji(cc.isEmpty ? 'BR' : cc),
                      style: const TextStyle(fontSize: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                     child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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

    return Text(
      joined ? t.get('you_are_going') : '$attendees',
      style: TextStyle(
        fontWeight: FontWeight.w900,
        color: joined ? _remdyBlue : _text,
        fontSize: joined ? 11 : 14,
      ),
    );
  },
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
                if (city.isNotEmpty)
                  _InfoRow(icon: Icons.location_city_rounded, text: city),
                if (place.isNotEmpty)
                  _InfoRow(icon: Icons.place_rounded, text: place),
                _InfoRow(
                  icon: Icons.people_alt_rounded,
                  text: '$attendees ${t.get('participating')}',
                ),
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
                       onPressed: _uid == null
    ? null
    : () => joined ? _leaveEvent(eventId) : _joinEvent(eventId),


                        style: ElevatedButton.styleFrom(
                          backgroundColor: joined ? const Color(0xFFEFF6FF) : _remdyBlue,
                         foregroundColor: joined ? _remdyBlue : Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          _uid == null
                              ? t.get('login_to_join')
                              : (joined ? 'Cancelar' : t.get('join')),
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
    final t = AppTexts.current;
    final displayCity = _selectedCity.isNotEmpty ? _selectedCity : '';


    return Scaffold(
      backgroundColor: _bg,
     appBar: AppBar(
  backgroundColor: _bg,
  surfaceTintColor: _bg,
  scrolledUnderElevation: 0,
  elevation: 0,
  title: Row(
    children: [
      Text(
        t.get('events'),
        style: const TextStyle(
          color: _text,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(width: 8),
      Row(
  children: [
    const Icon(Icons.location_on, size: 16),
    const SizedBox(width: 4),
   
Text(
  _selectedEventScope == 0
      ? (displayCity.isNotEmpty ? displayCity : 'Cidade')
      : _selectedEventScope == 1
          ? 'Ao redor (${_getRegionFromCity(displayCity)})'
          : 'País',
)

  ],
)

    ],
  ),
  iconTheme: const IconThemeData(color: _muted),
),

body: FutureBuilder<

DocumentSnapshot<Map<String, dynamic>>>(
  future: db.collection('users').doc(_uid).get(),
  builder: (context, userSnap) {
    if (userSnap.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    final userData = userSnap.data?.data() ?? {};
    if (_selectedCity.isEmpty) {
  final savedCity = (userData['cityName'] ??
          userData['city'] ??
          '')
      .toString()
      .trim();

  if (savedCity.isNotEmpty) {
    _selectedCity = savedCity;
  }
}

if (_selectedCity.isEmpty) {
  final savedCity = (userData['cityName'] ??
          userData['city'] ??
          userData['displayLocation'] ??
          '')
      .toString()
      .trim();

  if (savedCity.isNotEmpty) {
    _selectedCity = savedCity;
  }
}



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

    final selectedCityFinal =
    _selectedCity.isNotEmpty ? _selectedCity : myCity;

 return Column(
  children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          children: [
          _eventScopeChip(0, selectedCityFinal.isNotEmpty ? selectedCityFinal : 'Cidade'),
_eventScopeChip(1, 'Ao redor'),
_eventScopeChip(2, 'País'),

          ],
        ),
      ),
    ),
    Expanded(
      child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
  future: _selectedEventScope == 0
    ? _loadEventsWithFallback(myCountry, selectedCityFinal)
    : _selectedEventScope == 1
        ? db
            .collection('events')
            .where('isActive', isEqualTo: true)
            .where('countryCode', isEqualTo: myCountry)
            .where('scope', isEqualTo: 'region')
            .where(
              'regionKey',
              isEqualTo: _getRegionFromCity(selectedCityFinal),
            )
            .limit(50)
            .get()
        : db
            .collection('events')
            .where('isActive', isEqualTo: true)
            .where('countryCode', isEqualTo: myCountry)
            .where('scope', isEqualTo: 'country')
            .limit(50)
            .get(),


       

  builder: (context, snap) {

          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }


          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${t.get('error')}: ${snap.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            );
          }
      

          final docs = snap.data?.docs ?? [];
         if (docs.isEmpty) {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.event_busy_rounded, size: 38, color: _muted),
        const SizedBox(height: 10),
        Text(
          _selectedEventScope == 0
              ? 'Sem eventos em ${displayCity.isNotEmpty ? displayCity : 'sua cidade'}'
              : 'Sem eventos disponíveis',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _selectedEventScope == 0
              ? 'Mostrando eventos ao redor'
              : 'Tente outra aba',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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


              final title = (data['title'] ?? t.get('event')).toString();
              final city = (data['city'] ?? '').toString();
              final place = (data['placeName'] ?? '').toString();
              final cc = (data['countryCode'] ?? '').toString();
              final startAt = data['startAt'] as Timestamp?;
              final desc = (data['description'] ?? '').toString();
              final attendees = (data['attendeesCount'] is int)
    ? data['attendeesCount'] as int
    : 0;

final badge = _eventBadge(startAt, attendees);



          final rawPhotos = data['photoUrls'];

final photoUrls = (rawPhotos is List)
    ? rawPhotos
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList()
    : <String>[];

final coverUrl = photoUrls.isNotEmpty ? photoUrls.first : '';



              return InkWell(
                borderRadius: BorderRadius.circular(18),
onTap: () {
  _openDetails(
    eventId: d.id,
    title: title,
    cc: cc,
    city: city,
    place: place,
    startAt: startAt,
    desc: desc,
    attendees: attendees,
    coverUrl: coverUrl,
    photoUrls: photoUrls,
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
                      ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(18),
                          bottomLeft: Radius.circular(18),
                        ),
                        child: Container(
                          width: 105,
                          height: 96,
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
                                  child: Icon(
                                    Icons.event_rounded,
                                    color: Color(0xFF94A3B8),
                                  ),
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
                                  fontSize: 16,
                                  color: _text,
                                ),
                              ),
                              if (badge.isNotEmpty)
  Container(
    margin: const EdgeInsets.only(top: 4),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F5F9),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      badge,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
      ),
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
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                place.isEmpty ? t.get('place_to_be_defined') : place,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                               style: const TextStyle(
  color: _text,
  fontWeight: FontWeight.w700,
  fontSize: 13,
),

                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
  padding: const EdgeInsets.only(right: 12),
  child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream: (_uid == null)
        ? const Stream.empty()
        : db
            .collection('events')
            .doc(d.id)
            .collection('attendees')
            .doc(_uid)
            .snapshots(),
    builder: (context, snap) {
      final joined = snap.data?.exists == true;

      return Column(
        children: [
          Text(
            _flagEmoji(cc.isEmpty ? 'BR' : cc),
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: joined ? null : () => _joinEvent(d.id),
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: joined ? const Color(0xFFEFF6FF) : _remdyBlue,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: joined ? const Color(0xFFBFDBFE) : _remdyBlue,
                ),
              ),
              child: Text(
                joined ? t.get('you_are_going') : t.get('join'),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  color: joined ? _remdyBlue : Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    },
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
