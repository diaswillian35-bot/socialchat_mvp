import 'dart:io';


import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';


import 'Premium_page.dart'; // <-- se o seu for "premium_page.dart", troque aqui


class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});


  @override
  State<ProfilePage> createState() => _ProfilePageState();
}


class _ProfilePageState extends State<ProfilePage> {
  final _nameC = TextEditingController();
  final _countryC = TextEditingController();
  final _aboutC = TextEditingController();


  bool _loading = false;


  String _photoUrl = '';
  List<String> _gallery = []; // máx 9
  bool _isPremium = false;


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


  @override
  void initState() {
    super.initState();
    _load();
  }


  @override
  void dispose() {
    _nameC.dispose();
    _countryC.dispose();
    _aboutC.dispose();
    super.dispose();
  }


  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final snap = await _ref.get();
      final data = snap.data() ?? {};


      _nameC.text = (data['name'] ?? '').toString();
      _countryC.text = (data['country'] ?? '').toString();
      _aboutC.text = (data['about'] ?? '').toString();


      _photoUrl = (data['photoUrl'] ?? '').toString();
      _isPremium = data['isPremium'] == true;


      final g = data['gallery'];
      if (g is List) {
        _gallery = g
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList();
      } else {
        _gallery = [];
      }
    } catch (_) {
      // silencioso
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  // padroniza: "canada" -> "Canada", "estados unidos" -> "Estados Unidos"
  String _capitalizeWords(String input) {
    final s = input.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (s.isEmpty) return s;
    return s
        .split(' ')
        .map((w) {
          if (w.isEmpty) return w;
          final lower = w.toLowerCase();
          return lower[0].toUpperCase() + lower.substring(1);
        })
        .join(' ');
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
        const SnackBar(content: Text('Você já tem 9 fotos na galeria.')),
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
    final country = _capitalizeWords(_countryC.text);
    final about = _aboutC.text.trim();


    setState(() => _loading = true);


    try {
      await _ref.set(
        {
          'name': name,
          'country': country,
          'about': about,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );


      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Salvo'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.all(12),
        ),
      );


      // ✅ mantém seu fluxo: salva e volta
      if (Navigator.canPop(context)) Navigator.pop(context, true); // ✅ REABRE MENU
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  // ✅ Input padrão Remdy (visual apenas)
  InputDecoration _inputDeco(String label) {
    return InputDecoration(
      labelText: label,
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


  // ✅ Carrossel: foto principal (se existir) + galeria
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
            // se tem foto principal, ela é índice 0
            final offset = _photoUrl.isNotEmpty ? 1 : 0;
            _openCarousel(initialIndex: offset + i);
          },
          onLongPress: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('Remover foto?'),
                content: const Text('Essa foto será removida da sua galeria.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancelar'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Remover'),
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


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,


        // ✅ VOLTAR pedindo reabrir menu (true)
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context, true), // ✅ REABRE MENU
        ),


        title: const Text(
          'Perfil',
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
              decoration: _inputDeco('Nome'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),


            TextField(
              controller: _countryC,
              decoration: _inputDeco('País (ex: Canadá, Brasil, França...)'),
              textInputAction: TextInputAction.next,
              onChanged: (v) {},
              onEditingComplete: () {
                final fixed = _capitalizeWords(_countryC.text);
                if (fixed != _countryC.text) {
                  _countryC.value = _countryC.value.copyWith(
                    text: fixed,
                    selection: TextSelection.collapsed(offset: fixed.length),
                  );
                }
                FocusScope.of(context).nextFocus();
              },
            ),
            const SizedBox(height: 12),


            TextField(
              controller: _aboutC,
              maxLines: 4,
              decoration: _inputDeco('Sobre você'),
            ),


            const SizedBox(height: 18),
            const Text(
              'Galeria (até 9 fotos)',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: _text,
              ),
            ),
            const SizedBox(height: 10),
            _galleryGrid(),


            const SizedBox(height: 18),


            // ✅ Premium (como estava)
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
                  _isPremium ? 'Premium (ativo)' : 'Virar Premium',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
            ),


            const SizedBox(height: 12),


            // ✅ Botão salvar (fica só aqui)
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
                  label: const Text(
                    'Salvar alterações',
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
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Fotos'),
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
