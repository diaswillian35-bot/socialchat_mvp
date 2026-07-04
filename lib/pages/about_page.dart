import 'package:flutter/material.dart';
import '../l10n/app_texts.dart';


class AboutPage extends StatelessWidget {
  const AboutPage({super.key});


  static const Color _bg = Colors.white;
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);


  static const LinearGradient _primaryGradient = LinearGradient(
    colors: [
      Color(0xFF313A5F),
      Color(0xFF264E9A),
    ],
  );


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


  String _aboutText() {
    final t = AppTexts.current;


    return '${t.get('about_remdy_paragraph_1')}\n\n'
        '${t.get('about_remdy_paragraph_2')}\n\n'
        '${t.get('about_remdy_our_idea_title')}\n'
        '${t.get('about_remdy_paragraph_3')}\n\n'
        '${t.get('about_remdy_paragraph_4')}\n\n'
        '${t.get('about_remdy_paragraph_5')}\n'
        '• ${t.get('about_remdy_bullet_1')}\n'
        '• ${t.get('about_remdy_bullet_2')}\n'
        '• ${t.get('about_remdy_bullet_3')}\n'
        '• ${t.get('about_remdy_bullet_4')}\n\n'
        '${t.get('about_remdy_paragraph_6')}\n\n'
        '${t.get('about_remdy_global_title')}\n'
        '${t.get('about_remdy_paragraph_7')}\n\n'
        '${t.get('about_remdy_safety_title')}\n'
        '${t.get('about_remdy_paragraph_8')}\n\n'
        '${t.get('about_remdy_getting_started_title')}\n'
        '${t.get('about_remdy_paragraph_9')}\n\n'
        '${t.get('about_remdy_thanks_title')}\n'
        '${t.get('about_remdy_paragraph_10')}';
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
        title: Text(
          t.get('about'),
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
                  t.get('about_remdy_title'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: _text,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _aboutText(),
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: _muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
