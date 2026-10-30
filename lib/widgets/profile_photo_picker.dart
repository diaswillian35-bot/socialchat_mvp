import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';

/// Foto principal do perfil (mesmo visual do Menu > Perfil): avatar 46 +
/// botão de câmera com o gradiente da marca. [showError] mostra o aviso
/// de foto obrigatória.
class ProfilePhotoPicker extends StatelessWidget {
  const ProfilePhotoPicker({
    super.key,
    required this.photoUrl,
    required this.onPick,
    this.busy = false,
    this.showError = false,
  });

  final String photoUrl;
  final VoidCallback? onPick;
  final bool busy;
  final bool showError;

  static const LinearGradient _primaryGradient = LinearGradient(
    colors: [Color(0xFF313A5F), Color(0xFF264E9A)],
  );

  @override
  Widget build(BuildContext context) {
    final has = photoUrl.isNotEmpty;
    return Column(
      key: const Key('profile_photo_picker'),
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            InkWell(
              onTap: busy ? null : onPick,
              borderRadius: BorderRadius.circular(999),
              child: CircleAvatar(
                radius: 46,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: has ? NetworkImage(photoUrl) : null,
                child: busy
                    ? const CircularProgressIndicator()
                    : has
                        ? null
                        : const Icon(Icons.person,
                            size: 42, color: Color(0xFF9CA3AF)),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: InkWell(
                key: const Key('profile_photo_pick'),
                onTap: busy ? null : onPick,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    gradient: _primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.camera_alt,
                      size: 18, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          AppTexts.current
              .get(has ? 'profile_photo_change' : 'profile_photo_add'),
          style: const TextStyle(
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w600,
              fontSize: 12),
        ),
        if (showError && !has)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              AppTexts.current.get('profile_photo_required'),
              key: const Key('profile_photo_required'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontWeight: FontWeight.w700,
                  fontSize: 12),
            ),
          ),
      ],
    );
  }
}
