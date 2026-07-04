import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import '../l10n/app_texts.dart';


class CreateEventPage extends StatefulWidget {
  const CreateEventPage({super.key});

  @override
  State<CreateEventPage> createState() => _CreateEventPageState();
}

class _CreateEventPageState extends State<CreateEventPage> {
  final _formKey = GlobalKey<FormState>();

  final _titleC = TextEditingController();
  final _descC = TextEditingController();
  final _cityC = TextEditingController();
  final _placeC = TextEditingController();
  final _citySearchC = TextEditingController();
  final ImagePicker _picker = ImagePicker();

List<XFile> _pickedEventPhotos = [];


String _eventCityName = '';
double? _eventLat;
double? _eventLng;

String _eventStateName = '';
String _eventDisplayLocation = '';


String _eventPlaceName = '';
String _eventAddress = '';
String _eventPlaceDisplay = '';
String _eventCountryName = '';

String _countryCodeFromName(String countryName) {
  final v = countryName.trim().toLowerCase();

  if (v.contains('brazil') || v.contains('brasil')) return 'br';
  if (v.contains('canada') || v.contains('canadá')) return 'ca';
  if (v.contains('portugal')) return 'pt';
  if (v.contains('france') || v.contains('frança')) return 'fr';
  if (v.contains('spain') || v.contains('espanha')) return 'es';
  if (v.contains('united states') || v.contains('estados unidos')) return 'us';
  if (v.contains('italy') || v.contains('itália')) return 'it';

  return 'br';
}



static const String _googlePlacesApiKey = 'AIzaSyCCu5KXXT2tSqL4kqwjDX6ySv49lqyCLs0';


  String _category = 'Show';
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  bool _sponsorInterested = false;
  bool _saving = false;

  static const Color _bg = Color(0xFFF6F7FB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void dispose() {
    _titleC.dispose();
    _descC.dispose();
    _cityC.dispose();
    _placeC.dispose();
    _citySearchC.dispose();
    super.dispose();
  }


Future<void> _pickEventPhotos() async {
  final picked = await _picker.pickMultiImage(
    imageQuality: 80,
  );

  if (picked.isEmpty) return;

  setState(() {
    _pickedEventPhotos = picked.take(5).toList();
  });
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

  Future<void> _pickDate() async {
    final now = DateTime.now();

final date = await showDatePicker(
  context: context,
  builder: (context, child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF313A5F),
        ),
      ),
      child: child!,
    );
  },
  initialDate: now.add(const Duration(days: 1)),
  firstDate: now,
  lastDate: now.add(const Duration(days: 365)),
);




    if (date == null) return;

    setState(() {
      _selectedDate = date;
    });
  }

  Future<void> _pickTime() async {
final time = await showTimePicker(
  context: context,
  builder: (context, child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF313A5F),
        ),
      ),
      child: child!,
    );
  },
  initialTime: const TimeOfDay(
    hour: 19,
    minute: 0,
  ),
);



    if (time == null) return;

    setState(() {
      _selectedTime = time;
    });
  }

  Future<void> _saveEvent() async {
    final uid = _uid;
    if (uid == null) return;

    if (!_formKey.currentState!.validate()) return;

    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escolha a data e o horário do evento.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final userSnap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();

      final userData = userSnap.data() ?? {};

final countryCode = _countryCodeFromName(_eventCountryName).toLowerCase();

  



    final city = _eventCityName.trim().toLowerCase();
    final regionKey = _getRegionFromCity(city);
    final cityKey = city;




      final startAt = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );
List<String> uploadedPhotos = [];

for (final photo in _pickedEventPhotos) {
  final fileName =
      '${DateTime.now().millisecondsSinceEpoch}_${uploadedPhotos.length}.jpg';

  final ref = FirebaseStorage.instance
      .ref()
      .child('events')
      .child(uid)
      .child(fileName);

  await ref.putFile(
  File(photo.path),
  SettableMetadata(
    contentType: 'image/jpeg',
  ),
);


  final url = await ref.getDownloadURL();

  uploadedPhotos.add(url);
}

final coverUrl =
    uploadedPhotos.isNotEmpty ? uploadedPhotos.first : '';


      await FirebaseFirestore.instance.collection('events').add({
        'city': city,
'cityKey': cityKey,
'stateName': _eventStateName,

'title': _titleC.text.trim(),
'description': _descC.text.trim(),
'category': _category,


'placeName': _placeC.text.trim(),
'address': _eventAddress,
'placeDisplay': _eventPlaceDisplay,
'lat': _eventLat,
'lng': _eventLng,

'countryCode': countryCode,
'regionKey': regionKey,
'scope':'city',


        

        // aprovação admin
        'status': 'pending',
        'isActive': false,

        // dat
        'startAt': Timestamp.fromDate(startAt),

        // autor
        'createdBy': uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),

        // presença
        'attendeesCount': 0,
        'attendeesUids': <String>[],

        // fotos vamos ligar depois
        
'coverUrl': coverUrl,
'photoUrls': uploadedPhotos,



        // patrocinado
        'sponsorInterested': _sponsorInterested,
        'sponsorStatus': _sponsorInterested ? 'interested' : 'none',
        'sponsored': false,
        'featured': false,
        'featuredUntil': null,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
     


SnackBar(
  content: Text(
    AppTexts.current.get('create_event_success'),
  ),

),



      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
    

SnackBar(
  content: Text(
    AppTexts.current.get('create_event_error'),
  ),
),
);

    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _inputDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _remdyBlue),
      ),
    );
  }
  Future<List<_CitySuggestion>> _searchCities(String input) async {
  final q = input.trim();

  if (q.length < 2) {
    return [];
  }

  final user = FirebaseAuth.instance.currentUser;
  String userCountryCode = 'CA';

  if (user != null) {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    final data = snap.data() ?? {};

    userCountryCode = (data['countryCode'] ??
            data['homeCountryCode'] ??
            'ca')
        .toString()
        .trim()
        .toUpperCase();
  }

  Future<List<_CitySuggestion>> search({String? countryCode}) async {
    final components = countryCode == null || countryCode.trim().isEmpty
        ? ''
        : '&components=country:${countryCode.trim().toUpperCase()}';

    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json'
      '?input=${Uri.encodeComponent(q)}'
     '&types=geocode'
      '$components'
      '&language=pt-BR'
      '&key=$_googlePlacesApiKey',
    );

    final res = await http.get(url);

    debugPrint('PLACES STATUS: ${res.statusCode}');
    debugPrint('PLACES BODY: ${res.body}');

    if (res.statusCode != 200) {
      return [];
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;

    final predictions =
        (data['predictions'] as List<dynamic>?) ?? [];

    return predictions.map((p) {
      final description =
          (p['description'] ?? '').toString();

      final parts =
          description.split(',').map((e) => e.trim()).toList();

      final cityName = parts.isNotEmpty ? parts[0] : '';
      final stateName = parts.length >= 2 ? parts[1] : '';
      final countryName =
          parts.length >= 3 ? parts.last : countryCode ?? '';

      return _CitySuggestion(
        cityName: cityName,
        stateName: stateName,
        countryName: countryName,
        display: description,
      );
    }).where((e) {
      return e.cityName.isNotEmpty;
    }).toList();
  }

  final localResults = await search(countryCode: userCountryCode);

  if (localResults.isNotEmpty) {
    return localResults;
  }

  return search();
}



Future<_PlaceSuggestion?> _openPlaceSearch() async {
  final searchC = TextEditingController();
  List<_PlaceSuggestion> results = [];
  bool loading = false;

  return showModalBottomSheet<_PlaceSuggestion>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> runSearch(String value) async {
            if (value.trim().length < 2) {
              setModalState(() {
                results = [];
                loading = false;
              });
              return;
            }

            setModalState(() => loading = true);

            final found = await _searchPlaces(value);

            setModalState(() {
              results = found;
              loading = false;
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: Column(
                children: [
                  TextField(
                    controller: searchC,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Local',
                      hintText: 'Digite nome do lugar ou endereço',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.place),
                    ),
                    onChanged: runSearch,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : results.isEmpty
                            ? const Center(
                                child: Text('Digite pelo menos 2 letras'),
                              )
                            : ListView.builder(
                                itemCount: results.length,
                                itemBuilder: (context, i) {
                                  final item = results[i];

                                  return ListTile(
                                    title: Text(item.placeName),
                                    subtitle: Text(item.address),
                                    onTap: () {
                                      Navigator.pop(sheetContext, item);
                                    },
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
  );
}



Future<_CitySuggestion?> _openCitySearch() async {
  final searchC = TextEditingController();

  List<_CitySuggestion> results = [];

  bool loading = false;

return showModalBottomSheet<_CitySuggestion>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.white,
  builder: (sheetContext) {
    return StatefulBuilder(
      builder: (context, setModalState) {
        Future<void> runSearch(String value) async {
          if (value.trim().length < 2) {
            setModalState(() {
              results = [];
              loading = false;
            });
            return;
          }

          setModalState(() => loading = true);

          final found = await _searchCities(value);

          setModalState(() {
            results = found;
            loading = false;
          });
        }

        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.75,
            child: Column(
              children: [
                TextField(
                  controller: searchC,
                  autofocus: true,
                  decoration:  InputDecoration(
                  labelText: AppTexts.current.get('create_event_city'),
                  hintText: AppTexts.current.get('create_event_city_search_hint'),
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: runSearch,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: loading
                      ? const Center(child: CircularProgressIndicator())
                      : results.isEmpty
                          ? const Center(
                              child: Text('Digite pelo menos 2 letras'),
                            )
                          : ListView.builder(
                              itemCount: results.length,
                              itemBuilder: (context, i) {
                                final item = results[i];

                                return ListTile(
                                  title: Text(item.display),
                                  onTap: () {
                                    Navigator.pop(sheetContext, item);
                                  },
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
);

  
}


Future<List<_PlaceSuggestion>> _searchPlaces(String input) async {
  final q = input.trim();

  if (q.length < 2) return [];

  final cityContext = _eventDisplayLocation.isNotEmpty
      ? _eventDisplayLocation
      : _eventCityName;

  final query = cityContext.isNotEmpty ? '$q $cityContext' : q;
final placeCountryCode = _countryCodeFromName(_eventCountryName).toUpperCase();

final url = Uri.parse(
  'https://maps.googleapis.com/maps/api/place/autocomplete/json'
  '?input=${Uri.encodeComponent(query)}'
  '&types=address'
  '&components=country:$placeCountryCode'
  '&language=pt-BR'
  '&key=$_googlePlacesApiKey',
);


  final res = await http.get(url);

  if (res.statusCode != 200) return [];

  final data = jsonDecode(res.body) as Map<String, dynamic>;
  final predictions = (data['predictions'] as List<dynamic>? ?? []);

  return predictions.map((p) {
    final description = (p['description'] ?? '').toString();
    final mainText =
        (p['structured_formatting']?['main_text'] ?? description).toString();

    return _PlaceSuggestion(
  placeName: mainText,
  address: description,
  display: description,
  placeId: (p['place_id'] ?? '').toString(),
);

  }).where((e) => e.display.isNotEmpty).toList();
}
Future<void> _loadPlaceLatLng(String placeId) async {
  if (placeId.isEmpty) return;

  final url = Uri.parse(
    'https://maps.googleapis.com/maps/api/place/details/json'
    '?place_id=${Uri.encodeComponent(placeId)}'
    '&fields=geometry'
    '&key=$_googlePlacesApiKey',
  );

  final res = await http.get(url);

  if (res.statusCode != 200) return;

  final data = jsonDecode(res.body) as Map<String, dynamic>;

  final location = data['result']?['geometry']?['location'];

  if (location == null) return;

  setState(() {
    _eventLat = (location['lat'] as num?)?.toDouble();
    _eventLng = (location['lng'] as num?)?.toDouble();
  });
}


  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current.get;
    final dateText = _selectedDate == null
        ? t('create_event_pick_date')
        : '${_selectedDate!.day.toString().padLeft(2, '0')}/${_selectedDate!.month.toString().padLeft(2, '0')}/${_selectedDate!.year}';

    final timeText = _selectedTime == null
    ? t('create_event_pick_time')
    : '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}';


    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          t('create_event_title'),
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                 Text(
                  t('create_event_intro'),
                  style: TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),

                TextFormField(
                  controller: _titleC,
                  decoration: _inputDecoration(
                    t('create_event_name'),
                    hint:t('create_event_name_hint'),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Digite o título.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  value: _category,
                  dropdownColor: Colors.white,
borderRadius: BorderRadius.circular(16),
menuMaxHeight: 260,

                  decoration: _inputDecoration(t('create_event_category')),
                 
items: [
  DropdownMenuItem(
    value: 'Restaurante',
    child: Text(t('event_category_restaurant')),
  ),
  DropdownMenuItem(
    value: 'café',
    child: Text(t('event_category_cafe')),
  ),
  DropdownMenuItem(
    value: 'Esportes',
    child: Text(t('event_category_sports')),
  ),
  DropdownMenuItem(
    value: 'Show',
    child: Text(t('event_category_show')),
  ),
],

                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _category = v);
                  },
                ),
                const SizedBox(height: 12),

 TextFormField(
  controller: _citySearchC,
  readOnly: true,
  decoration: _inputDecoration(
    t('create_event_city'),
    hint: t('create_event_city_hint'),
  ),
  onTap: () async {
    final result = await _openCitySearch();

    if (result != null) {
      setState(() {
        _eventCityName = result.cityName;
        _eventStateName = result.stateName;
        _eventDisplayLocation = result.display;
        _citySearchC.text = result.display;
        _eventCountryName = result.countryName;
      });
    }
  },
),



                const SizedBox(height: 12),

               
TextFormField(
  controller: _placeC,
  readOnly: true,
  onTap: () async {
    final result = await _openPlaceSearch();

if (result != null) {
  setState(() {
    _placeC.text = result.placeName;
    _cityC.text = _eventCityName;

    _eventPlaceName = result.placeName;
    _eventAddress = result.address;
    _eventPlaceDisplay = result.display;
  });

  await _loadPlaceLatLng(result.placeId);
}


  },
  decoration: _inputDecoration(
    t('create_event_place'),
    hint:t('create_event_place_hint')
  ),
),

InkWell(
  onTap: _pickEventPhotos,
  borderRadius: BorderRadius.circular(14),
  child: Container(
    height: 120,
    width: double.infinity,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _border),
    ),
    child: _pickedEventPhotos.isEmpty
        ?  Center(
            child: Text(
             t('create_event_add_photos'), 
              style: TextStyle(
                fontWeight: FontWeight.w800,
              ),
            ),
          )
        : ListView.separated(
            padding: const EdgeInsets.all(8),
            scrollDirection: Axis.horizontal,
            itemCount: _pickedEventPhotos.length,
            separatorBuilder: (_, __) =>
                const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final photo = _pickedEventPhotos[index];

              return ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(
                  File(photo.path),
                  width: 160,
                  fit: BoxFit.cover,
                ),
              );
            },
          ),
  ),
),


const SizedBox(height: 12),


                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_month),
                        label: Text(dateText),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickTime,
                        icon: const Icon(Icons.schedule),
                        label: Text(timeText),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _descC,
                  minLines: 4,
                  maxLines: 7,
                  decoration: _inputDecoration(
                   t('create_event_description'),
                    hint: t('create_event_description_hint'),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Digite uma descrição.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       Text(
                        t('create_event_promote_title'),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: _text,
                        ),
                      ),
                      const SizedBox(height: 6),
                       Text(
                       t('create_event_promote_text'),
                        style: TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: _sponsorInterested,
                        contentPadding: EdgeInsets.zero,
                        title:  Text(
                         t('create_event_promote_checkbox'),
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        controlAffinity: ListTileControlAffinity.leading,
                        onChanged: (v) {
                          setState(() {
                            _sponsorInterested = v ?? false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveEvent,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _remdyBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            t('create_event_submit'),
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CitySuggestion {
  final String cityName;
  final String stateName;
  final String countryName;
  final String display;

  const _CitySuggestion({
    required this.cityName,
    required this.stateName,
    required this.countryName,
    required this.display,
  });
}
class _PlaceSuggestion {
  final String placeName;
  final String address;
  final String display;
  final String placeId;


const _PlaceSuggestion({
  required this.placeName,
  required this.address,
  required this.display,
  required this.placeId,
});

}
