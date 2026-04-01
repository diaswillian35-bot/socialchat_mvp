import 'package:flutter/material.dart';
import '../l10n/app_texts.dart';


class TermsPage extends StatelessWidget {
  const TermsPage({super.key});


  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);


  String _terms() {
    final t = AppTexts.current;
    return '''
${t.get('terms_of_use')} — Remdy
${t.get('last_update')}: 2026


${t.get('terms_welcome')}


1. ${t.get('terms_about_remdy')}
${t.get('terms_about_intro')}
• ${t.get('terms_about_item_1')}
• ${t.get('terms_about_item_2')}
• ${t.get('terms_about_item_3')}
• ${t.get('terms_about_item_4')}


${t.get('terms_not_dating_app')}
${t.get('terms_no_bots')}


2. ${t.get('terms_rules_title')}
${t.get('terms_rules_intro')}
• ${t.get('terms_rules_item_1')}
• ${t.get('terms_rules_item_2')}
• ${t.get('terms_rules_item_3')}
• ${t.get('terms_rules_item_4')}
• ${t.get('terms_rules_item_5')}


${t.get('terms_rules_consequence')}


3. ${t.get('terms_photos_profile_title')}
${t.get('terms_photos_intro')}
• ${t.get('terms_photos_item_1')}
• ${t.get('terms_photos_item_2')}
• ${t.get('terms_photos_item_3')}


4. ${t.get('privacy')}
${t.get('terms_privacy_intro')}
• ${t.get('terms_privacy_item_1')}
• ${t.get('terms_privacy_item_2')}
• ${t.get('terms_privacy_item_3')}
• ${t.get('terms_privacy_item_4')}


${t.get('terms_privacy_usage')}
${t.get('terms_privacy_no_sell')}


5. ${t.get('security')}
${t.get('terms_security_intro')}
• ${t.get('terms_security_item_1')}
• ${t.get('terms_security_item_2')}


6. ${t.get('premium')}
${t.get('terms_premium_intro')}
• ${t.get('terms_premium_item_1')}
• ${t.get('terms_premium_item_2')}


7. ${t.get('terms_availability_title')}
${t.get('terms_availability_text')}


8. ${t.get('terms_account_closure_title')}
${t.get('terms_account_closure_user')}
${t.get('terms_account_closure_remdy')}


9. ${t.get('terms_changes_title')}
${t.get('terms_changes_text_1')}
${t.get('terms_changes_text_2')}


10. ${t.get('contact')}
${t.get('terms_contact_intro')}
contact@remdy.app
''';
  }


  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: child,
    );
  }


  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;


    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: true,
        title: Text(
          t.get('terms'),
          style: const TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.get('terms_of_use'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: _text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t.get('terms_intro_short'),
                  style: const TextStyle(
                    fontSize: 13,
                    color: _muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: SelectableText(
              _terms(),
              style: const TextStyle(
                fontSize: 14,
                height: 1.4,
                color: _text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}
