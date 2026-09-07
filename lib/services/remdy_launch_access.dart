import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_texts.dart';

/// Configuração central do lançamento gratuito (Brasil + Canadá).
///
/// Ativo **somente no iOS**. Android permanece com o fluxo Premium atual.
/// Para reativar compras/internacionais no iOS: `freeBrazilLaunchEnabled = false`.
class RemdyLaunchAccess {
  RemdyLaunchAccess._();

  /// Master switch — preservar código de compras; só desligar este flag.
  static const bool freeBrazilLaunchEnabled = true;

  /// Países abertos neste lançamento (gratuitos, isolados entre si).
  static const Set<String> freeCountryCodes = {'br', 'ca'};

  /// Alias legado (Brasil). Preferir [freeCountryCodes] / [isCountryOpen].
  static const String freeCountryCode = 'br';

  /// iOS (+ testes na VM). Android permanece no fluxo Premium atual.
  static bool get isFreeBrazilLaunch {
    if (!freeBrazilLaunchEnabled) return false;
    if (kIsWeb) return false;
    try {
      if (Platform.isAndroid) return false;
      return true;
    } catch (_) {
      return true;
    }
  }

  /// RevenueCat / UI de assinatura.
  static bool get purchasesEnabled => !isFreeBrazilLaunch;

  static bool get showPremiumUi => !isFreeBrazilLaunch;

  static String normalizeCountryCode(String? raw) =>
      (raw ?? '').trim().toLowerCase();

  /// País (ou "world") pode ser aberto neste lançamento (BR e CA).
  static bool isCountryOpen(String? countryCode) {
    if (!isFreeBrazilLaunch) return true;
    final code = normalizeCountryCode(countryCode);
    if (code.isEmpty) return false;
    if (code == 'world' || code == 'mundo') return false;
    return freeCountryCodes.contains(code);
  }

  static bool isWorldOpen() {
    if (!isFreeBrazilLaunch) return true;
    return false;
  }

  /// Conteúdo (pessoas/grupos/chats/eventos) só no próprio país de casa,
  /// e somente se esse país estiver aberto no lançamento.
  static bool canAccessCountryContent({
    required String? userHomeCountryCode,
    required String? targetCountryCode,
  }) {
    final home = normalizeCountryCode(userHomeCountryCode);
    final target = normalizeCountryCode(targetCountryCode);
    if (home.isEmpty || target.isEmpty) return false;
    if (!isCountryOpen(home) || !isCountryOpen(target)) return false;
    return home == target;
  }

  /// Grupos no lançamento gratuito: mesmo país aberto apenas.
  /// `isPremium` / `isMaster` / `premiumUntil` / grupo `world` **não**
  /// ignoram este bloqueio. Fora do lançamento, retorna true (legado Android).
  static bool canAccessGroupCountry({
    required String? userHomeCountryCode,
    required String? groupCountryCode,
  }) {
    if (!isFreeBrazilLaunch) return true;
    return canAccessCountryContent(
      userHomeCountryCode: userHomeCountryCode,
      targetCountryCode: groupCountryCode,
    );
  }

  /// Selo "Em breve" na Home: depende do país canônico do perfil.
  /// BR vê CA/PT/mundo como Em breve; CA vê BR/PT/mundo como Em breve.
  static bool showsComingSoonOnHome({
    required String? userHomeCountryCode,
    required String? targetCountryCode,
  }) {
    if (!isFreeBrazilLaunch) return false;
    return !canAccessCountryContent(
      userHomeCountryCode: userHomeCountryCode,
      targetCountryCode: targetCountryCode,
    );
  }

  /// DM: mesmo país aberto (BR↔BR ou CA↔CA). Nunca BR↔CA.
  static bool canChatBetweenCountries({
    required String senderCountryCode,
    required String recipientCountryCode,
    required bool premiumActive,
  }) {
    if (!isFreeBrazilLaunch) {
      if (premiumActive) return true;
      final a = normalizeCountryCode(senderCountryCode);
      final b = normalizeCountryCode(recipientCountryCode);
      return a.isNotEmpty && a == b;
    }
    return canAccessCountryContent(
      userHomeCountryCode: senderCountryCode,
      targetCountryCode: recipientCountryCode,
    );
  }

  static String comingSoonTitle([AppTexts? texts]) {
    final t = texts ?? AppTexts.current;
    final key = 'country_coming_soon_title';
    final msg = t.get(key);
    if (msg == key || msg.trim().isEmpty) {
      return 'Em breve neste país 🌍';
    }
    return msg;
  }

  static String comingSoonMessage([AppTexts? texts]) {
    final t = texts ?? AppTexts.current;
    final key = 'country_coming_soon';
    final msg = t.get(key);
    if (msg == key || msg.trim().isEmpty) {
      return 'Estamos preparando a Remdy para conectar pessoas nessa região. Avisaremos quando estiver disponível.';
    }
    return msg;
  }

  static String comingSoonBadgeLabel([AppTexts? texts]) {
    final t = texts ?? AppTexts.current;
    final key = 'coming_soon_short';
    final msg = t.get(key);
    if (msg == key || msg.trim().isEmpty) return 'Em breve';
    return msg;
  }

  /// Snack / dialog único para país indisponível (sem CTA Premium).
  static Future<void> showComingSoon(BuildContext context) async {
    final title = comingSoonTitle();
    final message = comingSoonMessage();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF313A5F),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      AppTexts.current.get('close'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
