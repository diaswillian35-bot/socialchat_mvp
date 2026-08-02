import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_texts.dart';
import '../../models/event_editorial_draft.dart';
import '../../utils/event_timezone.dart';
import '../keyboard_dismiss.dart';

/// Wizard canônico de 7 passos para criar/editar evento.
class EventEditorialWizard extends StatefulWidget {
  const EventEditorialWizard({
    super.key,
    required this.initial,
    required this.isEdit,
    required this.onSubmit,
    this.onCancel,
    this.onDraftChanged,
    this.title,
  });

  final EventEditorialDraft initial;
  final bool isEdit;
  final Future<void> Function(EventEditorialDraft draft) onSubmit;
  final VoidCallback? onCancel;
  final ValueChanged<EventEditorialDraft>? onDraftChanged;
  final String? title;

  @override
  State<EventEditorialWizard> createState() => _EventEditorialWizardState();
}

class _EventEditorialWizardState extends State<EventEditorialWizard> {
  static const Color _bg = Color(0xFFF6F7FB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyNavy = Color(0xFF313A5F);

  static const String _googlePlacesApiKey =
      'AIzaSyCCu5KXXT2tSqL4kqwjDX6ySv49lqyCLs0';

  late final PageController _pageController;
  late EventEditorialDraft _draft;
  final _picker = ImagePicker();
  int _step = 0;
  bool _submitting = false;
  bool _dirty = false;

  final _titleC = TextEditingController();
  final _shortDescC = TextEditingController();
  final _descC = TextEditingController();
  final _langC = TextEditingController();
  final _priceC = TextEditingController();
  final _currencyC = TextEditingController();
  final _ticketUrlC = TextEditingController();
  final _ticketInfoC = TextEditingController();
  final _audienceC = TextEditingController();
  final _accessC = TextEditingController();
  final _parkingC = TextEditingController();
  final _foodC = TextEditingController();
  final _ageC = TextEditingController();
  final _entryC = TextEditingController();
  final _contactC = TextEditingController();
  final _websiteC = TextEditingController();
  final _notesC = TextEditingController();

  static const _stepKeys = [
    'event_wizard_step_info',
    'event_wizard_step_datetime',
    'event_wizard_step_tickets',
    'event_wizard_step_media',
    'event_wizard_step_program',
    'event_wizard_step_extra',
    'event_wizard_step_review',
  ];

  @override
  void initState() {
    super.initState();
    _draft = widget.initial;
    _pageController = PageController();
    _syncControllersFromDraft();
  }

  void _syncControllersFromDraft() {
    _titleC.text = _draft.title;
    _shortDescC.text = _draft.shortDescription;
    _descC.text = _draft.description;
    _langC.text = _draft.primaryLanguage;
    _priceC.text = _draft.price;
    _currencyC.text = _draft.priceCurrency;
    _ticketUrlC.text = _draft.ticketUrl;
    _ticketInfoC.text = _draft.ticketInfo;
    _audienceC.text =
        _draft.expectedAudience == null ? '' : '${_draft.expectedAudience}';
    _accessC.text = _draft.accessibility;
    _parkingC.text = _draft.parking;
    _foodC.text = _draft.foodInfo;
    _ageC.text = _draft.ageRating;
    _entryC.text = _draft.entryPolicy;
    _contactC.text = _draft.publicContact;
    _websiteC.text = _draft.websiteUrl;
    _notesC.text = _draft.publicNotes;
  }

  @override
  void dispose() {
    _pageController.dispose();
    _titleC.dispose();
    _shortDescC.dispose();
    _descC.dispose();
    _langC.dispose();
    _priceC.dispose();
    _currencyC.dispose();
    _ticketUrlC.dispose();
    _ticketInfoC.dispose();
    _audienceC.dispose();
    _accessC.dispose();
    _parkingC.dispose();
    _foodC.dispose();
    _ageC.dispose();
    _entryC.dispose();
    _contactC.dispose();
    _websiteC.dispose();
    _notesC.dispose();
    super.dispose();
  }

  void _setDraft(EventEditorialDraft next) {
    setState(() {
      _draft = next;
      _dirty = true;
    });
    widget.onDraftChanged?.call(next);
  }

  void _pullTextFieldsIntoDraft() {
    final audienceRaw = _audienceC.text.trim();
    final audience = audienceRaw.isEmpty ? null : int.tryParse(audienceRaw);
    _draft = _draft.copyWith(
      title: _titleC.text,
      shortDescription: _shortDescC.text,
      description: _descC.text,
      primaryLanguage: _langC.text,
      price: _priceC.text,
      priceCurrency: _currencyC.text,
      ticketUrl: _ticketUrlC.text,
      ticketInfo: _ticketInfoC.text,
      expectedAudience: audience,
      clearExpectedAudience: audience == null,
      accessibility: _accessC.text,
      parking: _parkingC.text,
      foodInfo: _foodC.text,
      ageRating: _ageC.text,
      entryPolicy: _entryC.text,
      publicContact: _contactC.text,
      websiteUrl: _websiteC.text,
      publicNotes: _notesC.text,
    );
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppTexts.t('event_wizard_discard_title')),
        content: Text(AppTexts.t('event_wizard_discard_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppTexts.t('event_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppTexts.t('event_wizard_discard_confirm')),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _onPopInvoked(bool didPop) async {
    if (didPop) return;
    final ok = await _confirmDiscard();
    if (ok && mounted) {
      if (widget.onCancel != null) {
        widget.onCancel!();
      } else {
        Navigator.of(context).maybePop();
      }
    }
  }

  String? _validateCurrent() {
    _pullTextFieldsIntoDraft();
    return _draft.validateStep(_step);
  }

  Future<void> _goNext() async {
    dismissAppKeyboard();
    final err = _validateCurrent();
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.t(err))),
      );
      return;
    }
    if (_step >= EventEditorialDraft.stepCount - 1) {
      await _submit();
      return;
    }
    setState(() => _step += 1);
    await _pageController.animateToPage(
      _step,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _goBack() async {
    dismissAppKeyboard();
    _pullTextFieldsIntoDraft();
    if (_step <= 0) {
      final ok = await _confirmDiscard();
      if (ok && mounted) {
        if (widget.onCancel != null) {
          widget.onCancel!();
        } else {
          Navigator.of(context).maybePop();
        }
      }
      return;
    }
    setState(() => _step -= 1);
    await _pageController.animateToPage(
      _step,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    _pullTextFieldsIntoDraft();
    final err = _draft.validateStep(6);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.t(err))),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.onSubmit(_draft);
      _dirty = false;
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  InputDecoration _dec(String label, {String? hint}) {
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
        borderSide: const BorderSide(color: _remdyNavy),
      ),
    );
  }

  String _fmtDate(DateTime? d) {
    if (d == null) return AppTexts.t('create_event_pick_date');
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  String _fmtTime(String t) {
    if (t.trim().isEmpty) return AppTexts.t('create_event_pick_time');
    return t;
  }

  Future<void> _pickDate({required bool isEnd}) async {
    final now = DateTime.now();
    final initial = isEnd
        ? (_draft.endDate ?? _draft.startDate ?? now.add(const Duration(days: 1)))
        : (_draft.startDate ?? now.add(const Duration(days: 1)));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: isEnd ? (_draft.startDate ?? now) : now,
      lastDate: now.add(const Duration(days: 730)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: _remdyNavy),
          ),
          child: child!,
        );
      },
    );
    if (date == null) return;
    if (isEnd) {
      _setDraft(_draft.copyWith(endDate: DateTime(date.year, date.month, date.day)));
    } else {
      var next = _draft.copyWith(
        startDate: DateTime(date.year, date.month, date.day),
      );
      if (next.endDate == null) {
        next = next.copyWith(endDate: next.startDate);
      }
      _setDraft(next);
      _maybeSuggestEnd();
    }
  }

  Future<void> _pickTime({required bool isEnd}) async {
    final parsed = EventEditorialDraft.parseHm(
      isEnd ? _draft.endTime : _draft.startTime,
    );
    final initial = parsed == null
        ? TimeOfDay(hour: isEnd ? 21 : 19, minute: 0)
        : TimeOfDay(hour: parsed[0], minute: parsed[1]);
    final time = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: _remdyNavy),
          ),
          child: child!,
        );
      },
    );
    if (time == null) return;
    String two(int n) => n.toString().padLeft(2, '0');
    final hm = '${two(time.hour)}:${two(time.minute)}';
    if (isEnd) {
      _setDraft(_draft.copyWith(endTime: hm));
    } else {
      _setDraft(_draft.copyWith(startTime: hm));
      _maybeSuggestEnd();
    }
  }

  void _maybeSuggestEnd() {
    if (_draft.startDate == null || _draft.startTime.isEmpty) return;
    if (_draft.endTime.isNotEmpty && _draft.endDate != null) return;
    final hm = EventEditorialDraft.parseHm(_draft.startTime);
    if (hm == null) return;
    final endMinute = hm[0] * 60 + hm[1] + 120;
    final endHour = (endMinute ~/ 60) % 24;
    final endMin = endMinute % 60;
    final dayAdd = endMinute ~/ (24 * 60);
    final base = _draft.startDate!;
    final endDate = DateTime(base.year, base.month, base.day)
        .add(Duration(days: dayAdd));
    String two(int n) => n.toString().padLeft(2, '0');
    _setDraft(_draft.copyWith(
      endDate: endDate,
      endTime: '${two(endHour)}:${two(endMin)}',
    ));
  }

  String _countryCodeFromName(String countryName) {
    final v = countryName.trim().toLowerCase();
    if (v.contains('brazil') || v.contains('brasil')) return 'br';
    if (v.contains('canada') || v.contains('canadá')) return 'ca';
    if (v.contains('portugal')) return 'pt';
    if (v.contains('france') || v.contains('frança')) return 'fr';
    if (v.contains('spain') || v.contains('espanha')) return 'es';
    if (v.contains('united states') || v.contains('estados unidos')) {
      return 'us';
    }
    if (v.contains('italy') || v.contains('itália')) return 'it';
    return 'br';
  }

  Future<List<_CitySuggestion>> _searchCities(String input) async {
    final q = input.trim();
    if (q.length < 2) return [];

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
      if (res.statusCode != 200) return [];
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final predictions = (data['predictions'] as List<dynamic>?) ?? [];
      return predictions.map((p) {
        final description = (p['description'] ?? '').toString();
        final parts = description.split(',').map((e) => e.trim()).toList();
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
      }).where((e) => e.cityName.isNotEmpty).toList();
    }

    final localResults = await search(countryCode: userCountryCode);
    if (localResults.isNotEmpty) return localResults;
    return search();
  }

  Future<List<_PlaceSuggestion>> _searchPlaces(String input) async {
    final q = input.trim();
    if (q.length < 2) return [];
    final cityContext = _draft.placeDisplay.isNotEmpty
        ? _draft.placeDisplay
        : (_draft.city.isNotEmpty
            ? '${_draft.city}, ${_draft.stateName}'
            : _draft.city);
    final query = cityContext.isNotEmpty ? '$q $cityContext' : q;
    final placeCountryCode = (_draft.countryCode.isNotEmpty
            ? _draft.countryCode
            : _countryCodeFromName(_draft.countryName))
        .toUpperCase();
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
          (p['structured_formatting']?['main_text'] ?? description)
              .toString();
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
    _setDraft(_draft.copyWith(
      lat: (location['lat'] as num?)?.toDouble(),
      lng: (location['lng'] as num?)?.toDouble(),
    ));
  }

  Future<_CitySuggestion?> _openCitySearch() async {
    final searchC = TextEditingController();
    List<_CitySuggestion> results = [];
    var loading = false;
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
                      decoration: InputDecoration(
                        labelText: AppTexts.t('create_event_city'),
                        hintText:
                            AppTexts.t('create_event_city_search_hint'),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: runSearch,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : results.isEmpty
                              ? Center(
                                  child: Text(
                                    AppTexts.t('create_event_type_2_letters'),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: results.length,
                                  itemBuilder: (context, i) {
                                    final item = results[i];
                                    return ListTile(
                                      title: Text(item.display),
                                      onTap: () => Navigator.pop(
                                        sheetContext,
                                        item,
                                      ),
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

  Future<_PlaceSuggestion?> _openPlaceSearch() async {
    final searchC = TextEditingController();
    List<_PlaceSuggestion> results = [];
    var loading = false;
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
                      decoration: InputDecoration(
                        labelText: AppTexts.t('create_event_place'),
                        hintText:
                            AppTexts.t('create_event_place_search_hint'),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.place),
                      ),
                      onChanged: runSearch,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: loading
                          ? const Center(child: CircularProgressIndicator())
                          : results.isEmpty
                              ? Center(
                                  child: Text(
                                    AppTexts.t('create_event_type_2_letters'),
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: results.length,
                                  itemBuilder: (context, i) {
                                    final item = results[i];
                                    return ListTile(
                                      title: Text(item.placeName),
                                      subtitle: Text(item.address),
                                      onTap: () => Navigator.pop(
                                        sheetContext,
                                        item,
                                      ),
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

  Future<void> _pickPhotos() async {
    final remaining =
        5 - (_draft.photoUrls.length + _draft.pendingPhotoPaths.length);
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.t('max_5_photos'))),
      );
      return;
    }
    final picked = await _picker.pickMultiImage(imageQuality: 80);
    if (picked.isEmpty) return;
    final paths = picked.take(remaining).map((e) => e.path).toList();
    final nextPending = [..._draft.pendingPhotoPaths, ...paths];
    var coverPath = _draft.pendingCoverPath;
    if (coverPath.isEmpty &&
        _draft.coverUrl.isEmpty &&
        nextPending.isNotEmpty) {
      coverPath = nextPending.first;
    }
    _setDraft(_draft.copyWith(
      pendingPhotoPaths: nextPending,
      pendingCoverPath: coverPath,
    ));
  }

  Future<void> _pickLogo() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    _setDraft(_draft.copyWith(pendingLogoPath: picked.path));
  }

  Future<void> _editScheduleItem({EventScheduleItem? existing, int? index}) async {
    final dayC = TextEditingController(text: existing?.day ?? '');
    final startC = TextEditingController(text: existing?.startTime ?? '');
    final endC = TextEditingController(text: existing?.endTime ?? '');
    final titleC = TextEditingController(text: existing?.title ?? '');
    final descC = TextEditingController(text: existing?.description ?? '');
    final tagC = TextEditingController(text: existing?.tag ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppTexts.t(
          existing == null
              ? 'event_wizard_add_schedule'
              : 'event_wizard_edit_schedule',
        )),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleC,
                decoration: _dec(AppTexts.t('event_wizard_schedule_title')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: dayC,
                decoration: _dec(AppTexts.t('event_wizard_schedule_day')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: startC,
                decoration: _dec(AppTexts.t('event_wizard_schedule_start')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: endC,
                decoration: _dec(AppTexts.t('event_wizard_schedule_end')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descC,
                maxLines: 2,
                decoration: _dec(AppTexts.t('event_wizard_schedule_desc')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: tagC,
                decoration: _dec(AppTexts.t('event_wizard_schedule_tag')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppTexts.t('event_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppTexts.t('event_wizard_save_item')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final item = EventScheduleItem(
      id: existing?.id ??
          's_${DateTime.now().microsecondsSinceEpoch}',
      day: dayC.text.trim(),
      startTime: startC.text.trim(),
      endTime: endC.text.trim(),
      title: titleC.text.trim(),
      description: descC.text.trim(),
      tag: tagC.text.trim(),
      order: existing?.order ?? _draft.schedule.length,
    );
    final list = [..._draft.schedule];
    if (index != null) {
      list[index] = item;
    } else {
      list.add(item);
    }
    _setDraft(_draft.copyWith(schedule: list));
  }

  Future<void> _editAttractionItem({
    EventAttractionItem? existing,
    int? index,
  }) async {
    final nameC = TextEditingController(text: existing?.name ?? '');
    final descC = TextEditingController(text: existing?.description ?? '');
    final typeC = TextEditingController(text: existing?.type ?? '');
    final photoC = TextEditingController(text: existing?.photoUrl ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppTexts.t(
          existing == null
              ? 'event_wizard_add_attraction'
              : 'event_wizard_edit_attraction',
        )),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                decoration:
                    _dec(AppTexts.t('event_wizard_attraction_name')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: descC,
                maxLines: 2,
                decoration:
                    _dec(AppTexts.t('event_wizard_attraction_desc')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: typeC,
                decoration:
                    _dec(AppTexts.t('event_wizard_attraction_type')),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: photoC,
                decoration:
                    _dec(AppTexts.t('event_wizard_attraction_photo')),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppTexts.t('event_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppTexts.t('event_wizard_save_item')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final item = EventAttractionItem(
      id: existing?.id ??
          'a_${DateTime.now().microsecondsSinceEpoch}',
      name: nameC.text.trim(),
      description: descC.text.trim(),
      type: typeC.text.trim(),
      photoUrl: photoC.text.trim(),
      order: existing?.order ?? _draft.attractions.length,
    );
    final list = [..._draft.attractions];
    if (index != null) {
      list[index] = item;
    } else {
      list.add(item);
    }
    _setDraft(_draft.copyWith(attractions: list));
  }

  Widget _chipButton({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: _muted),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepInfo() {
    final t = AppTexts.t;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        TextField(
          controller: _titleC,
          decoration: _dec(t('create_event_name'), hint: t('create_event_name_hint')),
          onChanged: (_) => _dirty = true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _shortDescC,
          maxLength: 280,
          decoration: _dec(t('event_wizard_short_description')),
          onChanged: (_) => _dirty = true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descC,
          maxLines: 5,
          decoration: _dec(
            t('create_event_description'),
            hint: t('create_event_description_hint'),
          ),
          onChanged: (_) => _dirty = true,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: kEventEditorialCategories.contains(_draft.category)
              ? _draft.category
              : 'Geral',
          decoration: _dec(t('create_event_category')),
          items: kEventEditorialCategories
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            _setDraft(_draft.copyWith(category: v));
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _langC,
          decoration: _dec(t('event_wizard_primary_language')),
          onChanged: (_) => _dirty = true,
        ),
      ],
    );
  }

  Widget _stepDatePlace() {
    final t = AppTexts.t;
    final cityLabel = _draft.city.isEmpty
        ? t('create_event_city_hint')
        : [
            _draft.city,
            if (_draft.stateName.isNotEmpty) _draft.stateName,
            if (_draft.countryName.isNotEmpty) _draft.countryName,
          ].join(', ');
    final placeLabel = _draft.placeName.isEmpty
        ? t('create_event_place_hint')
        : _draft.placeName;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: _chipButton(
                icon: Icons.calendar_month_outlined,
                text: _fmtDate(_draft.startDate),
                onTap: () => _pickDate(isEnd: false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _chipButton(
                icon: Icons.access_time,
                text: _fmtTime(_draft.startTime),
                onTap: () => _pickTime(isEnd: false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          t('events_end_section'),
          style: const TextStyle(fontWeight: FontWeight.w800, color: _text),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _chipButton(
                icon: Icons.calendar_month_outlined,
                text: _fmtDate(_draft.endDate),
                onTap: () => _pickDate(isEnd: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _chipButton(
                icon: Icons.access_time,
                text: _fmtTime(_draft.endTime),
                onTap: () => _pickTime(isEnd: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: EventTimezone.suggestedZones.contains(_draft.eventTimeZone)
              ? _draft.eventTimeZone
              : EventTimezone.suggestedZones.first,
          decoration: _dec(t('events_timezone_label')),
          items: EventTimezone.suggestedZones
              .map((z) => DropdownMenuItem(value: z, child: Text(z)))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            _setDraft(_draft.copyWith(eventTimeZone: v));
          },
        ),
        const SizedBox(height: 12),
        _chipButton(
          icon: Icons.search,
          text: cityLabel,
          onTap: () async {
            final city = await _openCitySearch();
            if (city == null) return;
            final cc = _countryCodeFromName(city.countryName);
            _setDraft(_draft.copyWith(
              city: city.cityName,
              cityKey: city.cityName.toLowerCase(),
              stateName: city.stateName,
              countryName: city.countryName,
              countryCode: cc,
            ));
          },
        ),
        const SizedBox(height: 12),
        _chipButton(
          icon: Icons.place_outlined,
          text: placeLabel,
          onTap: () async {
            final place = await _openPlaceSearch();
            if (place == null) return;
            _setDraft(_draft.copyWith(
              placeName: place.placeName,
              address: place.address,
              placeDisplay: place.display,
              placeId: place.placeId,
            ));
            await _loadPlaceLatLng(place.placeId);
          },
        ),
      ],
    );
  }

  Widget _stepTickets() {
    final t = AppTexts.t;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          t('event_wizard_ticket_type'),
          style: const TextStyle(fontWeight: FontWeight.w800, color: _text),
        ),
        const SizedBox(height: 8),
        ...['free', 'paid', 'inquire'].map((type) {
          return RadioListTile<String>(
            value: type,
            groupValue: _draft.ticketType,
            activeColor: _remdyNavy,
            title: Text(t('event_wizard_ticket_$type')),
            onChanged: (v) {
              if (v == null) return;
              _setDraft(_draft.withTicketType(v));
            },
          );
        }),
        if (_draft.ticketType == 'paid') ...[
          TextField(
            controller: _priceC,
            decoration: _dec(t('event_wizard_price')),
            keyboardType: TextInputType.text,
            onChanged: (_) => _dirty = true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _currencyC,
            decoration: _dec(t('event_wizard_currency'), hint: 'BRL'),
            onChanged: (_) => _dirty = true,
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _ticketUrlC,
          decoration: _dec(t('event_wizard_ticket_url')),
          onChanged: (_) => _dirty = true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ticketInfoC,
          decoration: _dec(t('event_wizard_ticket_info')),
          onChanged: (_) => _dirty = true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _audienceC,
          decoration: _dec(t('event_wizard_expected_audience')),
          keyboardType: TextInputType.number,
          onChanged: (_) => _dirty = true,
        ),
      ],
    );
  }

  Widget _stepMedia() {
    final t = AppTexts.t;
    final pending = _draft.pendingPhotoPaths;
    final remote = _draft.photoUrls;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Text(
          t('create_event_add_photos'),
          style: const TextStyle(fontWeight: FontWeight.w700, color: _muted),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < remote.length; i++)
              _photoThumb(
                remote: remote[i],
                isCover: _draft.coverUrl == remote[i] ||
                    (_draft.coverUrl.isEmpty &&
                        _draft.pendingCoverPath.isEmpty &&
                        i == 0),
                onCover: () => _setDraft(_draft.copyWith(coverUrl: remote[i])),
                onRemove: () {
                  final next = [...remote]..removeAt(i);
                  var cover = _draft.coverUrl;
                  if (cover == remote[i]) {
                    cover = next.isNotEmpty ? next.first : '';
                  }
                  _setDraft(_draft.copyWith(photoUrls: next, coverUrl: cover));
                },
              ),
            for (var i = 0; i < pending.length; i++)
              _photoThumb(
                localPath: pending[i],
                isCover: _draft.pendingCoverPath == pending[i] ||
                    (_draft.pendingCoverPath.isEmpty &&
                        _draft.coverUrl.isEmpty &&
                        remote.isEmpty &&
                        i == 0),
                onCover: () =>
                    _setDraft(_draft.copyWith(pendingCoverPath: pending[i])),
                onRemove: () {
                  final next = [...pending]..removeAt(i);
                  var cover = _draft.pendingCoverPath;
                  if (cover == pending[i]) {
                    cover = next.isNotEmpty ? next.first : '';
                  }
                  _setDraft(_draft.copyWith(
                    pendingPhotoPaths: next,
                    pendingCoverPath: cover,
                  ));
                },
              ),
            if (remote.length + pending.length < 5)
              InkWell(
                onTap: _pickPhotos,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                  ),
                  child: const Icon(Icons.add_a_photo_outlined,
                      color: _remdyNavy),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          t('event_wizard_logo'),
          style: const TextStyle(fontWeight: FontWeight.w700, color: _muted),
        ),
        const SizedBox(height: 8),
        if (_draft.pendingLogoPath.isNotEmpty || _draft.logoUrl.isNotEmpty)
          Row(
            children: [
              if (_draft.pendingLogoPath.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_draft.pendingLogoPath),
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                )
              else if (_draft.logoUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    _draft.logoUrl,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                  ),
                ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () => _setDraft(_draft.copyWith(
                  pendingLogoPath: '',
                  logoUrl: '',
                )),
                child: Text(t('event_wizard_remove')),
              ),
            ],
          ),
        TextButton.icon(
          onPressed: _pickLogo,
          icon: const Icon(Icons.image_outlined),
          label: Text(t('event_wizard_pick_logo')),
        ),
      ],
    );
  }

  Widget _photoThumb({
    String? remote,
    String? localPath,
    required bool isCover,
    required VoidCallback onCover,
    required VoidCallback onRemove,
  }) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: localPath != null
              ? Image.file(
                  File(localPath),
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                )
              : Image.network(
                  remote!,
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: InkWell(
            onTap: onRemove,
            child: const CircleAvatar(
              radius: 12,
              backgroundColor: Colors.black54,
              child: Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
        Positioned(
          bottom: 4,
          left: 4,
          child: InkWell(
            onTap: onCover,
            child: Icon(
              isCover ? Icons.star : Icons.star_border,
              color: isCover ? Colors.amber : Colors.white,
              size: 22,
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepProgram() {
    final t = AppTexts.t;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                t('events_tab_schedule'),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _text,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _editScheduleItem(),
              icon: const Icon(Icons.add),
              label: Text(t('event_wizard_add')),
            ),
          ],
        ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _draft.schedule.length,
          onReorder: (oldIndex, newIndex) {
            final list = [..._draft.schedule];
            if (newIndex > oldIndex) newIndex -= 1;
            final item = list.removeAt(oldIndex);
            list.insert(newIndex, item);
            _setDraft(_draft.copyWith(
              schedule: [
                for (var i = 0; i < list.length; i++)
                  list[i].copyWith(order: i),
              ],
            ));
          },
          itemBuilder: (context, i) {
            final s = _draft.schedule[i];
            return ListTile(
              key: ValueKey(s.id),
              title: Text(s.title),
              subtitle: Text(
                [
                  if (s.day.isNotEmpty) s.day,
                  if (s.startTime.isNotEmpty || s.endTime.isNotEmpty)
                    '${s.startTime}${s.endTime.isNotEmpty ? '–${s.endTime}' : ''}',
                ].join(' · '),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () =>
                        _editScheduleItem(existing: s, index: i),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      final list = [..._draft.schedule]..removeAt(i);
                      _setDraft(_draft.copyWith(schedule: list));
                    },
                  ),
                  const Icon(Icons.drag_handle),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                t('events_tab_attractions'),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: _text,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () => _editAttractionItem(),
              icon: const Icon(Icons.add),
              label: Text(t('event_wizard_add')),
            ),
          ],
        ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _draft.attractions.length,
          onReorder: (oldIndex, newIndex) {
            final list = [..._draft.attractions];
            if (newIndex > oldIndex) newIndex -= 1;
            final item = list.removeAt(oldIndex);
            list.insert(newIndex, item);
            _setDraft(_draft.copyWith(
              attractions: [
                for (var i = 0; i < list.length; i++)
                  list[i].copyWith(order: i),
              ],
            ));
          },
          itemBuilder: (context, i) {
            final a = _draft.attractions[i];
            return ListTile(
              key: ValueKey(a.id),
              title: Text(a.name),
              subtitle: a.description.isEmpty ? null : Text(a.description),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () =>
                        _editAttractionItem(existing: a, index: i),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () {
                      final list = [..._draft.attractions]..removeAt(i);
                      _setDraft(_draft.copyWith(attractions: list));
                    },
                  ),
                  const Icon(Icons.drag_handle),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _stepExtra() {
    final t = AppTexts.t;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        TextField(
          controller: _accessC,
          maxLines: 2,
          decoration: _dec(t('event_wizard_accessibility')),
          onChanged: (_) => _dirty = true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _parkingC,
          maxLines: 2,
          decoration: _dec(t('event_wizard_parking')),
          onChanged: (_) => _dirty = true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _foodC,
          maxLines: 2,
          decoration: _dec(t('event_wizard_food')),
          onChanged: (_) => _dirty = true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ageC,
          decoration: _dec(t('event_wizard_age_rating')),
          onChanged: (_) => _dirty = true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _entryC,
          maxLines: 2,
          decoration: _dec(t('event_wizard_entry_policy')),
          onChanged: (_) => _dirty = true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _contactC,
          decoration: _dec(t('event_wizard_public_contact')),
          onChanged: (_) => _dirty = true,
        ),
        CheckboxListTile(
          value: _draft.publicContactConsent,
          activeColor: _remdyNavy,
          title: Text(t('event_wizard_public_contact_consent')),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) =>
              _setDraft(_draft.copyWith(publicContactConsent: v == true)),
        ),
        TextField(
          controller: _websiteC,
          decoration: _dec(t('event_wizard_website')),
          onChanged: (_) => _dirty = true,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notesC,
          maxLines: 3,
          decoration: _dec(t('event_wizard_public_notes')),
          onChanged: (_) => _dirty = true,
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          value: _draft.sponsorInterested,
          activeColor: _remdyNavy,
          title: Text(t('create_event_promote_checkbox')),
          subtitle: Text(t('create_event_promote_text')),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          onChanged: (v) =>
              _setDraft(_draft.copyWith(sponsorInterested: v == true)),
        ),
      ],
    );
  }

  Widget _stepReview() {
    _pullTextFieldsIntoDraft();
    final t = AppTexts.t;
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(k,
                  style: const TextStyle(
                      color: _muted, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(v.isEmpty ? '—' : v,
                  style: const TextStyle(
                      color: _text, fontWeight: FontWeight.w800)),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        row(t('create_event_name'), _draft.title),
        row(t('create_event_category'), _draft.category),
        row(t('create_event_city'),
            '${_draft.city} ${_draft.stateName}'.trim()),
        row(t('create_event_place'), _draft.placeName),
        row(t('events_timezone_label'), _draft.eventTimeZone),
        row(
          t('create_event_pick_date'),
          '${_fmtDate(_draft.startDate)} ${_draft.startTime} → ${_fmtDate(_draft.endDate)} ${_draft.endTime}',
        ),
        row(t('event_wizard_ticket_type'),
            t('event_wizard_ticket_${_draft.ticketType}')),
        row(t('events_tab_schedule'), '${_draft.schedule.length}'),
        row(t('events_tab_attractions'), '${_draft.attractions.length}'),
        row(
          t('create_event_add_photos'),
          '${_draft.photoUrls.length + _draft.pendingPhotoPaths.length}',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.t;
    final title = widget.title ??
        (widget.isEdit ? t('edit_event') : t('create_event_title'));

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _onPopInvoked(didPop);
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          surfaceTintColor: _bg,
          elevation: 0,
          iconTheme: const IconThemeData(color: _text),
          title: Text(
            title,
            style: const TextStyle(color: _text, fontWeight: FontWeight.w900),
          ),
        ),
        body: KeyboardDismissOnTap(
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t(_stepKeys[_step]),
                        style: const TextStyle(
                          color: _remdyNavy,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: (_step + 1) / EventEditorialDraft.stepCount,
                          minHeight: 6,
                          backgroundColor: _border,
                          color: _remdyNavy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_step + 1}/${EventEditorialDraft.stepCount}',
                        style: const TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      _stepInfo(),
                      _stepDatePlace(),
                      _stepTickets(),
                      _stepMedia(),
                      _stepProgram(),
                      _stepExtra(),
                      _stepReview(),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _submitting ? null : _goBack,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _remdyNavy,
                            side: const BorderSide(color: _remdyNavy),
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: Text(
                            _step == 0
                                ? t('event_cancel')
                                : t('event_wizard_back'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _submitting ? null : _goNext,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _remdyNavy,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _step == EventEditorialDraft.stepCount - 1
                                      ? (widget.isEdit
                                          ? t('event_wizard_save')
                                          : t('create_event_submit'))
                                      : t('event_wizard_next'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                    ],
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
