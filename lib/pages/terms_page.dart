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
${t.get('last_update')}: ${t.get('legal_last_update_date')}

${t.get('terms_welcome')}

1. ${t.get('terms_about_remdy')}
${t.get('terms_about_intro')}
• ${t.get('terms_about_item_1')}
• ${t.get('terms_about_item_2')}
• ${t.get('terms_about_item_3')}
• ${t.get('terms_about_item_4')}
• ${t.get('terms_about_item_5')}
• ${t.get('terms_about_item_6')}

${t.get('terms_not_dating_app')}
${t.get('terms_no_intent_promise')}

2. ${t.get('terms_remi_title')}
${t.get('terms_remi_intro')}
• ${t.get('terms_remi_item_1')}
• ${t.get('terms_remi_item_2')}
• ${t.get('terms_remi_item_3')}
• ${t.get('terms_remi_item_4')}
• ${t.get('terms_remi_item_5')}
• ${t.get('terms_remi_item_6')}

3. ${t.get('terms_age_title')}
${t.get('terms_age_text')}

4. ${t.get('terms_rules_title')}
${t.get('terms_rules_intro')}
• ${t.get('terms_rules_item_1')}
• ${t.get('terms_rules_item_2')}
• ${t.get('terms_rules_item_3')}
• ${t.get('terms_rules_item_4')}
• ${t.get('terms_rules_item_5')}
• ${t.get('terms_rules_item_6')}
• ${t.get('terms_rules_item_7')}
• ${t.get('terms_rules_item_8')}
• ${t.get('terms_rules_item_9')}
• ${t.get('terms_rules_item_10')}
• ${t.get('terms_rules_item_11')}

${t.get('terms_rules_consequence')}

5. ${t.get('terms_content_title')}
${t.get('terms_content_intro')}
• ${t.get('terms_content_item_1')}
• ${t.get('terms_content_item_2')}
• ${t.get('terms_content_item_3')}
• ${t.get('terms_content_item_4')}
• ${t.get('terms_content_item_5')}
• ${t.get('terms_content_item_6')}
• ${t.get('terms_content_item_7')}

${t.get('terms_content_rights')}
${t.get('terms_content_moderation')}

6. ${t.get('terms_events_title')}
${t.get('terms_events_intro')}
• ${t.get('terms_events_item_1')}
• ${t.get('terms_events_item_2')}
• ${t.get('terms_events_item_3')}
• ${t.get('terms_events_item_4')}
• ${t.get('terms_events_item_5')}
• ${t.get('terms_events_item_6')}
• ${t.get('terms_events_item_7')}

7. ${t.get('terms_moderation_title')}
${t.get('terms_moderation_intro')}
• ${t.get('terms_moderation_item_1')}
• ${t.get('terms_moderation_item_2')}
• ${t.get('terms_moderation_item_3')}
• ${t.get('terms_moderation_item_4')}
• ${t.get('terms_moderation_item_5')}

8. ${t.get('terms_premium_title')}
${t.get('terms_premium_intro')}
• ${t.get('terms_premium_item_1')}
• ${t.get('terms_premium_item_2')}
• ${t.get('terms_premium_item_3')}
• ${t.get('terms_premium_item_4')}
• ${t.get('terms_premium_item_5')}
• ${t.get('terms_premium_item_6')}
• ${t.get('terms_premium_item_7')}
• ${t.get('terms_premium_item_8')}
• ${t.get('terms_premium_item_9')}

9. ${t.get('terms_account_deletion_title')}
${t.get('terms_account_deletion_intro')}
• ${t.get('terms_account_deletion_item_1')}
• ${t.get('terms_account_deletion_item_2')}
• ${t.get('terms_account_deletion_item_3')}
• ${t.get('terms_account_deletion_item_4')}
• ${t.get('terms_account_deletion_item_5')}
• ${t.get('terms_account_deletion_item_6')}

10. ${t.get('terms_liability_title')}
${t.get('terms_liability_intro')}
• ${t.get('terms_liability_item_1')}
• ${t.get('terms_liability_item_2')}
• ${t.get('terms_liability_item_3')}
• ${t.get('terms_liability_item_4')}
• ${t.get('terms_liability_item_5')}

11. ${t.get('terms_availability_title')}
${t.get('terms_availability_text')}

12. ${t.get('terms_changes_title')}
${t.get('terms_changes_text_1')}
${t.get('terms_changes_text_2')}

13. ${t.get('terms_law_title')}
${t.get('terms_law_text')}

14. ${t.get('contact')}
${t.get('terms_contact_intro')}
${t.get('support_email')}
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
        ],
      ),
    );
  }
}
