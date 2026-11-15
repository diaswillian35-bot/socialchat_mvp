import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';
import '../services/profile_about.dart';
import '../services/profile_completion.dart';
import '../services/profile_photo.dart';
import '../services/user_interests.dart';
import '../widgets/interest_chips.dart';
import '../widgets/keyboard_dismiss.dart';
import '../widgets/profile_photo_picker.dart';
import 'delete_account_page.dart';
import 'splash_page.dart';

/// Conta já marcada como completa, mas falta foto, bio ou interesse.
/// Mostra só o que falta. Não dá para voltar (Apple 5.1.1: Sair / Excluir).
class RequireProfileCompletionPage extends StatefulWidget {
  const RequireProfileCompletionPage({
    super.key,
    this.initialData,
    this.providerPhotoUrl,
    this.uid,
    this.onSave,
    this.onLogout,
    this.pickPhoto,
  });

  /// Nos testes, evita Firestore: dados iniciais e callbacks.
  final Map<String, dynamic>? initialData;
  final String? providerPhotoUrl;
  final String? uid;
  final Future<void> Function(String uid, Map<String, dynamic> payload)? onSave;
  final Future<void> Function()? onLogout;
  final Future<String?> Function(String uid)? pickPhoto;

  @override
  State<RequireProfileCompletionPage> createState() =>
      _RequireProfileCompletionPageState();
}

class _RequireProfileCompletionPageState
    extends State<RequireProfileCompletionPage> {
  static const Color _bg = Color(0xFFF6F7FB);
  static const Color _text = Color(0xFF111827);
  static const Color _border = Color(0xFFE5E7EB);

  final _aboutC = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _picking = false;
  String? _err;
  String _photoUrl = '';
  List<String> _interests = const [];
  bool _needPhoto = false;
  bool _needBio = false;
  bool _needInterest = false;
  String _uid = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _aboutC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final injected = widget.initialData;
    final uid = widget.uid ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    Map<String, dynamic> data;
    if (injected != null) {
      data = Map<String, dynamic>.from(injected);
    } else if (uid.isEmpty) {
      data = const {};
    } else {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      data = snap.data() ?? {};
    }

    var photo = ProfilePhoto.urlFromData(data);
    if (photo.isEmpty) {
      var provider = (widget.providerPhotoUrl ?? '').trim();
      // Em testes com initialData não tocamos no Firebase Auth.
      if (provider.isEmpty && widget.initialData == null) {
        provider = ProfilePhoto.providerPhotoUrl(
            FirebaseAuth.instance.currentUser);
      }
      if (provider.startsWith('http')) photo = provider;
    }

    if (!mounted) return;
    setState(() {
      _uid = uid;
      _needPhoto = ProfileCompletion.missingPhoto(data);
      _needBio = ProfileCompletion.missingBio(data);
      _needInterest = ProfileCompletion.missingInterest(data);
      _photoUrl = photo;
      _aboutC.text = ProfileAbout.clamp((data['about'] ?? '').toString());
      _interests = UserInterests.fromUserData(data);
      _loading = false;
    });
  }

  Future<void> _logout() async {
    if (widget.onLogout != null) {
      await widget.onLogout!();
      return;
    }
    await FirebaseAuth.instance.signOut();
  }

  void _openDeleteAccount() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DeleteAccountPage()),
    );
  }

  Future<void> _pickPhoto() async {
    if (_uid.isEmpty || _picking) return;
    setState(() => _picking = true);
    try {
      final pick = widget.pickPhoto ?? ProfilePhoto.pickAndUpload;
      final url = await pick(_uid);
      if (!mounted || url == null || url.isEmpty) return;
      setState(() {
        _photoUrl = url;
        _err = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _err = AppTexts.current.get('profile_photo_required'));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final t = AppTexts.current;
    final photoUrl = _photoUrl.trim();
    if (_needPhoto && !ProfilePhoto.hasPhoto({'photoUrl': photoUrl})) {
      setState(() => _err = t.get('profile_photo_required'));
      return;
    }
    if (_needBio && ProfileAbout.clamp(_aboutC.text).isEmpty) {
      setState(() => _err = t.get('profile_bio_required'));
      return;
    }
    if (_needInterest && UserInterests.sanitize(_interests).isEmpty) {
      setState(() => _err = t.get('profile_interest_required'));
      return;
    }

    setState(() {
      _saving = true;
      _err = null;
    });

    final payload = ProfileCompletion.repairPayload(
      needPhoto: _needPhoto,
      photoUrl: photoUrl,
      needBio: _needBio,
      about: _aboutC.text,
      needInterest: _needInterest,
      interests: _interests,
    );

    try {
      if (widget.onSave != null) {
        await widget.onSave!(_uid, payload);
      } else {
        if (_uid.isEmpty) {
          setState(() => _err = t.get('login_required_save_profile.'));
          return;
        }
        payload['updatedAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .set(payload, SetOptions(merge: true));
      }
      if (!mounted) return;
      if (widget.onSave != null) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SplashPage()),
        (_) => false,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _err = t.get('login_required_save_profile.'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;
    final appBar = AppBar(
      backgroundColor: Colors.white,
      foregroundColor: _text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      title: Text(
        t.get('profile_complete_title'),
        style: const TextStyle(color: _text, fontWeight: FontWeight.w900),
      ),
      actions: [
        IconButton(
          key: const Key('require_profile_logout'),
          tooltip: t.get('logout'),
          icon: const Icon(Icons.logout),
          onPressed: _logout,
        ),
        IconButton(
          key: const Key('require_profile_delete'),
          tooltip: t.get('delete_my_account'),
          icon: const Icon(Icons.delete_forever_outlined),
          onPressed: _openDeleteAccount,
        ),
      ],
    );

    if (_loading) {
      return PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: _bg,
          appBar: appBar,
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: _bg,
        appBar: appBar,
        body: KeyboardDismissOnTap(
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                t.get(ProfileCompletion.bodyKey(
                  needPhoto: _needPhoto,
                  needBio: _needBio,
                  needInterest: _needInterest,
                )),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _text,
                ),
              ),
              const SizedBox(height: 16),
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
              if (_needPhoto) ...[
                ProfilePhotoPicker(
                  photoUrl: _photoUrl,
                  onPick: _saving || _picking ? null : _pickPhoto,
                  busy: _picking,
                  showError: _err == t.get('profile_photo_required') &&
                      _photoUrl.isEmpty,
                ),
                const SizedBox(height: 16),
              ],
              if (_needBio) ...[
                Text(
                  t.get('about_you'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  key: const Key('require_profile_about'),
                  controller: _aboutC,
                  maxLength: ProfileAbout.maxLength,
                  maxLines: 4,
                  enabled: !_saving,
                  decoration: InputDecoration(
                    hintText: t.get('about_you_hint'),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _border),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (_needInterest) ...[
                InterestChips(
                  selected: _interests,
                  onChanged: _saving
                      ? (_) {}
                      : (next) => setState(() {
                            _interests = next;
                            _err = null;
                          }),
                ),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  key: const Key('require_profile_save'),
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF313A5F),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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
                          t.get('save'),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
