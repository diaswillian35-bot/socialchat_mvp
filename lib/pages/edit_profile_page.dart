import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/countries_data.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';



import 'splash_page.dart';
import 'login_page.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {

final _formKey = GlobalKey<FormState>();

static const Color _bg = Color(0xFFF6F7FB);
static const Color _text = Color(0xFF111827);
static const Color _muted = Color(0xFF6B7280);
static const Color _border = Color(0xFFE5E7EB);


static const LinearGradient _primaryGradient = LinearGradient(
  colors: [
    Color(0xFF313A5F),
    Color(0xFF264E9A),
  ],
);
 
final _nameC = TextEditingController();
final _ageC = TextEditingController();
final _languagesC = TextEditingController();
final _aboutC = TextEditingController();
final _countrySearchC = TextEditingController();


final _citySearchC = TextEditingController();

String _normalizeText(String value) {
  return value
      .toLowerCase()
      .trim()
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('ã', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ä', 'a')
      .replaceAll('é', 'e')
      .replaceAll('è', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('ë', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ì', 'i')
      .replaceAll('î', 'i')
      .replaceAll('ï', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ò', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('ö', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ù', 'u')
      .replaceAll('û', 'u')
      .replaceAll('ü', 'u')
      .replaceAll('ç', 'c');
}

String _stateName = '';
String _cityName = '';
String _displayLocation = '';



bool _nearbyEnabled = false;
  



  bool _loading = true;
  bool _saving = false;
  String? _err;

  




 // ✅ país uma vez
String _homeCountryCode = '';
bool _countryLocked = false;
static const String _googlePlacesApiKey = 'AIzaSyCCu5KXXT2tSqL4kqwjDX6ySv49lqyCLs0';

String? get _myUid => FirebaseAuth.instance.currentUser?.uid;


final List<CountryData> _countries = countriesData;




  @override
  void initState() {
    super.initState();
    _load();
    
  }
DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
    FirebaseFirestore.instance.collection('users').doc(uid);


DocumentReference<Map<String, dynamic>> _publicDoc(String uid) =>
    FirebaseFirestore.instance.collection('publicUsers').doc(uid);


CollectionReference<Map<String, dynamic>> get _countriesCol =>
    FirebaseFirestore.instance.collection('configCountries');


  final List<CountryData> countries = countriesData;    


 Future<void> _load() async {
  setState(() {
    _loading = true;
    _err = null;
  });


  try {
    
    final uid = _myUid;

      if (uid == null) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  });
  return;
}


      final snap = await _userDoc(uid).get();
      final data = snap.data() ?? {};

      _nameC.text = (data['name'] ?? '').toString();
      _ageC.text = (data['age'] ?? '').toString();

      // ✅ substitui nativeLanguage/studying por languages
      final languages = (data['languages'] ?? data['nativeLanguage'] ?? '').toString();
_languagesC.text = languages;


_aboutC.text = (data['about'] ?? '').toString();


_stateName = (data['stateName'] ?? '').toString().trim();
_cityName = (data['cityName'] ?? '').toString().trim();
_displayLocation = (data['displayLocation'] ?? '').toString().trim();
_citySearchC.text = _displayLocation.isNotEmpty ? _displayLocation : _cityName;


_nearbyEnabled = data['nearbyEnabled'] == true;



_countryLocked = data['countryLocked'] == true;


final savedHomeCountry =
    (data['homeCountryCode'] ?? '').toString().trim().toLowerCase();
final savedCountryCode =
    (data['countryCode'] ?? '').toString().trim().toLowerCase();


// só reaproveita país salvo se já estiver travado
if (_countryLocked) {
  _homeCountryCode =
      savedHomeCountry.isNotEmpty ? savedHomeCountry : savedCountryCode;
} else {
  _homeCountryCode = '';
}





    } catch (e) {
      _err = 'Erro ao carregar perfil: $e';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _flagEmoji(String code) {
    final upper = code.toUpperCase();
    if (upper.length != 2) return '🏳️';
    final first = upper.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final second = upper.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCodes([first, second]);
  }

  String _countryNameFromCode(String code) {
    for (final c in _countries) {
      if (c.code == code.toLowerCase()) return c.name;
    }
    return 'Selecione';
  }

  Future<void> _openCountrySheet() async {
  if (_countryLocked) return;


  final picked = await showModalBottomSheet<CountryData>(

      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
  


  return StatefulBuilder(
    builder: (context, setModalState) {
  final query = _normalizeText(_countrySearchC.text);


final filteredCountries = _countries.where((c) {
  final name = _normalizeText(c.name);
  final code = _normalizeText(c.code);


  return query.isEmpty ||
      name.contains(query) ||
      name.startsWith(query) ||
      code == query ||
      code.contains(query);
}).toList();



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
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: const Icon(Icons.flag_rounded, color: Color(0xFF313A5F)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Escolha seu país',
                      style: TextStyle(
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
                controller: _countrySearchC,
                onChanged: (_) => setModalState(() {}),
                decoration: InputDecoration(
                  hintText: 'Buscar país',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filteredCountries.isEmpty
                    ? const Center(
                        child: Text(
                          'Nenhum país encontrado',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredCountries.length,
                        itemBuilder: (context, i) {
                          final c = filteredCountries[i];
                          final isSelected = c.code == _homeCountryCode;


                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 2,
                            ),
                            title: Text(
                              c.name,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                                color: isSelected
                                    ? const Color(0xFF264E9A)
                                    : const Color(0xFF111827),
                              ),
                            ),
                            trailing: isSelected
                                ? const Icon(
                                    Icons.check_circle,
                                    color: Color(0xFF264E9A),
                                  )
                                : null,
                            onTap: () => Navigator.pop(context, c),
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

    if (picked == null) return;

    setState(() {
  _homeCountryCode = picked.code;


  _cityName = '';
  _stateName = '';
  _displayLocation = '';
  _citySearchC.clear();
});

  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _err = null;
    });

    try {
      final uid = _myUid;
      if (uid == null) {
        setState(() => _err = 'Você precisa estar logado para salvar o perfil.');
        return;
      }

      final name = _nameC.text.trim();
      final languages = _languagesC.text.trim();
      final about = _aboutC.text.trim();

      final ageText = _ageC.text.trim();
      int? age;
      if (ageText.isNotEmpty) {
        age = int.tryParse(ageText);
      }

      final authUser = FirebaseAuth.instance.currentUser;
      final email = authUser?.email ?? '';
      final photoUrl = authUser?.photoURL ?? '';

      final now = FieldValue.serverTimestamp();

      final userSnap = await _userDoc(uid).get();
      final userData = userSnap.data() ?? {};
      final hasUserCreatedAt =
          userData.containsKey('createdAt') && userData['createdAt'] != null;

      final pubSnap = await _publicDoc(uid).get();
      final pubData = pubSnap.data() ?? {};
      final hasPubCreatedAt =
          pubData.containsKey('createdAt') && pubData['createdAt'] != null;

      final existingLocked = userData['countryLocked'] == true;
      final existingHome =
          (userData['homeCountryCode'] ?? '').toString().trim().toLowerCase();

      String finalHomeCode = existingHome;
      bool finalLocked = existingLocked;

 


      if (!existingLocked || existingHome.isEmpty) {
        if (_homeCountryCode.isEmpty) {
          setState(() => _err = 'Selecione seu país.');
          return;
        }
        finalHomeCode = _homeCountryCode;
        finalLocked = true;
      }

      final countryName = _countryNameFromCode(finalHomeCode);

      final countryRef = _countriesCol.doc(finalHomeCode);
final countrySnap = await countryRef.get();


if (!countrySnap.exists) {
  await countryRef.set({
    'code': finalHomeCode,
    'name': countryName,
    'flag': finalHomeCode.toUpperCase(),
    'createdBy': uid,
    'createdAt': FieldValue.serverTimestamp(),
    'usersCount': 1,
  });
} else {
  await countryRef.update({
    'usersCount': FieldValue.increment(1),
  });
}

final userPayload = <String, dynamic>{
  'uid': uid,
  'name': name,
  'age': age,
  'languages': languages,
  'about': about,
  'country': countryName,
  'homeCountryCode': finalHomeCode,
  'countryCode': finalHomeCode,
  'stateName': _stateName,
  'cityName': _cityName,
  'displayLocation': _displayLocation,
  'nearbyEnabled': _nearbyEnabled,
  'countryLocked': finalLocked,
  'profileComplete': true,
  'updatedAt': now,
};


      // compatibilidade com partes antigas do app
      userPayload['nativeLanguage'] = languages;

      if (!hasUserCreatedAt) {
        userPayload['createdAt'] = now;
      }

      await _userDoc(uid).set(userPayload, SetOptions(merge: true));

      final publicPayload = <String, dynamic>{
  'uid': uid,
  'name': name,
  'country': countryName,
  'countryCode': finalHomeCode,
  'city': _cityName,
  'state': _stateName,
  'location': _displayLocation,
  'nearbyEnabled': _nearbyEnabled,
  'about': about,
  'languages': languages,
  'nativeLanguage': languages,
  'isOnline': true,
  'lastSeenAt': now,
  'email': email,
  'photoUrl': photoUrl,
  'updatedAt': now,
};


      if (!hasPubCreatedAt) {
        publicPayload['createdAt'] = now;
      }

      await _publicDoc(uid).set(publicPayload, SetOptions(merge: true));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil salvo ✅')),
      );

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const SplashPage()),
        (_) => false,
      );
    } catch (e) {
      setState(() => _err = 'Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
  

_nameC.dispose();
_ageC.dispose();
_languagesC.dispose();
_aboutC.dispose();
_countrySearchC.dispose();
_citySearchC.dispose();
super.dispose();


  }

  InputDecoration _deco(String label, {String? hint, String? helper}) {
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
      borderSide: const BorderSide(color: Color(0xFF264E9A), width: 1.4),
    ),
  );
}


  Widget _countryField() {
    final countryName = _countryNameFromCode(_homeCountryCode);
   final flag = _homeCountryCode.isEmpty ? '🏳️' : _flagEmoji(_homeCountryCode);

    return InkWell(
      onTap: _countryLocked ? null : _openCountrySheet,
      borderRadius: BorderRadius.circular(6),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'País',
          helperText: _countryLocked
              ? 'Seu país está travado.'
              : 'Defina seu país UMA vez. Depois ficará travado.',
          border: const OutlineInputBorder(),
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                countryName,
                style: const TextStyle(
                  fontSize: 16,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            Icon(
              _countryLocked ? Icons.lock_outline : Icons.keyboard_arrow_down_rounded,
              color: const Color(0xFF6B7280),
            ),
          ],
        ),
      ),
    );
  }
Widget _nearbyField() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFD1D5DB)),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _nearbyEnabled,
          onChanged: (value) {
            setState(() {
              _nearbyEnabled = value;
            });
          },
          title: const Text(
            'Mostrar pessoas perto de mim',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF111827),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 6),
          child: Text(
            'Quando ativado, seu perfil pode aparecer para pessoas da sua cidade ou região.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
            ),
          ),
        ),
      ],
    ),
  );
}


Widget _cityField() {
  return TextFormField(
    controller: _citySearchC,
    readOnly: true,
    decoration: _deco(
  'Cidade',
  hint: 'Ex: Toronto',
),

  onTap: () async {
  final result = await _openCitySearch();


  if (result != null) {
    setState(() {
      _cityName = result.cityName;
      _stateName = result.stateName;
      _displayLocation = result.display;
      _citySearchC.text = result.display;
    });
  }
},

    validator: (v) {
      if ((v ?? '').trim().isEmpty) return 'Selecione sua cidade';
      return null;
    },
  );
}
Future<List<_CitySuggestion>> _searchCities(String input) async {
  final query = input.trim();
  final q = query.trim();


if (q.length < 2) {
  return [];
}




  if (_homeCountryCode.isEmpty) return [];


  final url = Uri.parse(
  'https://maps.googleapis.com/maps/api/place/autocomplete/json'
  '?input=${Uri.encodeComponent(q)}'
  '&components=country:${_homeCountryCode.toUpperCase()}'
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
    final stateName = parts.length >= 2 ? parts[1] : '';
    final countryName = parts.length >= 3 ? parts.last : _countryNameFromCode(_homeCountryCode);


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

Future<_CitySuggestion?> _openCitySearch() async {
  if (_homeCountryCode.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Selecione seu país primeiro.'),
      ),
    );
    return null;
  }


  final searchC = TextEditingController();
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
                      const Expanded(
                        child: Text(
                          'Escolha sua cidade',
                          style: TextStyle(
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
                      hintText: 'Buscar cidade',
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
                            ? const Center(
                                child: Text(
                                  'Digite pelo menos 2 letras da cidade',
                                  style: TextStyle(
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

  @override
  Widget build(BuildContext context) {
  if (_myUid == null) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  });


  return const Scaffold(
    body: Center(child: CircularProgressIndicator()),
  );
}



    if (_loading) {
      return Scaffold(
  backgroundColor: _bg,
  appBar: AppBar(
    backgroundColor: Colors.white,
    foregroundColor: _text,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
    title: const Text(
      'Completar perfil',
      style: TextStyle(
        color: _text,
        fontWeight: FontWeight.w900,
      ),
    ),
  ),

      );
    }

   return Scaffold(
  backgroundColor: _bg,
  appBar: AppBar(
    backgroundColor: Colors.white,
    foregroundColor: _text,
    elevation: 0,
    scrolledUnderElevation: 0,
    surfaceTintColor: Colors.transparent,
    title: const Text(
      'Completar perfil',
      style: TextStyle(
        color: _text,
        fontWeight: FontWeight.w900,
      ),
    ),
  ),

      body: ListView(
  padding: const EdgeInsets.all(16),
  children: [
    if (_err != null) ...[
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Text(
          _err!,
          style: TextStyle(
            color: Colors.red.shade900,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(height: 12),
    ],
    Form(
      key: _formKey,
      child: Column(
        children: [
       _countryField(),
const SizedBox(height: 12),


_cityField(),
const SizedBox(height: 12),


_nearbyField(),
const SizedBox(height: 12),


TextFormField(
  controller: _nameC,

            decoration: _deco('Nome completo'),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Digite seu nome completo';
              if (v.trim().length < 2) return 'Nome muito curto';
              return null;
            },
          ),

                const SizedBox(height: 12),

                TextFormField(
                  controller: _ageC,
                  keyboardType: TextInputType.number,
                  decoration: _deco('Idade'),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null;
                    final n = int.tryParse(t);
                    if (n == null) return 'Digite um número';
                    if (n < 13) return 'Idade mínima: 13';
                    if (n > 99) return 'Idade inválida';
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _languagesC,
                  decoration: _deco('Línguas que você fala'),
                ),
                const SizedBox(height: 12),

                TextFormField(
                  controller: _aboutC,
                  maxLines: 4,
                  decoration: _deco(
                    'Sobre você',
                    hint:
                        'Fale um pouco sobre você, o que gosta de fazer, para outras pessoas com perfil parecido com o seu... escreva algo legal.',
                  ),
                ),
                const SizedBox(height: 16),

                SizedBox(
  width: double.infinity,
  height: 48,
  child: Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(14),
      gradient: _primaryGradient,
    ),
    child: ElevatedButton.icon(
      onPressed: _saving ? null : _save,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
      icon: _saving
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.save, color: Colors.white),
      label: Text(
        _saving ? 'Salvando...' : 'Salvar',
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    ),
  ),
),

              ],
            ),
          ),
        ],
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


class _CountryItem {
  final String code;
  final String name;
  final String flag;


  const _CountryItem({
    required this.code,
    required this.name,
    required this.flag,
  });
}
