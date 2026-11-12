import 'package:cloud_functions/cloud_functions.dart';

import '../l10n/app_texts.dart';

/// Texto amigável de um [FirebaseFunctionsException].
/// Prefere a chave estável em `details.i18nKey` / `localizationKey`
/// (o servidor mantém `message` igual para apps antigos).
String? functionsErrorKey(FirebaseFunctionsException error) {
  final details = error.details;
  if (details is Map) {
    for (final field in ['i18nKey', 'localizationKey']) {
      final key = details[field];
      if (key is String && key.trim().isNotEmpty) {
        return key.trim();
      }
    }
  }
  return null;
}

String functionsErrorText(
  Object error, {
  String? fallbackKey,
}) {
  if (error is FirebaseFunctionsException) {
    final key = functionsErrorKey(error) ?? fallbackKey;
    if (key != null) {
      final text = AppTexts.t(key);
      if (text != key && text.trim().isNotEmpty) return text;
    }
    final details = error.details;
    if (details is Map) {
      final localeText = details['localeText'];
      if (localeText is String && localeText.trim().isNotEmpty) {
        return localeText.trim();
      }
    }
    final message = (error.message ?? '').trim();
    if (message.isNotEmpty) return message;
  }
  return AppTexts.t(fallbackKey ?? 'fn_error_generic');
}
