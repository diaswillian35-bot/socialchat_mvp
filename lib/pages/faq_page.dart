import 'package:flutter/material.dart';
import '../l10n/app_texts.dart';


class FaqPage extends StatelessWidget {
  const FaqPage({super.key});


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


  Widget _qa({
    required String q,
    required String a,
  }) {
    return _card(
      child: Theme(
        data: ThemeData(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(top: 8),
          title: Text(
            q,
            style: const TextStyle(
              color: _text,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          iconColor: _muted,
          collapsedIconColor: _muted,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                a,
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
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
          t.get('faq'),
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
                  t.get('frequently_asked_questions'),
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t.get('faq_intro'),
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _qa(
            q: t.get('faq_what_is_remdy_q'),
            a: t.get('faq_what_is_remdy_a'),
          ),
          const SizedBox(height: 10),
          _qa(
            q: t.get('faq_how_premium_works_q'),
            a: t.get('faq_how_premium_works_a'),
          ),
          const SizedBox(height: 10),
          _qa(
            q: t.get('faq_why_cant_talk_some_countries_q'),
            a: t.get('faq_why_cant_talk_some_countries_a'),
          ),
          const SizedBox(height: 10),
          _qa(
            q: t.get('faq_change_language_q'),
            a: t.get('faq_change_language_a'),
          ),
          const SizedBox(height: 10),
          _qa(
            q: t.get('faq_notifications_q'),
            a: t.get('faq_notifications_a'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
