import 'package:flutter/material.dart';
import '../widget/remdy_app.dart';
import '../l10n/app_texts.dart';


class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});


  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);


  String _privacy() {
    final t = AppTexts.current;


    return '''
${t.get('privacy_policy')} – Remdy
${t.get('last_update')}: 2026




1. ${t.get('privacy_section_1')}
${t.get('privacy_collect_intro')}
• ${t.get('privacy_collect_1')}
• ${t.get('privacy_collect_2')}
• ${t.get('privacy_collect_3')}
• ${t.get('privacy_collect_4')}
• ${t.get('privacy_collect_5')}




2. ${t.get('privacy_section_2')}
${t.get('privacy_use_intro')}
• ${t.get('privacy_use_1')}
• ${t.get('privacy_use_2')}
• ${t.get('privacy_use_3')}
• ${t.get('privacy_use_4')}




3. ${t.get('privacy_section_3')}
${t.get('privacy_share_text')}




4. ${t.get('security')}
${t.get('privacy_security_text')}




5. ${t.get('privacy_section_5')}
${t.get('privacy_user_content_text')}




6. ${t.get('privacy_section_6')}
${t.get('privacy_changes_text')}




7. ${t.get('contact')}
${t.get('privacy_contact_text')}
contact@remdy.app
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
          child: Text(
            _privacy(),
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: _text,
            ),
          ),
        ),
      ),
    );
  }
}
