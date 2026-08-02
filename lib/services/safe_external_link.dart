import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_texts.dart';
import '../services/message_link_utils.dart';
import '../services/remdy_link_router.dart';

/// Abertura segura de links (Parte 4D).
class SafeExternalLink {
  SafeExternalLink._();

  /// Confirma domínio externo e abre no navegador seguro do aparelho.
  /// Links oficiais Remdy disparam o deep link interno sem aviso externo.
  static Future<void> open(
    BuildContext context, {
    required String url,
    required bool isRemdyInternal,
    required String displayHost,
  }) async {
    final t = AppTexts.current;
    final normalized = MessageLinkUtils.normalizeToHttps(url);
    if (normalized == null) {
      _toast(context, t.get('link_blocked'));
      return;
    }
    final uri = Uri.tryParse(normalized);
    if (uri == null || !MessageLinkUtils.isAllowedHttpsUri(uri)) {
      _toast(context, t.get('link_blocked'));
      return;
    }

    if (isRemdyInternal || MessageLinkUtils.isRemdyHost(uri.host)) {
      final handled = await RemdyLinkRouter.open(uri);
      if (!handled && context.mounted) {
        _toast(context, t.get('link_open_failed'));
      }
      return;
    }

    final host = displayHost.isNotEmpty
        ? displayHost
        : MessageLinkUtils.displayDomain(uri.host);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(t.get('link_leaving_title')),
          content: Text(
            t.get('link_leaving_body').replaceAll('{domain}', host),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(t.get('link_cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(t.get('link_open')),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final ok = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!ok && context.mounted) {
      _toast(context, t.get('link_open_failed'));
    }
  }

  static void _toast(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
