import '../l10n/app_texts.dart';
import 'remi_language_contract.dart';

/// Labels de UI da Remi (idioma do app) — separados do idioma-alvo de prática.
class RemiUiLabels {
  RemiUiLabels._();

  static String goalTitle(String goalId) {
    switch (goalId) {
      case 'Travel':
        return AppTexts.t('remi_chip_travel');
      case 'Daily Life':
        return AppTexts.t('remi_chip_daily_life');
      case 'Work':
        return AppTexts.t('remi_chip_work');
      case 'Friends':
        return AppTexts.t('remi_goal_friends');
      case 'Events':
        return AppTexts.t('remi_goal_events');
      default:
        return goalId;
    }
  }

  static String lessonTitle(String lessonId) {
    switch (lessonId) {
      case 'Small Talk':
        return AppTexts.t('lesson_small_talk');
      case 'Coffee Shop':
        return AppTexts.t('lesson_coffee_shop');
      case 'Job Interview':
        return AppTexts.t('lesson_job_interview');
      case 'Introductions':
        return AppTexts.t('lesson_introductions');
      case 'Meeting People':
        return AppTexts.t('lesson_meeting_people');
      case 'Daily Life':
        return AppTexts.t('lesson_daily_life');
      case 'Airport':
        return AppTexts.t('lesson_airport');
      case 'Hotel':
        return AppTexts.t('lesson_hotel');
      case 'Restaurant':
        return AppTexts.t('lesson_restaurant');
      case 'Directions':
        return AppTexts.t('lesson_directions');
      case 'Shopping':
        return AppTexts.t('lesson_shopping');
      case 'Making Friends':
        return AppTexts.t('lesson_making_friends');
      case 'Social Events':
        return AppTexts.t('lesson_social_events');
      default:
        return lessonId;
    }
  }

  static String practiceLanguageTitle(String code) {
    return RemiLanguageContract.displayName(code);
  }
}
