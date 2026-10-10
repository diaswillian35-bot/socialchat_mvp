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

  /// Selo, menu “Premium ativo” e cópia de assinatura. Não concede acesso.
  static bool get showPremiumStatus => showPremiumUi;

  /// Convites com recompensa Premium, FAQ de assinatura e deep link `/invite`.
  static bool get showInviteRewards => showPremiumUi;

  /// Texto e botão de cancelar assinatura (exclusão de conta e termos).
  static bool get showSubscriptionManagementCopy => showPremiumUi;

  /// Remi não tem entrada na Home. FAQ e termos não descrevem a função.
  static const bool showRemiUi = false;

  /// Badge visual. `isMaster` / `isPremium` / `premiumUntil` não contornam.
  static bool showsPremiumBadge({required bool premiumActive}) =>
      showPremiumStatus && premiumActive;

  static const Set<String> _hiddenFaqSectionsWithoutPremium = {
    'faq_cat_premium',
    'faq_cat_invites',
  };

  static bool faqSectionVisible(String titleKey) {
    if (titleKey == 'faq_cat_remi') return showRemiUi;
    if (!showPremiumUi && _hiddenFaqSectionsWithoutPremium.contains(titleKey)) {
      return false;
    }
    return true;
  }

  /// Respostas neutras enquanto a compra está oculta. Chaves ausentes no
  /// catálogo caem no original via [AppTexts.get].
  static const Map<String, String> launchFaqAnswerKeys = {
    'faq_what_is_remdy_a': 'faq_what_is_remdy_a_launch',
    'faq_countries_available_a': 'faq_countries_available_a_launch',
    'faq_delete_account_a': 'faq_delete_account_a_launch',
    'faq_message_anyone_a': 'faq_message_anyone_a_launch',
    'faq_world_option_a': 'faq_world_option_a_launch',
    'faq_cant_join_group_a': 'faq_cant_join_group_a_launch',
  };

  static String faqAnswerKey(String key) {
    if (showPremiumUi) return key;
    return launchFaqAnswerKeys[key] ?? key;
  }

  static bool termsSectionVisible(String sectionId) {
    if (sectionId == 'remi') return showRemiUi;
    if (sectionId == 'premium') return showPremiumUi;
    return true;
  }

  /// País oferecido no primeiro cadastro. Conta já travada não passa por aqui.
  static bool isSignupCountryOffered(String? code) {
    final normalized = normalizeCountryCode(code);
    if (normalized.isEmpty) return false;
    if (!isFreeBrazilLaunch) return true;
    return freeCountryCodes.contains(normalized);
  }

  /// Gravação do país inicial. Conta travada só pode manter o país já salvo.
  static bool acceptsHomeCountry({
    required String? code,
    required bool alreadyLocked,
    required String? lockedCode,
  }) {
    if (alreadyLocked) {
      final locked = normalizeCountryCode(lockedCode);
      if (locked.isEmpty) return isSignupCountryOffered(code);
      return normalizeCountryCode(code) == locked;
    }
    return isSignupCountryOffered(code);
  }

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

  /// Mensagem neutra (Guideline 2.1(a)): sem promessa futura.
  static String unavailableMessage([AppTexts? texts]) {
    final t = texts ?? AppTexts.current;
    const key = 'launch_content_unavailable';
    final msg = t.get(key);
    if (msg == key || msg.trim().isEmpty) {
      return 'This content is not available.';
    }
    return msg;
  }

  /// Deep link / rota inválida no lançamento: snackbar, sem CTA morto.
  static Future<void> showUnavailable(BuildContext context) async {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(unavailableMessage()),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  /// Preservado para reativar copy "Em breve" fora deste lançamento.
  /// Não chamar a partir de UI alcançável enquanto [isFreeBrazilLaunch].
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
