/// Campo "Sobre mim" (users.about / publicUsers.about).
class ProfileAbout {
  ProfileAbout._();

  static const int maxLength = 300;

  static String clamp(String text) {
    final s = text.trim();
    return s.length <= maxLength ? s : s.substring(0, maxLength);
  }
}
