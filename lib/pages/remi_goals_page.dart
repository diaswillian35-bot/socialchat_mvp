
import 'package:flutter/material.dart';
import 'remi_lessons_page.dart';

class RemiGoalsPage extends StatelessWidget {
  final String language;

  const RemiGoalsPage({
    super.key,
    required this.language,
  });

  static const Color _bg = Color(0xFFF8FAFC);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);

  @override
  Widget build(BuildContext context) {
    final goals = [
      _Goal(icon: '✈️', title: 'Travel'),
      _Goal(icon: '☕', title: 'Daily Life'),
      _Goal(icon: '💼', title: 'Work'),
      _Goal(icon: '🧑‍🤝‍🧑', title: 'Friends'),
      _Goal(icon: '🎉', title: 'Events'),
    ];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        surfaceTintColor: _bg,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          language,
          style: const TextStyle(
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
            'What do you want to practice?',
            style: TextStyle(
              color: _text,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose your learning goal and Remi will guide you.',
            style: TextStyle(
              color: _muted,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 20),

          ...goals.map((goal) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
           onTap: () {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => RemiLessonsPage(
        language: language,
        goal: goal.title,
      ),
    ),
  );
},

                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    children: [
                      Text(
                        goal.icon,
                        style: const TextStyle(fontSize: 30),
                      ),
                      const SizedBox(width: 14),

                      Expanded(
                        child: Text(
                          goal.title,
                          style: const TextStyle(
                            color: _text,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),

                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF313A5F),
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

class _Goal {
  final String icon;
  final String title;

  const _Goal({
    required this.icon,
    required this.title,
  });
}
