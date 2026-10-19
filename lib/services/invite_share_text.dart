import '../l10n/app_texts.dart';

/// Texto único de convite (página Convidar e "Convidar amigos" das bandeiras).
class InviteShareText {
  InviteShareText._();

  static const String baseUrl = 'https://remdy.app';

  static String link(String inviteCode) {
    final code = inviteCode.trim();
    if (code.isEmpty) return baseUrl;
    return '$baseUrl/invite?ref=${Uri.encodeQueryComponent(code)}';
  }

  /// [template] usa `{link}`; padrão = chave `invite_share_message`.
  static String message(String inviteCode, {String? template}) {
    final text = template ?? AppTexts.current.get('invite_share_message');
    return text.replaceAll('{link}', link(inviteCode));
  }
}
