import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'place_submissions_page.dart';
import '../../../l10n/app_texts.dart';
import '../../../widget/city_search_dialog.dart';
import '../../../widgets/keyboard_dismiss.dart';
import '../../../widgets/remdy_keyboard_caps.dart';
import '../data/place_submission_service.dart';
import '../locais_strings.dart';
import '../models/place_listing.dart';

/// "Adicionar local" / "Editar local": mesmo fluxo e visual do wizard de
/// criar evento (AppBar, passo + barra de progresso, Voltar/Próximo).
class PlaceEditorPage extends StatefulWidget {
  const PlaceEditorPage({super.key, this.placeId, this.adminReview = false});

  /// Nulo = novo local.
  final String? placeId;

  /// Aberto pela seção "Locais em análise" do Modo administrador.
  final bool adminReview;

  @override
  State<PlaceEditorPage> createState() => _PlaceEditorPageState();
}

class _PlaceEditorPageState extends State<PlaceEditorPage> {
  // Mesmas constantes do EventEditorialWizard.
  static const Color _bg = Color(0xFFF6F7FB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyNavy = Color(0xFF313A5F);

  static const List<String> _stepKeys = [
    'place_step_info',
    'place_step_location',
    'place_step_contact',
    'place_step_photos',
    'place_step_menu',
    'place_step_review',
  ];

  final _pageController = PageController();
  final _picker = ImagePicker();
  PlaceDraft _draft = PlaceDraft();
  int _step = 0;
  bool _loading = false;
  bool _submitting = false;

  final _nameC = TextEditingController();
  final _descC = TextEditingController();
  final _addressC = TextEditingController();
  final _hoursC = TextEditingController();
  final _phoneC = TextEditingController();
  final _whatsC = TextEditingController();
  final _siteC = TextEditingController();
  final _menuUrlC = TextEditingController();
  final _deliveryAreaC = TextEditingController();

  bool get _isEdit => (widget.placeId ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_isEdit) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final d = await PlaceSubmissionService.load(widget.placeId!);
      if (d != null) _draft = d;
    } catch (_) {}
    _nameC.text = _draft.name;
    _descC.text = _draft.description;
    _addressC.text = _draft.addressLine;
    _hoursC.text = _draft.hoursNote;
    _phoneC.text = _draft.phone;
    _whatsC.text = _draft.whatsapp;
    _siteC.text = _draft.websiteUrl;
    _menuUrlC.text = _draft.menuUrl;
    _deliveryAreaC.text = _draft.deliveryArea;
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in [
      _nameC,
      _descC,
      _addressC,
      _hoursC,
      _phoneC,
      _whatsC,
      _siteC,
      _menuUrlC,
      _deliveryAreaC,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _pull() {
    _draft
      ..name = _nameC.text
      ..description = _descC.text
      ..addressLine = _addressC.text
      ..hoursNote = _hoursC.text
      ..phone = _phoneC.text
      ..whatsapp = _whatsC.text
      ..websiteUrl = _siteC.text
      ..menuUrl = _menuUrlC.text
      ..deliveryArea = _deliveryAreaC.text;
  }

  bool _isHttpsOrEmpty(String v) {
    final s = v.trim();
    return s.isEmpty || s.startsWith('https://');
  }

  String? _validate(int step) {
    _pull();
    switch (step) {
      case 0:
        return _draft.name.trim().length < 2 ? 'place_err_name' : null;
      case 1:
        return _draft.locationValid ? null : 'place_err_city';
      case 2:
        return _isHttpsOrEmpty(_draft.websiteUrl) ? null : 'place_err_link';
      case 3:
        return _draft.photoUrls.length + _draft.pendingPhotoPaths.length == 0
            ? 'place_err_photo'
            : null;
      case 4:
        return _isHttpsOrEmpty(_draft.menuUrl) ? null : 'place_err_link';
    }
    return null;
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

  Future<void> _goNext() async {
    dismissAppKeyboard();
    final err = _validate(_step);
    if (err != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.t(err))),
      );
      return;
    }
    if (_step >= _stepKeys.length - 1) {
      await _submit();
      return;
    }
    setState(() => _step++);
    _pageController.jumpToPage(_step);
  }

  void _goBack() {
    dismissAppKeyboard();
    if (_step == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() => _step--);
    _pageController.jumpToPage(_step);
  }

  Future<void> _submit() async {
    _pull();
    setState(() => _submitting = true);
    try {
      await PlaceSubmissionService.save(_draft);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppTexts.t(
            widget.adminReview ? 'place_saved' : 'place_submit_success',
          )),
        ),
      );
      Navigator.pop(context, true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final key = e.message == 'too_many_pending'
          ? 'place_err_too_many'
          : 'place_submit_error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.t(key))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppTexts.t('place_submit_error'))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _pickCity() async {
    final result = await CitySearchDialog.openDefault(
      context: context,
      countryCode: _draft.countryCode.toLowerCase(),
    );
    if (result == null || !mounted) return;
    setState(() {
      _draft
        ..cityName = result.cityName
        ..stateName = result.stateName
        ..cityDisplay = result.displayLocation
        ..latitude = result.lat
        ..longitude = result.lng;
    });
  }

  Future<void> _pick({required bool menu}) async {
    final current = menu
        ? _draft.menuPhotoUrls.length + _draft.pendingMenuPaths.length
        : _draft.photoUrls.length + _draft.pendingPhotoPaths.length;
    final remaining = PlaceDraft.maxPhotos - current;
    if (remaining <= 0) return;
    final picked = await _picker.pickMultiImage(imageQuality: 80);
    if (picked.isEmpty || !mounted) return;
    final paths = picked.take(remaining).map((e) => e.path);
    setState(() {
      if (menu) {
        _draft.pendingMenuPaths.addAll(paths);
      } else {
        _draft.pendingPhotoPaths.addAll(paths);
      }
    });
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

  Widget _photoThumb({
    String? remote,
    String? localPath,
    required VoidCallback onRemove,
  }) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: localPath != null
              ? Image.file(File(localPath),
                  width: 88, height: 88, fit: BoxFit.cover)
              : Image.network(remote!,
                  width: 88, height: 88, fit: BoxFit.cover),
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
      ],
    );
  }

  Widget _photoGrid({
    required List<String> remote,
    required List<String> pending,
    required VoidCallback onAdd,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < remote.length; i++)
          _photoThumb(
            remote: remote[i],
            onRemove: () => setState(() => remote.removeAt(i)),
          ),
        for (var i = 0; i < pending.length; i++)
          _photoThumb(
            localPath: pending[i],
            onRemove: () => setState(() => pending.removeAt(i)),
          ),
        if (remote.length + pending.length < PlaceDraft.maxPhotos)
          InkWell(
            onTap: onAdd,
            child: Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: const Icon(Icons.add_a_photo_outlined, color: _remdyNavy),
            ),
          ),
      ],
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, color: _muted),
      );

  Widget _stepInfo(LocaisStrings strings) {
    final t = AppTexts.t;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        TextField(
          key: const Key('place_name_field'),
          controller: _nameC,
          textCapitalization: RemdyKeyboardCaps.words,
          decoration: _dec(t('place_name'), hint: t('place_name_hint')),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _draft.category,
          decoration: _dec(t('place_category')),
          items: PlaceDraft.categories
              .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(strings.categoryName(PlaceCategory.parse(c))),
                  ))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _draft.category = v);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _descC,
          textCapitalization: RemdyKeyboardCaps.sentences,
          maxLines: 5,
          decoration: _dec(t('place_description')),
        ),
      ],
    );
  }

  Widget _stepLocation() {
    final t = AppTexts.t;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        DropdownButtonFormField<String>(
          value: const ['BR', 'CA', 'PT'].contains(_draft.countryCode)
              ? _draft.countryCode
              : 'BR',
          decoration: _dec(t('place_country')),
          items: const [
            DropdownMenuItem(value: 'BR', child: Text('🇧🇷 Brasil')),
            DropdownMenuItem(value: 'CA', child: Text('🇨🇦 Canada')),
            DropdownMenuItem(value: 'PT', child: Text('🇵🇹 Portugal')),
          ],
          onChanged: (v) {
            if (v == null || v == _draft.countryCode) return;
            setState(() {
              _draft
                ..countryCode = v
                ..cityName = ''
                ..stateName = ''
                ..cityDisplay = ''
                ..latitude = null
                ..longitude = null;
            });
          },
        ),
        const SizedBox(height: 12),
        _chipButton(
          icon: Icons.location_city_outlined,
          text: _draft.locationValid && _draft.cityDisplay.isNotEmpty
              ? _draft.cityDisplay
              : t('place_pick_city'),
          onTap: _pickCity,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _addressC,
          textCapitalization: RemdyKeyboardCaps.words,
          decoration: _dec(
            t(_draft.deliveryOnly ? 'place_address_optional' : 'place_address'),
            hint: t('place_address_hint'),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          key: const Key('place_delivery_only_switch'),
          contentPadding: EdgeInsets.zero,
          title: Text(t('place_delivery_only')),
          subtitle: Text(t('place_delivery_only_hint')),
          value: _draft.deliveryOnly,
          activeThumbColor: _remdyNavy,
          onChanged: (v) => setState(() => _draft.deliveryOnly = v),
        ),
        if (_draft.deliveryOnly) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('place_delivery_area_field'),
            controller: _deliveryAreaC,
            textCapitalization: RemdyKeyboardCaps.sentences,
            maxLength: 120,
            decoration: _dec(
              t('place_delivery_area'),
              hint: t('place_delivery_area_hint'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _stepContact() {
    final t = AppTexts.t;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        TextField(
          controller: _hoursC,
          textCapitalization: RemdyKeyboardCaps.sentences,
          maxLines: 3,
          decoration: _dec(t('place_hours'), hint: t('place_hours_hint')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneC,
          keyboardType: TextInputType.phone,
          textCapitalization: RemdyKeyboardCaps.none,
          decoration: _dec(t('place_phone')),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _whatsC,
          keyboardType: TextInputType.phone,
          textCapitalization: RemdyKeyboardCaps.none,
          decoration: _dec('WhatsApp'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _siteC,
          keyboardType: TextInputType.url,
          textCapitalization: RemdyKeyboardCaps.none,
          decoration: _dec(t('place_website'), hint: 'https://'),
        ),
      ],
    );
  }

  Widget _stepPhotos() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _label(AppTexts.t('place_add_photos')),
        const SizedBox(height: 12),
        _photoGrid(
          remote: _draft.photoUrls,
          pending: _draft.pendingPhotoPaths,
          onAdd: () => _pick(menu: false),
        ),
      ],
    );
  }

  Widget _stepMenu() {
    final t = AppTexts.t;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _label(t('place_menu_photos')),
        const SizedBox(height: 12),
        _photoGrid(
          remote: _draft.menuPhotoUrls,
          pending: _draft.pendingMenuPaths,
          onAdd: () => _pick(menu: true),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _menuUrlC,
          keyboardType: TextInputType.url,
          textCapitalization: RemdyKeyboardCaps.none,
          decoration: _dec(t('place_menu_link'), hint: 'https://'),
        ),
      ],
    );
  }

  Widget _stepReview(LocaisStrings strings) {
    final t = AppTexts.t;
    _pull();
    Widget row(String label, String value) => ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label,
              style:
                  const TextStyle(color: _muted, fontWeight: FontWeight.w700)),
          subtitle: Text(value.isEmpty ? '—' : value,
              style: const TextStyle(color: _text)),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        row(t('place_name'), _draft.name),
        row(t('place_category'),
            strings.categoryName(PlaceCategory.parse(_draft.category))),
        row(
            t('place_step_location'),
            [_draft.addressLine, _draft.cityDisplay]
                .where((e) => e.trim().isNotEmpty)
                .join(' · ')),
        row(t('place_hours'), _draft.hoursNote),
        row(t('place_phone'), _draft.phone),
        row(
          t('place_add_photos'),
          '${_draft.photoUrls.length + _draft.pendingPhotoPaths.length}',
        ),
        const SizedBox(height: 8),
        Text(
          t('place_review_notice'),
          style: const TextStyle(
            color: _muted,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.t;
    final strings = LocaisStrings.of(context);
    final title = _isEdit ? t('place_edit_title') : t('place_add_title');

    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _remdyNavy)),
      );
    }

    return Scaffold(
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
        actions: [
          if (!_isEdit)
            IconButton(
              key: const Key('place_my_places'),
              tooltip: t('place_mine_title'),
              icon: const Icon(Icons.storefront),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      const PlaceSubmissionsPage(adminPending: false),
                ),
              ),
            ),
        ],
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
                        value: (_step + 1) / _stepKeys.length,
                        minHeight: 6,
                        backgroundColor: _border,
                        color: _remdyNavy,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_step + 1}/${_stepKeys.length}',
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
                    _stepInfo(strings),
                    _stepLocation(),
                    _stepContact(),
                    _stepPhotos(),
                    _stepMenu(),
                    _stepReview(strings),
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
                        key: const Key('place_next_button'),
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
                                _step == _stepKeys.length - 1
                                    ? (_isEdit
                                        ? t('event_wizard_save')
                                        : t('place_submit'))
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
    );
  }
}
