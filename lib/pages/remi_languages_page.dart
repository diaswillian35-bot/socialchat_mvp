import 'package:flutter/material.dart';
import 'remi_goals_page.dart';
class RemiLanguagesPage extends StatelessWidget {
  const RemiLanguagesPage({super.key});

  static const Color _bg = Color(0xFFF8FAFC);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);

  @override
  Widget build(BuildContext context) {
    final languages = [
      _RemiLanguage(flag: '🇺🇸', title: 'English', subtitle: 'Practice English'),
      _RemiLanguage(flag: '🇫🇷', title: 'Français', subtitle: 'Pratiquer le français'),
      _RemiLanguage(flag: '🇪🇸', title: 'Español', subtitle: 'Practicar español'),
      _RemiLanguage(flag: '🇧🇷', title: 'Português', subtitle: 'Praticar português'),
    ];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        surfaceTintColor: _bg,
        iconTheme: const IconThemeData(color: _text),
        title: const Text(
          'Choose language',
          style: TextStyle(
            color: _text,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          const Text(
            'What language do you want to practice?',
            style: TextStyle(
              color: _text,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose one language and Remi will guide you with useful real-life phrases.',
            style: TextStyle(
              color: _muted,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 18),

          ...languages.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
             onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => RemiGoalsPage(
        language: item.title,
      ),
    ),
  );
},

                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    children: [
                      Text(
                        item.flag,
                        style: const TextStyle(fontSize: 30),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                color: _text,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.subtitle,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: _remdyBlue,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _RemiLanguage {
  final String flag;
  final String title;
  final String subtitle;

  const _RemiLanguage({
    required this.flag,
    required this.title,
    required this.subtitle,
  });
}
