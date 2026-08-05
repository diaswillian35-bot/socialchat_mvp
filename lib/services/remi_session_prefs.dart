import 'package:shared_preferences/shared_preferences.dart';

import 'remi_language_contract.dart';

class RemiLastSelection {
  const RemiLastSelection({
    required this.languageCode,
    required this.goal,
    required this.lesson,
  });

  final String languageCode;
  final String goal;
  final String lesson;
}

/// Persiste a última seleção de idioma/meta/lição da Remi (por conta).
class RemiSessionPrefs {
  RemiSessionPrefs._();
  static final RemiSessionPrefs instance = RemiSessionPrefs._();

  static String _langKey(String uid) => 'remi_last_language_$uid';
  static String _goalKey(String uid) => 'remi_last_goal_$uid';
  static String _lessonKey(String uid) => 'remi_last_lesson_$uid';

  Future<void> saveSelection({
    required String uid,
    required String languageCode,
    required String goal,
    required String lesson,
  }) async {
    if (uid.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _langKey(uid),
      RemiLanguageContract.normalize(languageCode),
    );
    await prefs.setString(_goalKey(uid), goal.trim());
    await prefs.setString(_lessonKey(uid), lesson.trim());
  }

  Future<RemiLastSelection?> loadSelection(String uid) async {
    if (uid.trim().isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString(_langKey(uid));
    final goal = prefs.getString(_goalKey(uid));
    final lesson = prefs.getString(_lessonKey(uid));
    if (lang == null || goal == null || lesson == null) return null;
    if (lang.trim().isEmpty || goal.trim().isEmpty || lesson.trim().isEmpty) {
      return null;
    }
    return RemiLastSelection(
      languageCode: RemiLanguageContract.normalize(lang),
      goal: goal.trim(),
      lesson: lesson.trim(),
    );
  }
}
