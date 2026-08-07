import 'package:flutter/material.dart';

import '../data/remi_lessons_data.dart';
import '../l10n/app_texts.dart';
import '../services/remi_language_contract.dart';
import '../services/remi_ui_labels.dart';
import 'remi_chat_page.dart';

class RemiLessonsPage extends StatelessWidget {
  final String languageCode;
  final String goal;

  const RemiLessonsPage({
    super.key,
    required this.languageCode,
    required this.goal,
  });

  static const Color _bg = Color(0xFFF8FAFC);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _border = Color(0xFFE5E7EB);

  @override
  Widget build(BuildContext context) {
    final code = RemiLanguageContract.normalize(languageCode);
    final lessonsMap =
        remiCatalogFor(code)[goal] ?? const <String, List<String>>{};
    final lessons = lessonsMap.keys.toList();
    final displayLang = RemiLanguageContract.displayName(code);
    final displayGoal = RemiUiLabels.goalTitle(goal);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        surfaceTintColor: _bg,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          '$displayLang • $displayGoal',
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
            AppTexts.t('remi_choose_lesson_headline'),
            style: const TextStyle(
              color: _text,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppTexts.t('remi_choose_lesson_subtitle'),
            style: const TextStyle(
              color: _muted,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 20),
          if (lessons.isEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border),
              ),
              child: Text(
                AppTexts.t('remi_no_lessons'),
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
              ),
            )
          else
            ...lessons.map((lesson) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RemiChatPage(
                          languageCode: code,
                          goal: goal,
                          lesson: lesson,
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
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            color: Color(0xFF313A5F),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            RemiUiLabels.lessonTitle(lesson),
                            style: const TextStyle(
                              color: _text,
                              fontSize: 16,
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
