import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import '../l10n/app_texts.dart';


import 'Premium_page.dart'; // <-- se o seu for "premium_page.dart", troque aqui

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameC = TextEditingController();
  final _cityC = TextEditingController();
  final _aboutC = TextEditingController();
  String _stateName = '';
  String _cityName = '';
  String _displayLocation = '';

  bool _loading = false;
 
  String _photoUrl = '';
  List<String> _gallery = []; // máx 9
  bool _isPremium = false;

  // ✅ país travado (somente visual)
  String _homeCountryCode = '';
  String _countryName = '';
  bool _localeLoaded = false;
  

  String get _uid => FirebaseAuth.instance.currentUser!.uid;
  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('users').doc(_uid);

  // ✅ Padrão Home (visual apenas)
  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);

  static const LinearGradient _primaryGradient = LinearGradient(
    colors: [
      Color(0xFF313A5F), // azul Remdy
      Color(0xFF264E9A), // azul logo
    ],
  );

  static const Map<String, String> _countryNames = {
    'br': 'Brasil',
    'ca': 'Canadá',
    'pt': 'Portugal',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }
@override
void didChangeDependencies() {
  super.didChangeDependencies();


  if (_localeLoaded) return;
  _localeLoaded = true;


  final locale = Localizations.localeOf(context);


  AppTexts.load(locale).then((_) {
    if (mounted) setState(() {});
  });
}

  @override
  void dispose() {
    _nameC.dispose();
    _cityC.dispose();
    _aboutC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final snap = await _ref.get();
      final data = snap.data() ?? {};

      _nameC.text = (data['name'] ?? '').toString();
      _stateName = (data['stateName'] ?? '').toString().trim();
_cityName = (data['cityName'] ?? '').toString().trim();
_displayLocation = (data['displayLocation'] ?? '').toString().trim();


_cityC.text = _displayLocation.isNotEmpty
    ? _displayLocation
    : (_cityName.isNotEmpty ? _cityName : (data['city'] ?? '').toString());

      _aboutC.text = (data['about'] ?? '').toString();

      _photoUrl = (data['photoUrl'] ?? '').toString();
      _isPremium = data['isPremium'] == true;

      final g = data['gallery'];
      if (g is List) {
        _gallery = g.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
      } else {
        _gallery = [];
      }

      // ✅ país vem do homeCountryCode (travado)
      _homeCountryCode =
          (data['homeCountryCode'] ?? '').toString().trim().toLowerCase();

      _countryName = _countryNames[_homeCountryCode] ?? AppTexts.current.get('your_country');
    } catch (_) {
      // silencioso
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _uploadImage(XFile file, {required String folder}) async {
    final storage = FirebaseStorage.instance;
    final id = const Uuid().v4();
    final path = 'users/$_uid/$folder/$id.jpg';
    final ref = storage.ref().child(path);

    if (kIsWeb) {
      final bytes = await file.readAsBytes();
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    } else {
      await ref.putFile(
        File(file.path),
        SettableMetadata(contentType: 'image/jpeg'),
      );
    }

    return await ref.getDownloadURL();
  }

  Future<void> _pickMainPhoto() async {
    if (_loading) return;
    final picker = ImagePicker();
    final file =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return;

    setState(() => _loading = true);
    try {
      final url = await _uploadImage(file, folder: 'profile');
      _photoUrl = url;

      await _ref.set(
        {
          'photoUrl': _photoUrl,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // silencioso
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addGalleryPhoto() async {
    if (_loading) return;
    if (_gallery.length >= 9) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(content: Text(AppTexts.current.get('gallery_limit_reached'))),
      );
      return;
    }

    final picker = ImagePicker();
    final file =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return;

    setState(() => _loading = true);
    try {
      final url = await _uploadImage(file, folder: 'gallery');
      _gallery = [..._gallery, url];

      await _ref.set(
        {
          'gallery': _gallery,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // silencioso
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeGalleryPhoto(int index) async {
    if (_loading) return;
    if (index < 0 || index >= _gallery.length) return;

    setState(() => _loading = true);
    try {
      final newList = [..._gallery]..removeAt(index);
      _gallery = newList;

      await _ref.set(
        {
          'gallery': _gallery,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // silencioso
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_loading) return;

    final name = _nameC.text.trim();
 final city = _cityC.text.trim();


// padrão novo
_displayLocation = city;
if (_cityName.isEmpty) {
  _cityName = city;
}

    final about = _aboutC.text.trim();

    if (city.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
         SnackBar(
          content: Text(AppTexts.current.get('city_required_events')),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(12),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      // ✅ country é salvo automaticamente a partir do homeCountryCode
    await _ref.set({
  'name': name,
  'city': city, // compatibilidade antiga
  'cityName': _cityName.isNotEmpty ? _cityName : city,
  'stateName': _stateName,
  'displayLocation': _displayLocation.isNotEmpty ? _displayLocation : city,
  'country': _countryName,
  'about': about,
  'updatedAt': FieldValue.serverTimestamp(),
}, SetOptions(merge: true));


      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
  content: Text(AppTexts.current.get('saved')),
  duration: const Duration(seconds: 1),
  behavior: SnackBarBehavior.floating,
  margin: const EdgeInsets.all(12),
),

      );

      if (Navigator.canPop(context)) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
   ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('${AppTexts.current.get('save_error')}: $e'),
  ),
);

    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  InputDecoration _inputDeco(String label, {String? hint, String? helper}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      helperStyle: const TextStyle(color: _muted, fontWeight: FontWeight.w600),
      labelStyle: const TextStyle(color: _muted, fontWeight: FontWeight.w700),
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

  String _flagEmoji(String code) {
    final upper = code.toUpperCase();
    if (upper.length != 2) return '🏳️';
    final int first = upper.codeUnitAt(0) - 0x41 + 0x1F1E6;
    final int second = upper.codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCodes([first, second]);
  }

  Widget _lockedCountryField() {
    return InputDecorator(
      decoration: _inputDeco( AppTexts.current.get('country'),
       
        helper: AppTexts.current.get('country_locked_helper'),
      ),
      child: Row(
        children: [
          Text(
            _flagEmoji(_homeCountryCode.isEmpty ? 'BR' : _homeCountryCode),
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _countryName,
              style: const TextStyle(
                color: _text,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.lock_outline_rounded, color: _muted, size: 18),
        ],
      ),
    );
  }

  List<String> _carouselUrls() {
    return <String>[
      if (_photoUrl.isNotEmpty) _photoUrl,
      ..._gallery,
    ];
  }

  void _openCarousel({required int initialIndex}) {
    final urls = _carouselUrls();
    if (urls.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _PhotoCarouselPage(
          urls: urls,
          initialIndex: initialIndex.clamp(0, urls.length - 1),
        ),
      ),
    );
  }

  Widget _mainPhoto() {
    return Stack(
      alignment: Alignment.bottomRight,
      children: [
        InkWell(
          onTap: () {
            if (_photoUrl.isNotEmpty || _gallery.isNotEmpty) {
              _openCarousel(initialIndex: 0);
            }
          },
          borderRadius: BorderRadius.circular(999),
          child: CircleAvatar(
            radius: 46,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: _photoUrl.isNotEmpty ? NetworkImage(_photoUrl) : null,
            child: _photoUrl.isEmpty
                ? const Icon(Icons.person, size: 42, color: Color(0xFF9CA3AF))
                : null,
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: InkWell(
            onTap: _pickMainPhoto,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                gradient: _primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.camera_alt, size: 18, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _galleryGrid() {
    final slots = List<String?>.filled(9, null);
    for (int i = 0; i < _gallery.length && i < 9; i++) {
      slots[i] = _gallery[i];
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 9,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemBuilder: (context, i) {
        final url = slots[i];

        if (url == null) {
          return InkWell(
            onTap: _addGalleryPhoto,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
              ),
              child: const Center(
                child: Icon(Icons.add, size: 28, color: Color(0xFF6B7280)),
              ),
            ),
          );
        }

        return InkWell(
          onTap: () {
            final offset = _photoUrl.isNotEmpty ? 1 : 0;
            _openCarousel(initialIndex: offset + i);
          },
          onLongPress: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(AppTexts.current.get('remove_photo_title')),
                content: Text( AppTexts.current.get('remove_photo_content')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child:  Text(AppTexts.current.get('cancel')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text( AppTexts.current.get('remove')),
                  ),
                ],
              ),
            );
            if (ok == true) _removeGalleryPhoto(i);
          },
          borderRadius: BorderRadius.circular(14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(url, fit: BoxFit.cover),
          ),
        );
      },
    );
  }

  Widget _infoBar(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 18, color: _muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: _muted,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context, true),
        ),
        title: Text(
          AppTexts.current.get('profile'),
          style: TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        actions: const [],
      ),
      body: AbsorbPointer(
        absorbing: _loading,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Center(child: _mainPhoto()),
            const SizedBox(height: 18),

            TextField(
              controller: _nameC,
              decoration: _inputDeco ( AppTexts.current.get ('name')),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),

            // ✅ país travado
            _lockedCountryField(),
            const SizedBox(height: 12),

            TextField(
              controller: _cityC,
              decoration: _inputDeco(AppTexts.current.get('city'),hint:AppTexts.current.get('city_example'),
),

              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),

            _infoBar(AppTexts.current.get('city_required_info')),
            const SizedBox(height: 12),

            TextField(
              controller: _aboutC,
              maxLines: 4,
            

decoration: _inputDeco(
  AppTexts.current.get('about_you'),
  helper:AppTexts.current.get('about_you_helper'),
),

            ),

            const SizedBox(height: 18),
             Text(
             AppTexts.current.get('gallery_up_to_9'),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: _text,
              ),
            ),
            const SizedBox(height: 10),
            _galleryGrid(),

            const SizedBox(height: 18),

            SizedBox(
              height: 46,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PremiumPage()),
                  );
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: _border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  backgroundColor: Colors.white,
                ),
                icon: Icon(
                  _isPremium ? Icons.star : Icons.star_border,
                  color: const Color(0xFF313A5F),
                ),
                label: Text(
                 
  _isPremium ? AppTexts.current.get('premium_active_short') : AppTexts.current.get('go_premium'),

                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            SizedBox(
              height: 46,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: _primaryGradient,
                ),
                child: ElevatedButton.icon(
                  onPressed: _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.save, color: Colors.white),
                  label: Text(
                    AppTexts.current.get('save_changes'),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),

            if (_loading) ...[
              const SizedBox(height: 14),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}

// ======================
// ✅ Tela do carrossel
// ======================
class _PhotoCarouselPage extends StatefulWidget {
  final List<String> urls;
  final int initialIndex;

  const _PhotoCarouselPage({
    required this.urls,
    required this.initialIndex,
  });

  @override
  State<_PhotoCarouselPage> createState() => _PhotoCarouselPageState();
}

class _PhotoCarouselPageState extends State<_PhotoCarouselPage> {
  late final PageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(AppTexts.current.get('photos')),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.urls.length,
        itemBuilder: (_, index) {
          final url = widget.urls[index];
          return InteractiveViewer(
            child: Center(
              child: Image.network(url, fit: BoxFit.contain),
            ),
          );
        },
      ),
    );
  }
}