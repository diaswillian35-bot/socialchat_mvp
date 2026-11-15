import 'profile_about.dart';
import 'profile_photo.dart';
import 'user_interests.dart';

/// Perfil obrigatório para usar o app: foto + bio (`about`) + ≥1 interesse.
class ProfileCompletion {
  ProfileCompletion._();

  static bool hasPhoto(Map<String, dynamic>? data) =>
      ProfilePhoto.hasPhoto(data);

  static bool hasBio(Map<String, dynamic>? data) {
    if (data == null) return false;
    return ProfileAbout.clamp((data['about'] ?? '').toString()).isNotEmpty;
  }

  static bool hasInterest(Map<String, dynamic>? data) =>
      UserInterests.fromUserData(data).isNotEmpty;

  static bool hasLanguage(Map<String, dynamic>? data) {
    if (data == null) return false;
    final languages = (data['languages'] ?? '').toString().trim();
    final native = (data['nativeLanguage'] ?? '').toString().trim();
    return languages.isNotEmpty || native.isNotEmpty;
  }

  static bool isComplete(Map<String, dynamic>? data) =>
      hasPhoto(data) && hasBio(data) && hasInterest(data);

  /// Ainda não passou pelo Completar perfil (flag ou doc vazio).
  static bool needsInitialCompletion(Map<String, dynamic>? data) =>
      data == null || data['profileComplete'] != true;

  /// Já completou uma vez, mas falta foto, bio ou interesse (conta antiga /
  /// foto rejeitada).
  static bool needsRepair(Map<String, dynamic>? data) =>
      !needsInitialCompletion(data) && !isComplete(data);

  static bool needsCountrySetup(Map<String, dynamic>? data) {
    if (data == null) return true;
    final home = (data['homeCountryCode'] ?? '').toString().trim();
    return home.isEmpty || data['countryLocked'] != true;
  }

  static bool missingPhoto(Map<String, dynamic>? data) => !hasPhoto(data);
  static bool missingBio(Map<String, dynamic>? data) => !hasBio(data);
  static bool missingInterest(Map<String, dynamic>? data) => !hasInterest(data);

  /// Chave l10n do texto "Para continuar usando o Remdy…", conforme o que falta.
  static String bodyKey({
    required bool needPhoto,
    required bool needBio,
    required bool needInterest,
  }) {
    if (needPhoto && needBio && needInterest) {
      return 'profile_complete_body_all';
    }
    if (needPhoto && needBio) return 'profile_complete_body_photo_bio';
    if (needPhoto && needInterest) {
      return 'profile_complete_body_photo_interest';
    }
    if (needBio && needInterest) return 'profile_complete_body_bio_interest';
    if (needPhoto) return 'profile_complete_body_photo';
    if (needBio) return 'profile_complete_body_bio';
    if (needInterest) return 'profile_complete_body_interest';
    return 'profile_complete_body_all';
  }

  static String bodyKeyFromData(Map<String, dynamic>? data) => bodyKey(
        needPhoto: missingPhoto(data),
        needBio: missingBio(data),
        needInterest: missingInterest(data),
      );

  /// Null se o salvamento pode seguir; senão a chave l10n do erro.
  static String? validateForSave({
    required String photoUrl,
    required String about,
    required List<String> interests,
  }) {
    if (!hasPhoto({'photoUrl': photoUrl})) return 'profile_photo_required';
    if (ProfileAbout.clamp(about).isEmpty) return 'profile_bio_required';
    if (UserInterests.sanitize(interests).isEmpty) {
      return 'profile_interest_required';
    }
    return null;
  }

  /// Payload de correção: só os campos que faltavam + `profileComplete`.
  static Map<String, dynamic> repairPayload({
    required bool needPhoto,
    String photoUrl = '',
    required bool needBio,
    String about = '',
    required bool needInterest,
    List<String> interests = const [],
  }) {
    final out = <String, dynamic>{'profileComplete': true};
    if (needPhoto) {
      final url = photoUrl.trim();
      out['photoUrl'] = url;
      out['profilePhotoUrl'] = url;
    }
    if (needBio) {
      out['about'] = ProfileAbout.clamp(about);
    }
    if (needInterest) {
      out['interests'] = UserInterests.sanitize(interests);
    }
    return out;
  }
}

/// Próxima tela depois da idade (AuthGate / Splash).
enum ProfileAccessStep { age, initialCompletion, repairCompletion, ready }

class ProfileAccessGate {
  ProfileAccessGate._();

  static ProfileAccessStep next({
    required bool ageVerified,
    Map<String, dynamic>? data,
  }) {
    if (!ageVerified) return ProfileAccessStep.age;
    if (ProfileCompletion.needsCountrySetup(data) ||
        ProfileCompletion.needsInitialCompletion(data)) {
      return ProfileAccessStep.initialCompletion;
    }
    if (ProfileCompletion.needsRepair(data)) {
      return ProfileAccessStep.repairCompletion;
    }
    return ProfileAccessStep.ready;
  }
}
