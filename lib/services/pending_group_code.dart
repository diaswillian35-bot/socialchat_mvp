import 'package:shared_preferences/shared_preferences.dart';

import 'remdy_deep_link_parser.dart';

/// Leitura do Play Install Referrer. `definitive` falso pede nova tentativa
/// no próximo arranque (timeout / Play Store indisponível).
class AndroidReferrerRead {
  const AndroidReferrerRead({
    this.referrer,
    this.installBeginTimestampSeconds,
    this.definitive = true,
  });

  final String? referrer;

  /// Segundos desde epoch. Prefere o relógio do servidor do Play.
  final int? installBeginTimestampSeconds;

  final bool definitive;
}

/// Regras puras do código de grupo pendente (`pending_group_code`).
///
/// O código entra por referrer (Android), área de transferência (iOS),
/// deep link ou pelo campo "Tenho um código de convite". Só sai quando a
/// prévia do grupo continua na tela depois do primeiro frame — login, e-mail,
/// 18+ e foto não apagam a chave.
class PendingGroupCodeLogic {
  PendingGroupCodeLogic._();

  static const pendingKey = 'pending_group_code';
  static const androidCheckedKey = 'android_install_referrer_checked';
  static const iosCheckedKey = 'ios_invite_clipboard_checked';

  /// Mesma chave gravada por AppReviewPrompt.recordLaunch no primeiro uso.
  static const firstLaunchKey = 'review_first_launch_ms';

  static const iosClipboardPrefix = 'REMDY-';

  /// Primeira sessão do app (a chave de review acabou de ser criada).
  /// Atualização de quem já usou o app fica de fora — sem aviso de colar.
  static const firstSessionWindowMs = 15 * 60 * 1000;

  /// Instalação pela Play Store recente o bastante para aplicar o referrer.
  /// Uma atualização de uma instalação antiga não reabre o convite.
  static const recentInstallWindowSeconds = 48 * 60 * 60;

  static bool isFirstAppSession({
    required int? firstLaunchMs,
    required int nowMs,
    int windowMs = firstSessionWindowMs,
  }) {
    if (firstLaunchMs == null) return true;
    final age = nowMs - firstLaunchMs;
    if (age < -60 * 1000) return true;
    return age <= windowMs;
  }

  static bool isRecentPlayInstall({
    required int? installBeginTimestampSeconds,
    required int nowSeconds,
    int windowSeconds = recentInstallWindowSeconds,
  }) {
    final stamp = _asEpochSeconds(installBeginTimestampSeconds);
    if (stamp == null || stamp <= 0) return false;
    final age = nowSeconds - stamp;
    if (age < -5 * 60) return true;
    return age <= windowSeconds;
  }

  /// O Play manda segundos. Um valor em milissegundos ainda entra na conta.
  static int? _asEpochSeconds(int? stamp) {
    if (stamp == null || stamp <= 0) return stamp;
    if (stamp > 100000000000) return stamp ~/ 1000;
    return stamp;
  }

  /// `invite={code}` (ou o link) no referrer da Play Store.
  /// O site manda `referrer=invite%3D{code}`.
  static String? codeFromInstallReferrer(String? referrer) {
    final decoded = _decodeUpToTwice(referrer);
    if (decoded.isEmpty) return null;
    final invite = _queryValue(decoded, 'invite');
    if (invite == null || invite.trim().isEmpty) return null;
    return codeFromUserInput(_decodeUpToTwice(invite));
  }

  /// Uma leitura no iOS: só o link `remdy.app/g/{code}` ou o prefixo `REMDY-`.
  /// Código solto (senha, outra coisa copiada) não entra.
  static String? codeFromIosClipboard(String? text) {
    final raw = (text ?? '').trim();
    if (raw.isEmpty) return null;
    if (raw.toUpperCase().startsWith(iosClipboardPrefix)) {
      return codeFromUserInput(raw);
    }
    if (!_looksLikeGroupLink(raw)) return null;
    final uri = _asInviteUri(raw);
    if (uri == null) return null;
    final parsed = RemdyDeepLinkParser.parse(uri);
    if (!parsed.opensGroupPreview) return null;
    return parsed.groupCode;
  }

  /// Campo manual: código puro, link (`https`, `remdy://`, `intent://`)
  /// ou prefixo `REMDY-`.
  static String? codeFromUserInput(String? raw) {
    var text = (raw ?? '').trim();
    if (text.isEmpty) return null;
    if (text.toUpperCase().startsWith(iosClipboardPrefix)) {
      text = text.substring(iosClipboardPrefix.length).trim();
      if (text.isEmpty) return null;
    }
    final uri = _asInviteUri(text);
    if (uri != null) {
      final parsed = RemdyDeepLinkParser.parse(uri);
      if (parsed.opensGroupPreview) return parsed.groupCode;
      return null;
    }
    final code = RemdyDeepLinkParser.normalizeGroupCode(text);
    if (!RemdyDeepLinkParser.isValidGroupCode(code)) return null;
    return code;
  }

  /// Referrer e área de transferência não substituem um código já gravado.
  static String? installCodeToWrite({
    required String? extracted,
    required String? alreadyPending,
  }) {
    if (extracted == null || !RemdyDeepLinkParser.isValidGroupCode(extracted)) {
      return null;
    }
    final existing = RemdyDeepLinkParser.normalizeGroupCode(alreadyPending);
    if (RemdyDeepLinkParser.isValidGroupCode(existing)) return null;
    return RemdyDeepLinkParser.normalizeGroupCode(extracted);
  }

  /// Mesmo portão da Home: sem sessão, com e-mail pendente, sem 18+ ou
  /// com foto obrigatória em falta, o código continua guardado.
  static bool mayOpenPendingGroup({
    required bool hasUser,
    required bool needsEmailVerification,
    required bool ageVerified,
    required bool needsProfilePhoto,
  }) {
    if (!hasUser) return false;
    if (needsEmailVerification) return false;
    if (!ageVerified) return false;
    if (needsProfilePhoto) return false;
    return true;
  }

  /// A chave só sai quando a prévia segue montada depois do frame.
  /// `pushAndRemoveUntil` do cadastro descarta a rota antes disso.
  static bool shouldReleasePendingCode({required bool pageStillMounted}) {
    return pageStillMounted;
  }

  static bool _looksLikeGroupLink(String text) {
    final lower = text.toLowerCase();
    return lower.contains('remdy.app/g/') || lower.startsWith('remdy://g/');
  }

  static Uri? _asInviteUri(String text) {
    final trimmed = text.trim();
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('remdy://') ||
        lower.startsWith('intent://') ||
        lower.startsWith('https://') ||
        lower.startsWith('http://')) {
      return Uri.tryParse(trimmed);
    }
    if (lower.startsWith('remdy.app/') || lower.startsWith('www.remdy.app/')) {
      return Uri.tryParse('https://$trimmed');
    }
    return null;
  }

  static String? _queryValue(String raw, String key) {
    try {
      return Uri.splitQueryString(raw)[key];
    } catch (_) {
      return null;
    }
  }

  static String _decodeUpToTwice(String? raw) {
    var value = (raw ?? '').trim();
    for (var i = 0; i < 2; i++) {
      if (!value.contains('%')) break;
      try {
        final next = Uri.decodeFull(value);
        if (next == value) break;
        value = next;
      } catch (_) {
        break;
      }
    }
    return value;
  }
}

class PendingGroupCodeStore {
  PendingGroupCodeStore._();

  static Future<void> save(String code) async {
    final normalized = RemdyDeepLinkParser.normalizeGroupCode(code);
    if (!RemdyDeepLinkParser.isValidGroupCode(normalized)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PendingGroupCodeLogic.pendingKey, normalized);
  }

  /// Remove a chave só se ela ainda for este código e a prévia ficou na tela.
  static Future<void> releaseIfMatches(
    String code, {
    bool pageStillMounted = true,
  }) async {
    if (!PendingGroupCodeLogic.shouldReleasePendingCode(
      pageStillMounted: pageStillMounted,
    )) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final current = RemdyDeepLinkParser.normalizeGroupCode(
      prefs.getString(PendingGroupCodeLogic.pendingKey),
    );
    if (current != RemdyDeepLinkParser.normalizeGroupCode(code)) return;
    await prefs.remove(PendingGroupCodeLogic.pendingKey);
  }
}
