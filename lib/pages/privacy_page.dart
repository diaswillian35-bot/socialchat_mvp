import 'package:flutter/material.dart';
import '../widget/remdy_app.dart';
import '../l10n/app_texts.dart';
import '../services/remdy_launch_access.dart';

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);

  @visibleForTesting
  String get debugPrivacy => _privacy();

  String _privacy() {
    final t = AppTexts.current;
    final purchases = RemdyLaunchAccess.showPremiumUi;
    final showRemi = RemdyLaunchAccess.showRemiUi;
    final purposePremium = purchases
        ? '• ${t.get('privacy_purpose_5')}\n'
        : '';
    final sharingStores = purchases
        ? '• ${t.get('privacy_sharing_10')}\n• ${t.get('privacy_sharing_11')}\n'
        : '';
    final remiContent = showRemi ? '• ${t.get('privacy_content_9')}\n' : '';
    final remiSharing = showRemi ? '• ${t.get('privacy_sharing_12')}\n' : '';
    final sections = <String>[
      '''
${t.get('privacy_section_intro_title')}
${t.get('privacy_section_intro_text')}''',
      '''
${t.get('privacy_section_account_title')}
${t.get('privacy_section_account_intro')}
• ${t.get('privacy_account_1')}
• ${t.get('privacy_account_2')}
• ${t.get('privacy_account_3')}
• ${t.get('privacy_account_4')}
• ${t.get('privacy_account_5')}
• ${t.get('privacy_account_6')}
• ${t.get('privacy_account_7')}
• ${t.get('privacy_account_8')}
• ${t.get('privacy_account_9')}''',
      '''
${t.get('privacy_section_location_title')}
${t.get('privacy_section_location_intro')}
• ${t.get('privacy_location_1')}
• ${t.get('privacy_location_2')}
• ${t.get('privacy_location_3')}
• ${t.get('privacy_location_4')}
${t.get('privacy_location_permission')}''',
      '''
${t.get('privacy_section_content_title')}
${t.get('privacy_section_content_intro')}
• ${t.get('privacy_content_1')}
• ${t.get('privacy_content_2')}
• ${t.get('privacy_content_3')}
• ${t.get('privacy_content_4')}
• ${t.get('privacy_content_5')}
• ${t.get('privacy_content_6')}
• ${t.get('privacy_content_7')}
• ${t.get('privacy_content_8')}
$remiContent''',
      '''
${t.get('privacy_section_technical_title')}
${t.get('privacy_section_technical_intro')}
• ${t.get('privacy_technical_1')}
• ${t.get('privacy_technical_2')}
• ${t.get('privacy_technical_3')}
• ${t.get('privacy_technical_4')}
• ${t.get('privacy_technical_5')}
• ${t.get('privacy_technical_6')}
• ${t.get('privacy_technical_7')}
• ${t.get('privacy_technical_8')}''',
      if (purchases)
        '''
${t.get('privacy_section_purchase_title')}
${t.get('privacy_section_purchase_intro')}
• ${t.get('privacy_purchase_1')}
• ${t.get('privacy_purchase_2')}
• ${t.get('privacy_purchase_3')}
• ${t.get('privacy_purchase_4')}
• ${t.get('privacy_purchase_5')}
${t.get('privacy_purchase_no_card')}''',
      '''
${t.get('privacy_section_login_title')}
${t.get('privacy_section_login_text')}''',
      if (showRemi)
        '''
${t.get('privacy_section_remi_title')}
${t.get('privacy_section_remi_intro')}
• ${t.get('privacy_remi_1')}
• ${t.get('privacy_remi_2')}
• ${t.get('privacy_remi_3')}
• ${t.get('privacy_remi_4')}''',
      '''
${t.get('privacy_section_purposes_title')}
${t.get('privacy_section_purposes_intro')}
• ${t.get('privacy_purpose_1')}
• ${t.get('privacy_purpose_2')}
• ${t.get('privacy_purpose_3')}
• ${t.get('privacy_purpose_4')}
$purposePremium• ${t.get('privacy_purpose_6')}
• ${t.get('privacy_purpose_7')}
• ${t.get('privacy_purpose_8')}
• ${t.get('privacy_purpose_9')}
• ${t.get('privacy_purpose_10')}''',
      '''
${t.get('privacy_section_sharing_title')}
${t.get('privacy_section_sharing_intro')}
• ${t.get('privacy_sharing_1')}
• ${t.get('privacy_sharing_2')}
• ${t.get('privacy_sharing_3')}
• ${t.get('privacy_sharing_4')}
• ${t.get('privacy_sharing_5')}
• ${t.get('privacy_sharing_6')}
• ${t.get('privacy_sharing_7')}
• ${t.get('privacy_sharing_8')}
• ${t.get('privacy_sharing_9')}
$sharingStores$remiSharing
${t.get('privacy_no_sell')}''',
      '''
${t.get('privacy_section_retention_title')}
${t.get('privacy_retention_text')}''',
      '''
${t.get('privacy_section_rights_title')}
${t.get('privacy_rights_intro')}
• ${t.get('privacy_rights_1')}
• ${t.get('privacy_rights_2')}
• ${t.get('privacy_rights_3')}
• ${t.get('privacy_rights_4')}
• ${t.get('privacy_rights_5')}
• ${t.get('privacy_rights_6')}
• ${t.get('privacy_rights_7')}
${t.get('privacy_rights_laws')}''',
      '''
${t.get('privacy_section_children_title')}
${t.get('privacy_children_text')}''',
      '''
${t.get('privacy_section_transfer_title')}
${t.get('privacy_transfer_text')}''',
      '''
${t.get('privacy_section_security_title')}
${t.get('privacy_security_text')}''',
      '''
${t.get('privacy_section_third_party_title')}
${t.get('privacy_third_party_text')}''',
      '''
${t.get('privacy_section_notifications_title')}
${t.get('privacy_notifications_text')}''',
      '''
${t.get('privacy_section_changes_title')}
${t.get('privacy_changes_text')}''',
      '''
${t.get('contact')}
${t.get('privacy_contact_text')}
${t.get('support_email')}''',
    ];

    final numbered = <String>[
      for (var i = 0; i < sections.length; i++) '${i + 1}. ${sections[i].trim()}',
    ];

    return '''
${t.get('privacy_policy')} – Remdy
${t.get('last_update')}: ${t.get('legal_last_update_date')}

${numbered.join('\n\n')}
''';
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;

    return Scaffold(
      backgroundColor: _bg,
      appBar: RemdyAppBar(title: t.get('privacy_policy')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: SelectableText(
            _privacy(),
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: _text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
