import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../l10n/app_texts.dart';
import '../services/group_create_flow.dart';
import '../services/group_creation_service.dart';
import '../services/group_places_client.dart';
import '../services/group_geo.dart';
import '../services/group_settings_service.dart';
import '../widgets/keyboard_dismiss.dart';
import '../widgets/remdy_keyboard_caps.dart';
import '../widgets/required_field.dart';
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
    final selected = _selectedCountry.trim().toLowerCase();
    final match = _countries.firstWhere(
      (country) => country['code']!.trim().toLowerCase() == selected,
      orElse: () => const {'iso2': ''},
    );
    return (match['iso2'] ?? '').trim().toLowerCase();
  }

  static const String _googlePlacesApiKey =
      'AIzaSyCCu5KXXT2tSqL4kqwjDX6ySv49lqyCLs0';

  final _nameC = TextEditingController();
  final _cityC = TextEditingController();
  final _bioC = TextEditingController();

  bool _loading = false;
  bool _inFlight = false;
  String? _activeRequestId;
  String? _boundSignature;
  bool _cityReveal = false;
  String _cityMessageKey = 'group_create_place_required';
  XFile? _coverFile;
  final _cityFocus = FocusNode();
  final _cityAnchor = GlobalKey();

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
  void initState() {
    super.initState();
    _loadProfileCity();
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

  @override
  void dispose() {
    _nameC.dispose();
    _cityC.dispose();
    _bioC.dispose();
    _cityFocus.dispose();
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

  String? _countryCodeForIso(String iso) {
    final wanted = iso.trim().toUpperCase();
    if (wanted.isEmpty) return null;
    for (final country in _countries) {
      if ((country['iso2'] ?? '').toUpperCase() == wanted) {
        return country['code'];
      }
    }
    return null;
  }

  Future<void> _loadProfileCity() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!mounted) return;
      final data = snap.data();
      if (data == null) return;
      if (_cityC.text.trim().isNotEmpty || _cityPlaceId.isNotEmpty) return;
      final placeId = (data['placeId'] ?? '').toString().trim();
      final cityName = (data['cityName'] ?? data['city'] ?? '').toString().trim();
      final stateName = (data['stateName'] ?? '').toString().trim();
      final display = (data['displayLocation'] ?? cityName).toString().trim();
      final iso = (data['homeCountryCode'] ?? data['countryCode'] ?? '')
          .toString()
          .trim();
      if (cityName.isEmpty && placeId.isEmpty) return;
      final countryCode = _countryCodeForIso(iso);
      final lat = data['cityLat'] ?? data['lat'];
      final lng = data['cityLng'] ?? data['lng'];
      setState(() {
        if (countryCode != null) _selectedCountry = countryCode;
        _cityName = cityName;
        _stateName = stateName;
        _displayLocation = display.isNotEmpty ? display : cityName;
        _cityC.text = _displayLocation;
        _cityPlaceId = placeId;
        if (lat is num) _cityLatitude = lat.toDouble();
        if (lng is num) _cityLongitude = lng.toDouble();
      });
    } catch (_) {}
  }

  void _applyCity({
    required String placeId,
    required String cityName,
    required String stateName,
    required String display,
    double? latitude,
    double? longitude,
  }) {
    _cityPlaceId = placeId;
    _cityName = cityName;
    _stateName = stateName;
    _displayLocation = display;
    _cityC.text = display.isNotEmpty ? display : cityName;
    _cityLatitude = latitude;
    _cityLongitude = longitude;
    _cityReveal = false;
  }

  bool get _cityLooksInvalid {
    if (_groupScope == 'country') return false;
    return !GroupCreateFlow.resolveCity(
      required: true,
      typed: _cityC.text,
      selectedPlaceId: _cityPlaceId,
      selectedCityName: _cityName,
      selectedStateName: _stateName,
      selectedDisplay: _displayLocation,
      suggestions: const [],
      searched: false,
    ).accepted;
  }

  Future<bool> _uploadCover(String groupId) async {
    final file = _coverFile;
    if (file == null) return true;
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'owner';
      final ext = file.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final ref = FirebaseStorage.instance
          .ref()
          .child('groups')
          .child(groupId)
          .child('avatar')
          .child('group_avatar_$uid.$ext');
      await ref.putFile(
        File(file.path),
        SettableMetadata(
          contentType: ext == 'png' ? 'image/png' : 'image/jpeg',
        ),
      );
      final url = await ref.getDownloadURL();
      await GroupSettingsService.updateSettings(
        groupId: groupId,
        changes: {
          'avatarUrl': url,
          'avatarPath': ref.fullPath,
        },
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  String _pretty(String s) {
    final t = s.trim();
    if (t.isEmpty) return t;
    return t[0].toUpperCase() + t.substring(1);
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

    final found = await GroupPlacesClient.search(
      apiKey: _googlePlacesApiKey,
      countryIso2: countryIso2,
      input: q,
    );
    return [
      for (final item in found)
        _CitySuggestion(
          cityName: item.cityName,
          stateName: item.stateName,
          countryName: item.countryName,
          display: item.display,
          placeId: item.placeId,
        ),
    ];
  }

  Future<Map<String, double>?> _getCityCoordinates(String placeId) {
    return GroupPlacesClient.coordinates(
      apiKey: _googlePlacesApiKey,
      placeId: placeId,
    );
  }

  Future<_CitySuggestion?> _openCitySearch() async {
    final searchC = TextEditingController(text: _cityC.text.trim());
    List<_CitySuggestion> results = [];
    bool loading = false;

    final picked = await showModalBottomSheet<_CitySuggestion>(
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
                      color: Colors.black.withValues(alpha: 0.18),
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
                      textCapitalization: RemdyKeyboardCaps.none,
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
    final typed = searchC.text.trim();
    searchC.dispose();
    if (picked == null && typed.isNotEmpty && typed != _displayLocation.trim()) {
      setState(() {
        _cityC.text = typed;
        _cityPlaceId = '';
        _cityName = '';
        _stateName = '';
        _displayLocation = '';
        _cityLatitude = null;
        _cityLongitude = null;
        _cityReveal = true;
        _cityMessageKey = 'group_create_place_required';
      });
    }
    return picked;
  }

  Future<void> _rejectCity(String messageKey) async {
    setState(() {
      _cityReveal = true;
      _cityMessageKey = messageKey;
    });
    final anchor = _cityAnchor.currentContext;
    if (anchor != null) {
      await Scrollable.ensureVisible(
        anchor,
        alignment: 0.2,
        duration: const Duration(milliseconds: 280),
      );
    }
    _cityFocus.requestFocus();
  }

  Future<GroupCityDecision> _resolveCityForSubmit() async {
    final preset = GroupCreateFlow.resolveCity(
      required: _groupScope != 'country',
      typed: _cityC.text,
      selectedPlaceId: _cityPlaceId,
      selectedCityName: _cityName,
      selectedStateName: _stateName,
      selectedDisplay: _displayLocation,
      suggestions: const [],
      searched: false,
    );
    if (preset.accepted || _groupScope == 'country') return preset;
    if (_cityC.text.trim().isEmpty) return preset;
    final found = await _searchCities(_cityC.text);
    return GroupCreateFlow.resolveCity(
      required: true,
      typed: _cityC.text,
      selectedPlaceId: '',
      selectedCityName: '',
      selectedStateName: '',
      selectedDisplay: '',
      suggestions: [
        for (final item in found)
          GroupCityCandidate(
            cityName: item.cityName,
            stateName: item.stateName,
            countryName: item.countryName,
            display: item.display,
            placeId: item.placeId,
          ),
      ],
      searched: true,
    );
  }

  Future<void> _create() async {
    if (!GroupCreateFlow.shouldStartSubmit(inFlight: _inFlight)) return;
    _inFlight = true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _inFlight = false;
      _toast(AppTexts.t('create_group_need_login'));
      return;
    }

    final name = _nameC.text.trim();
    final bio = _bioC.text.trim();
    final country = _selectedCountry.trim().toLowerCase();

    if (name.isEmpty) {
      _inFlight = false;
      return _toast(AppTexts.t('create_group_enter_name'));
    }
    if (name.length < 3) {
      _inFlight = false;
      return _toast(AppTexts.t('create_group_name_too_short'));
    }
    if (name.length > 80) {
      _inFlight = false;
      return _toast(AppTexts.t('group_edit_name_required'));
    }
    if (bio.length > 1000) {
      _inFlight = false;
      return _toast(AppTexts.t('group_create_bio_too_long'));
    }
    if (country.isEmpty) {
      _inFlight = false;
      return _toast(AppTexts.t('create_group_select_country'));
    }

    setState(() => _loading = true);
    String? createdGroupId;
    try {
      final cityDecision = await _resolveCityForSubmit();
      if (!cityDecision.accepted) {
        await _rejectCity(
          cityDecision.messageKey ?? 'group_create_place_required',
        );
        return;
      }
      if (_groupScope != 'country') {
        var latitude = _cityLatitude;
        var longitude = _cityLongitude;
        final samePlace = cityDecision.placeId == _cityPlaceId;
        if (!samePlace ||
            !GroupGeo.validCoordinates(latitude, longitude)) {
          final coords = await _getCityCoordinates(cityDecision.placeId);
          latitude = coords?['latitude'];
          longitude = coords?['longitude'];
        }
        if (_groupScope == 'region' &&
            !GroupGeo.validCoordinates(latitude, longitude)) {
          _toast(AppTexts.t('create_group_region_coordinates_required'));
          return;
        }
        setState(() {
          _applyCity(
            placeId: cityDecision.placeId,
            cityName: cityDecision.cityName,
            stateName: cityDecision.stateName,
            display: cityDecision.display,
            latitude: latitude,
            longitude: longitude,
          );
        });
      }

      final signature = GroupCreateFlow.signature(
        name: name,
        scope: _groupScope,
        placeId: _cityPlaceId,
        country: country,
        joinPolicy: _joinPolicy,
      );
      final requestId = GroupCreateFlow.requestIdFor(
        currentId: _activeRequestId,
        boundSignature: _boundSignature,
        signature: signature,
        mint: GroupCreationService.newRequestId,
      );
      _activeRequestId = requestId;
      _boundSignature = signature;

      final groupCountryCode = _selectedCountryCode2();
      final cityName = _cityName.isNotEmpty ? _cityName : _cityC.text.trim();
      final isCountry = _groupScope == 'country';
      final isRegion = _groupScope == 'region';
      final regionGeohash =
          isRegion ? GroupGeo.geohash(_cityLatitude, _cityLongitude) : '';

      final fields = <String, dynamic>{
        'name': name,
        'bio': bio,
        'country': country,
        'countryCode': groupCountryCode,
        'scope': _groupScope,
        'joinPolicy': _joinPolicy,
      };
      if (!isCountry) {
        fields['city'] = cityName;
        fields['cityName'] = cityName;
        fields['stateName'] = _stateName;
        fields['displayLocation'] =
            _displayLocation.isNotEmpty ? _displayLocation : cityName;
        fields['placeId'] = _cityPlaceId;
        if (_cityLatitude != null) fields['latitude'] = _cityLatitude;
        if (_cityLongitude != null) fields['longitude'] = _cityLongitude;
      }
      if (isRegion) {
        fields['regionCenterCity'] = cityName;
        fields['regionCenterCountryCode'] = groupCountryCode;
        fields['regionCenterLat'] = _cityLatitude;
        fields['regionCenterLng'] = _cityLongitude;
        fields['regionRadiusKm'] = GroupGeo.regionRadiusKm;
        fields['regionCenterGeohash'] = regionGeohash;
      }

      final result = await GroupCreationService.createGroup(
        requestId: requestId,
        fields: fields,
      );

      createdGroupId = (result['groupId'] ?? '').toString().trim();
      if (createdGroupId.isEmpty) {
        throw Exception('missing groupId');
      }

      final avatarOk = await _uploadCover(createdGroupId);
      final finish = GroupCreateFlow.finish(
        groupId: createdGroupId,
        avatarFailed: !avatarOk,
      );
      _activeRequestId = null;
      _boundSignature = null;
      if (!mounted) return;
      _toast(AppTexts.t(finish.toastKey));
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GroupInfoPage(groupId: finish.groupId),
        ),
      );
    } on FirebaseFunctionsException catch (e) {
      if (createdGroupId == null) {
        _toast(AppTexts.t(GroupCreationService.errorKey(e)));
      }
    } catch (_) {
      if (createdGroupId != null) {
        final finish = GroupCreateFlow.finish(
          groupId: createdGroupId,
          avatarFailed: _coverFile != null,
        );
        _toast(AppTexts.t(finish.toastKey));
      } else {
        _toast(AppTexts.t('group_create_error'));
      }
    } finally {
      _inFlight = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedCountryName = _countries.firstWhere(
      (e) => e['code'] == _selectedCountry,
      orElse: () => const {"code": "canada", "name": "Canadá", "iso2": "CA"},
    )['name']!;
    final entryLabel = _joinPolicy == 'open'
        ? AppTexts.t('create_group_open')
        : _joinPolicy == 'approval'
            ? AppTexts.t('admin_approval')
            : AppTexts.t('invite_only');
    final scopeLocationSummary = _groupScope == 'country'
        ? '${AppTexts.t('country')}: ${_pretty(selectedCountryName)}'
        : _groupScope == 'region'
            ? '${AppTexts.t('create_group_region_center')}: '
                '${_cityName.isEmpty ? "--" : _cityName}\n'
                '${AppTexts.t('country')}: ${_pretty(selectedCountryName)}\n'
                '${AppTexts.t('create_group_region_radius_short')}'
            : '${AppTexts.t('city')}: '
                '${_cityName.isEmpty ? "--" : _cityName}\n'
                '${AppTexts.t('country')}: ${_pretty(selectedCountryName)}';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
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
      body: SafeArea(
        top: false,
        bottom: false,
        child: KeyboardDismissOnTap(
          child: AbsorbPointer(
            absorbing: _loading,
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                  textCapitalization: RemdyKeyboardCaps.words,
                  textInputAction: TextInputAction.next,
                  decoration: _dec(
                    AppTexts.t('create_group_name'),
                    hint: AppTexts.t('create_group_name_hint'),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedCountry,
                  decoration: _dec(
                    AppTexts.t('country'),
                    helper: AppTexts.t('create_group_country_helper'),
                  ),
                  dropdownColor: Colors.white,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: _muted),
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
                      _cityLatitude = null;
                      _cityLongitude = null;
                      _cityPlaceId = '';
                      _cityC.clear();
                      _cityReveal = false;
                    });
                  },
                ),
                const SizedBox(height: 12),
                if (_groupScope != 'country')
                  KeyedSubtree(
                    key: _cityAnchor,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _cityC,
                          focusNode: _cityFocus,
                          readOnly: true,
                          textCapitalization: RemdyKeyboardCaps.none,
                          textInputAction: TextInputAction.next,
                          decoration: RequiredFieldChrome.apply(
                            base: _dec(
                              AppTexts.t('city'),
                              hint: AppTexts.t('city_example'),
                            ),
                            pending: RequiredFieldChrome.reveal(
                              invalid: _cityLooksInvalid,
                              blurred: _cityReveal,
                              submitAttempted: _cityReveal,
                            ),
                          ),
                          onTap: () async {
                            final result = await _openCitySearch();
                            if (result == null) return;
                            final coords =
                                await _getCityCoordinates(result.placeId);
                            if (!mounted) return;
                            setState(() {
                              _applyCity(
                                placeId: result.placeId,
                                cityName: result.cityName,
                                stateName: result.stateName,
                                display: result.display,
                                latitude: coords?['latitude'],
                                longitude: coords?['longitude'],
                              );
                            });
                          },
                        ),
                        if (RequiredFieldChrome.reveal(
                          invalid: _cityLooksInvalid,
                          blurred: _cityReveal,
                          submitAttempted: _cityReveal,
                        ))
                          RequiredPendingNotice(
                            pendingLabel: AppTexts.t('field_pending'),
                            message: AppTexts.t(_cityMessageKey),
                          ),
                      ],
                    ),
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
                            onSelected: (_) =>
                                setState(() => _groupScope = 'city'),
                          ),
                          ChoiceChip(
                            label:
                                Text(AppTexts.t('create_group_scope_region')),
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
                            onSelected: (_) =>
                                setState(() => _groupScope = 'region'),
                          ),
                          ChoiceChip(
                            label:
                                Text(AppTexts.t('create_group_scope_country')),
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
                            onSelected: (_) =>
                                setState(() => _groupScope = 'country'),
                          ),
                        ],
                      ),
                      if (_groupScope == 'region') ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color:
                                  Theme.of(context).colorScheme.outlineVariant,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppTexts.t('create_group_region_radius_title'),
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                AppTexts.t(
                                    'create_group_region_radius_description'),
                                style: TextStyle(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
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
                              color: _joinPolicy == 'open'
                                  ? Colors.white
                                  : _remdyBlue,
                              fontWeight: FontWeight.w700,
                            ),
                            onSelected: (_) =>
                                setState(() => _joinPolicy = 'open'),
                          ),
                          ChoiceChip(
                            label: Text(AppTexts.t('admin_approval')),
                            selected: _joinPolicy == 'approval',
                            selectedColor: _logoBlue,
                            backgroundColor: Colors.white,
                            checkmarkColor: Colors.white,
                            side: const BorderSide(color: _border),
                            labelStyle: TextStyle(
                              color: _joinPolicy == 'approval'
                                  ? Colors.white
                                  : _remdyBlue,
                              fontWeight: FontWeight.w700,
                            ),
                            onSelected: (_) =>
                                setState(() => _joinPolicy = 'approval'),
                          ),
                          ChoiceChip(
                            label: Text(AppTexts.t('invite_only')),
                            selected: _joinPolicy == 'inviteOnly',
                            selectedColor: _logoBlue,
                            backgroundColor: Colors.white,
                            checkmarkColor: Colors.white,
                            side: const BorderSide(color: _border),
                            labelStyle: TextStyle(
                              color: _joinPolicy == 'inviteOnly'
                                  ? Colors.white
                                  : _remdyBlue,
                              fontWeight: FontWeight.w700,
                            ),
                            onSelected: (_) =>
                                setState(() => _joinPolicy = 'inviteOnly'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _loading
                      ? null
                      : () async {
                          final file = await ImagePicker().pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 80,
                          );
                          if (file == null || !mounted) return;
                          setState(() => _coverFile = file);
                        },
                  icon: const Icon(Icons.image_outlined),
                  label: Text(
                    _coverFile == null
                        ? AppTexts.t('create_group_cover_optional')
                        : AppTexts.t('create_group_cover_selected'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bioC,
                  textCapitalization: RemdyKeyboardCaps.sentences,
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
                    '$scopeLocationSummary\n'
                    '${AppTexts.t('create_group_entry')}: $entryLabel',
                    style: const TextStyle(
                      color: _muted,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ),
                // Espaço para não ficar atrás do botão fixo.
                const SizedBox(height: 88),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: Builder(
        builder: (context) {
          final mq = MediaQuery.of(context);
          final keyboard = mq.viewInsets.bottom;
          // Preferir viewPadding (gestos/3 botões). Se o SO reportar 0
          // (edge-to-edge sem insets), usar mínimo seguro para não colar na barra.
          // Neste aparelho (edge-to-edge) o SO pode reportar padding 0;
          // 64dp cobre a barra de gestos / 3 botões (~61px até y=2669).
          final reported = mq.viewPadding.bottom > 0
              ? mq.viewPadding.bottom
              : mq.padding.bottom;
          final systemBottom = reported > 0 ? reported : 64.0;
          // Spacer separado do botão (evita Semantics expandir até a borda
          // física e o botão ficar visualmente sob a barra inferior).
          final gap = keyboard > 0 ? keyboard : systemBottom;
          return Material(
            color: _bg,
            elevation: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: SizedBox(
                    height: 48,
                    width: double.infinity,
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
                            : const Icon(Icons.group_add_rounded,
                                color: Colors.white),
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
                ),
                ExcludeSemantics(child: SizedBox(height: gap)),
              ],
            ),
          );
        },
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
