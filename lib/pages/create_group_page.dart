import 'dart:convert';
import 'dart:math';


import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;


import '../l10n/app_texts.dart';
import 'group_info_page.dart';


class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});


  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}


class _CreateGroupPageState extends State<CreateGroupPage> {
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);
  static const Color _logoBlue = Color(0xFF264E9A);


  String _selectedCountryCode2() {
  switch (_selectedCountry.trim().toLowerCase()) {
    case 'canada':
      return 'ca';
    case 'brasil':
      return 'br';
    case 'portugal':
      return 'pt';
    default:
      return '';
  }
}



  static const String _googlePlacesApiKey =
      'AIzaSyCCu5KXXT2tSqL4kqwjDX6ySv49lqyCLs0';


  final _nameC = TextEditingController();
  final _cityC = TextEditingController();
  final _bioC = TextEditingController();


  bool _loading = false;

String _selectedCountry = 'canada';
String _cityName = '';
String _stateName = '';
String _displayLocation = '';
double? _cityLatitude;
double? _cityLongitude;
String _cityPlaceId = '';

String _loadedLocaleCode = '';

String _groupScope = 'city'; // city | region | country

String _joinPolicy = 'open'; // open | approval | inviteOnly

  final List<Map<String, String>> _countries = const [
    {"code": "canada", "name": "Canadá", "iso2": "CA"},
    {"code": "brasil", "name": "Brasil", "iso2": "BR"},
    {"code": "portugal", "name": "Portugal", "iso2": "PT"},
    {"code": "estados unidos", "name": "Estados Unidos", "iso2": "US"},
    {"code": "espanha", "name": "Espanha", "iso2": "ES"},
    {"code": "franca", "name": "França", "iso2": "FR"},
    {"code": "italia", "name": "Itália", "iso2": "IT"},
    {"code": "uk", "name": "Reino Unido", "iso2": "GB"},
    {"code": "irlanda", "name": "Irlanda", "iso2": "IE"},
    {"code": "australia", "name": "Austrália", "iso2": "AU"},
  ];


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


  @override
  void dispose() {
    _nameC.dispose();
    _cityC.dispose();
    _bioC.dispose();
    super.dispose();
  }


  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
      ),
    );
  }


  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    final rand = Random();
    return String.fromCharCodes(
      Iterable.generate(6, (_) => chars.codeUnitAt(rand.nextInt(chars.length))),
    );
  }


  String _pretty(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    return t[0].toUpperCase() + t.substring(1);
  }
String _regionKeyFromState(String state) {
  final s = state.trim().toLowerCase();

  if (s.isEmpty) return 'default';

  return s
      .replaceAll(' ', '_')
      .replaceAll('.', '')
      .replaceAll('-', '_');
}


  InputDecoration _dec(String label, {String? hint, String? helper}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperStyle: const TextStyle(
        color: _muted,
        fontWeight: FontWeight.w600,
      ),
      labelStyle: const TextStyle(
        color: _muted,
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _logoBlue, width: 1.4),
      ),
    );
  }


  String _selectedCountryIso2() {
    final item = _countries.firstWhere(
      (e) => e['code'] == _selectedCountry,
      orElse: () => const {"code": "canada", "name": "Canadá", "iso2": "CA"},
    );
    return item['iso2'] ?? 'CA';
  }


  Future<List<_CitySuggestion>> _searchCities(String input) async {
    final q = input.trim();
    if (q.length < 2) return [];


    final countryIso2 = _selectedCountryIso2();


    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/place/autocomplete/json'
      '?input=${Uri.encodeComponent(q)}'
      '&components=country:$countryIso2'
      '&language=pt-BR'
      '&key=$_googlePlacesApiKey',
    );


    final res = await http.get(url);
    if (res.statusCode != 200) return [];


    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final predictions = (data['predictions'] as List<dynamic>? ?? []);


    return predictions.map((p) {
      final description = (p['description'] ?? '').toString();
      final parts = description.split(',').map((e) => e.trim()).toList();


      final cityName = parts.isNotEmpty ? parts[0] : '';
      final stateName = parts.length >= 3 ? parts[parts.length - 2] : '';
      final countryName = parts.isNotEmpty ? parts.last : '';


  
return _CitySuggestion(
  cityName: cityName,
  stateName: stateName,
  countryName: countryName,
  display: description,
  placeId: (p['place_id'] ?? '').toString(),
);



    }).where((e) => e.cityName.isNotEmpty).toList();
  }

Future<Map<String, double>?> _getCityCoordinates(String placeId) async {
  final id = placeId.trim();
  if (id.isEmpty) return null;

  final url = Uri.parse(
    'https://maps.googleapis.com/maps/api/place/details/json'
    '?place_id=${Uri.encodeComponent(id)}'
    '&fields=geometry'
    '&key=$_googlePlacesApiKey',
  );

  final res = await http.get(url);
  if (res.statusCode != 200) return null;

  final data = jsonDecode(res.body) as Map<String, dynamic>;
  final result = data['result'];

  if (result is! Map<String, dynamic>) return null;

  final geometry = result['geometry'];
  if (geometry is! Map<String, dynamic>) return null;

  final location = geometry['location'];
  if (location is! Map<String, dynamic>) return null;

  final lat = location['lat'];
  final lng = location['lng'];

  if (lat is! num || lng is! num) return null;

  return {
    'latitude': lat.toDouble(),
    'longitude': lng.toDouble(),
  };
}





  Future<_CitySuggestion?> _openCitySearch() async {
    final searchC = TextEditingController(text: _cityC.text.trim());
    List<_CitySuggestion> results = [];
    bool loading = false;


    return showModalBottomSheet<_CitySuggestion>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
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


            return SafeArea(
              child: Container(
                height: MediaQuery.of(context).size.height * 0.78,
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
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
                        Expanded(
                          child: Text(
                            AppTexts.t('create_group_choose_city'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF111827),
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: searchC,
                      autofocus: true,
                      onChanged: (v) async {
                        await runSearch(v);
                      },
                      decoration: InputDecoration(
                        hintText: AppTexts.t('create_group_search_city'),
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : results.isEmpty
                              ? Center(
                                  child: Text(
                                    AppTexts.t(
                                      'create_group_type_two_letters_city',
                                    ),
                                    style: const TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: results.length,
                                  itemBuilder: (context, i) {
                                    final item = results[i];


                                    return ListTile(
                                      title: Text(item.display),
                                      onTap: () {
                                        Navigator.pop(context, item);
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


  Future<void> _create() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _toast(AppTexts.t('create_group_need_login'));
      return;
    }


    final name = _nameC.text.trim();
    final city = _cityC.text.trim();
    final bio = _bioC.text.trim();
    final country = _selectedCountry.trim().toLowerCase();


    if (name.isEmpty) return _toast(AppTexts.t('create_group_enter_name'));
    if (name.length < 3) {
      return _toast(AppTexts.t('create_group_name_too_short'));
    }
    if (country.isEmpty) {
      return _toast(AppTexts.t('create_group_select_country'));
    }
    if (city.isEmpty) return _toast(AppTexts.t('create_group_enter_city'));


    setState(() => _loading = true);


    try {
      final inviteCode = _generateInviteCode();
      final now = FieldValue.serverTimestamp();


      final doc = FirebaseFirestore.instance.collection('groups').doc();

      final groupCountryCode = _selectedCountryCode2();


      await doc.set({
        'name': name,
        

'country': country,
'countryCode': groupCountryCode,

        'city': _cityName.isNotEmpty ? _cityName : city,
        'cityName': _cityName.isNotEmpty ? _cityName : city,
        'countryCode': groupCountryCode,
        'stateName': _stateName,
'displayLocation':
    _displayLocation.isNotEmpty ? _displayLocation : city,
   
'placeId': _cityPlaceId,
'latitude': _cityLatitude,
'longitude': _cityLongitude,


 
'scope': _groupScope,
'regionKey': _regionKeyFromState(_stateName),
'bio': bio,

        'avatarUrl': '',
        'avatarPath': '',
        'ownerId': user.uid,
        'admins': [user.uid],
        'members': [user.uid],
        'membersCount': 1,
        'inviteCode': inviteCode,
       
'isPrivate': _joinPolicy != 'open',
'joinPolicy': _joinPolicy,

        'deleted': false,
        'unread': {
          user.uid: 0,
        },
        'lastMessage': '',
        'lastSenderId': '',
        'lastMessageAt': null,
        'createdAt': now,
        'updatedAt': now,
      });


      await doc.collection('reads').doc(user.uid).set({
        'lastReadAt': now,
      }, SetOptions(merge: true));


     if (!mounted) return;

Navigator.pushReplacement(
  context,
  MaterialPageRoute(
    builder: (_) => GroupInfoPage(groupId: doc.id),
  ),
);

    } catch (e) {
      _toast('${AppTexts.t('create_group_error')}: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  @override
  Widget build(BuildContext context) {
    final selectedCountryName = _countries.firstWhere(
      (e) => e['code'] == _selectedCountry,
      orElse: () => const {"code": "canada", "name": "Canadá", "iso2": "CA"},
    )['name']!;


    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          AppTexts.t('create_group_title'),
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
          ),
        ),
        iconTheme: const IconThemeData(color: _muted),
      ),
      body: AbsorbPointer(
        absorbing: _loading,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_remdyBlue, _logoBlue],
                ),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(Icons.groups_rounded, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppTexts.t('create_group_banner'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _nameC,
              textInputAction: TextInputAction.next,
              decoration: _dec(
                AppTexts.t('create_group_name'),
                hint: AppTexts.t('create_group_name_hint'),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedCountry,
              decoration: _dec(
                AppTexts.t('country'),
                helper: AppTexts.t('create_group_country_helper'),
              ),
              dropdownColor: Colors.white,
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _muted),
              style: const TextStyle(
                color: _text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
              items: _countries.map((c) {
                return DropdownMenuItem<String>(
                  value: c['code'],
                  child: Text(
                    c['name']!,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _selectedCountry = v;
                  _cityName = '';
                  _stateName = '';
                  _displayLocation = '';
                  _cityC.clear();
                });
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cityC,
              readOnly: true,
              textInputAction: TextInputAction.next,
              decoration: _dec(
                AppTexts.t('city'),
                hint: AppTexts.t('city_example'),
              ),
       onTap: () async {
  final result = await _openCitySearch();
  if (result == null) return;

  final coords = await _getCityCoordinates(result.placeId);

  setState(() {
    _cityName = result.cityName;
    _stateName = result.stateName;
    _displayLocation = result.display;
    _cityPlaceId = result.placeId;

    _cityLatitude = coords?['latitude'];
    _cityLongitude = coords?['longitude'];

    _cityC.text = result.display;
  });
},



            ),

            
Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: const Color(0xFFF9FAFB),
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: _border),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        AppTexts.t('create_group_scope_title'),
        style: const TextStyle(
          color: _text,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: Text(AppTexts.t('create_group_scope_city')),
            selected: _groupScope == 'city',
            selectedColor: _logoBlue,
backgroundColor: Colors.white,
checkmarkColor: Colors.white,
side: const BorderSide(color: _border),
labelStyle: TextStyle(
  color: _groupScope == 'city'
      ? Colors.white
      : _remdyBlue,
  fontWeight: FontWeight.w700,
),

            onSelected: (_) => setState(() => _groupScope = 'city'),
          ),
          ChoiceChip(
  label: Text(AppTexts.t('create_group_scope_region')),
  selected: _groupScope == 'region',

  selectedColor: _logoBlue,
  backgroundColor: Colors.white,
  checkmarkColor: Colors.white,
  side: const BorderSide(color: _border),
  labelStyle: TextStyle(
    color: _groupScope == 'region'
        ? Colors.white
        : _remdyBlue,
    fontWeight: FontWeight.w700,
  ),

  onSelected: (_) => setState(() => _groupScope = 'region'),
),

        ChoiceChip(
  label: Text(AppTexts.t('create_group_scope_country')),
  selected: _groupScope == 'country',

  selectedColor: _logoBlue,
  backgroundColor: Colors.white,
  checkmarkColor: Colors.white,
  side: const BorderSide(color: _border),
  labelStyle: TextStyle(
    color: _groupScope == 'country'
        ? Colors.white
        : _remdyBlue,
    fontWeight: FontWeight.w700,
  ),

  onSelected: (_) => setState(() => _groupScope = 'country'),
),

        ],
      ),
    ],
  ),
),


const SizedBox(height: 12),
const SizedBox(height: 12),
Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: const Color(0xFFF9FAFB),
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: _border),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        AppTexts.t('create_group_entry'),
        style: const TextStyle(
          color: _text,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: Text(AppTexts.t('create_group_open')),
            selected: _joinPolicy == 'open',
            selectedColor: _logoBlue,
            backgroundColor: Colors.white,
            checkmarkColor: Colors.white,
            side: const BorderSide(color: _border),
            labelStyle: TextStyle(
              color: _joinPolicy == 'open' ? Colors.white : _remdyBlue,
              fontWeight: FontWeight.w700,
            ),
            onSelected: (_) => setState(() => _joinPolicy = 'open'),
          ),
          ChoiceChip(
            label: Text(AppTexts.t('admin_approval')),
            selected: _joinPolicy == 'approval',
            selectedColor: _logoBlue,
            backgroundColor: Colors.white,
            checkmarkColor: Colors.white,
            side: const BorderSide(color: _border),
            labelStyle: TextStyle(
              color: _joinPolicy == 'approval' ? Colors.white : _remdyBlue,
              fontWeight: FontWeight.w700,
            ),
            onSelected: (_) => setState(() => _joinPolicy = 'approval'),
          ),
          ChoiceChip(
            label: Text(AppTexts.t('invite_only')),
            selected: _joinPolicy == 'inviteOnly',
            selectedColor: _logoBlue,




            
            backgroundColor: Colors.white,
            checkmarkColor: Colors.white,
            side: const BorderSide(color: _border),
            labelStyle: TextStyle(
              color: _joinPolicy == 'inviteOnly' ? Colors.white : _remdyBlue,
              fontWeight: FontWeight.w700,
            ),
            onSelected: (_) => setState(() => _joinPolicy = 'inviteOnly'),
          ),
        ],
      ),
    ],
  ),
),

            const SizedBox(height: 12),
            TextField(
              controller: _bioC,
              maxLines: 4,
              decoration: _dec(
                AppTexts.t('create_group_bio'),
                hint: AppTexts.t('create_group_bio_hint'),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
              ),
              child: Text(
                '${AppTexts.t('country')}: ${_pretty(selectedCountryName)}\n'
                '${AppTexts.t('city')}: ${_cityName.isEmpty ? "--" : '$_cityName${_stateName.isNotEmpty ? ', $_stateName' : ''}'}\n'
                '${AppTexts.t('create_group_entry')}: ${_joinPolicy == 'open'
    ? AppTexts.t('create_group_open')
    : _joinPolicy == 'approval'
        ? AppTexts.t('admin_approval')
        : AppTexts.t('invite_only')}',

                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 48,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: const LinearGradient(
                    colors: [_remdyBlue, _logoBlue],
                  ),
                ),
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _create,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.group_add_rounded, color: Colors.white),
                  label: Text(
                    _loading
                        ? AppTexts.t('create_group_creating')
                        : AppTexts.t('create_group_button'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ],
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
  final String placeId;

  const _CitySuggestion({
    required this.cityName,
    required this.stateName,
    required this.countryName,
    required this.display,
    required this.placeId,
  });
}


