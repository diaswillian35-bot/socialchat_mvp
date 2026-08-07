import 'package:flutter/material.dart';

import '../data/remi_lessons_data.dart';
import '../l10n/app_texts.dart';
import '../services/remi_language_contract.dart';
import '../services/remi_ui_labels.dart';
import 'remi_lessons_page.dart';

class RemiGoalsPage extends StatelessWidget {
  final String languageCode;

  const RemiGoalsPage({
    super.key,
    required this.languageCode,
  });

  static const Color _bg = Color(0xFFF8FAFC);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);

  static const _goalIcons = <String, String>{
    'Travel': '✈️',
    'Daily Life': '☕',
    'Work': '💼',
    'Friends': '🧑‍🤝‍🧑',
    'Events': '🎉',
  };

  @override
  Widget build(BuildContext context) {
    final code = RemiLanguageContract.normalize(languageCode);
    final catalog = remiCatalogFor(code);
    final goals = remiGoalIds
        .where(catalog.containsKey)
        .map(
          (id) => _Goal(
            id: id,
            icon: _goalIcons[id] ?? '📚',
            title: RemiUiLabels.goalTitle(id),
          ),
        )
        .toList();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        surfaceTintColor: _bg,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          RemiLanguageContract.displayName(code),
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
          Text(
            AppTexts.t('remi_choose_goal_headline'),
            style: const TextStyle(
              color: _text,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppTexts.t('remi_choose_goal_subtitle'),
            style: const TextStyle(
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
                        languageCode: code,
                        goal: goal.id,
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
                      Text(goal.icon, style: const TextStyle(fontSize: 30)),
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
  final String id;
  final String icon;
  final String title;

  const _Goal({
    required this.id,
    required this.icon,
    required this.title,
  });
}
