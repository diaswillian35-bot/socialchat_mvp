import 'package:flutter/material.dart';

import '../features/locais/ui/place_submissions_page.dart';
import '../data/country_names_l10n.dart';
import '../l10n/app_texts.dart';
import '../services/admin_access.dart';

/// "Modo administrador" (somente admin total): escolhe o país cujas pessoas,
/// grupos e eventos aparecem nas listas. Não dá acesso a DMs.
/// Mesmo padrão de folha com ListTile já usado no app (ex.: denúncia).
class AdminModeSheet {
  AdminModeSheet._();

  static const Map<String, String> _fallbackNames = {
    'br': 'Brasil',
    'ca': 'Canadá',
    'pt': 'Portugal',
  };

  static String _lang() {
    final loc = AppTexts.current.locale;
    final lang = loc.languageCode.toLowerCase();
    if (lang != 'pt') return lang;
    return (loc.countryCode ?? '').toUpperCase() == 'PT' ? 'pt-PT' : 'pt-BR';
  }

  static Future<void> show(BuildContext context) {
    final t = AppTexts.current;
    final admin = AdminAccess.instance;
    final selected = admin.viewCountry;
    final lang = _lang();

    Widget option(BuildContext sheetContext, String code, String label) {
      return ListTile(
        title: Text(label),
        trailing: selected == code ? const Icon(Icons.check) : null,
        onTap: () {
          Navigator.pop(sheetContext);
          admin.setViewCountry(code);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t.get('admin_mode_applied'))),
          );
        },
      );
    }

    return showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.admin_panel_settings),
                title: Text(t.get('admin_mode_title')),
                subtitle: Text(t.get('admin_mode_subtitle')),
              ),
              ListTile(
                leading: const Icon(Icons.storefront),
                title: Text(t.get('place_pending_title')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const PlaceSubmissionsPage(adminPending: true),
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              option(sheetContext, '', t.get('admin_mode_my_country')),
              for (final code in AdminAccess.viewableCountries)
                option(
                  sheetContext,
                  code,
                  localizedCountryName(
                    code,
                    _fallbackNames[code] ?? code.toUpperCase(),
                    lang,
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.lock),
                subtitle: Text(t.get('admin_mode_dm_note')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
