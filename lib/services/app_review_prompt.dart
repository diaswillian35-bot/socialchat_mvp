import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Armazenamento mínimo (SharedPreferences no app; mapa em memória nos testes).
abstract class ReviewPromptStore {
  Future<int?> getInt(String key);
  Future<void> setInt(String key, int value);
}

class SharedPrefsReviewStore implements ReviewPromptStore {
  @override
  Future<int?> getInt(String key) async =>
      (await SharedPreferences.getInstance()).getInt(key);

  @override
  Future<void> setInt(String key, int value) async =>
      (await SharedPreferences.getInstance()).setInt(key, value);
}

class MemoryReviewStore implements ReviewPromptStore {
  final Map<String, int> values = {};
  @override
  Future<int?> getInt(String key) async => values[key];
  @override
  Future<void> setInt(String key, int value) async => values[key] = value;
}

/// Pedido de avaliação OFICIAL (in_app_review: Play In-App Review no
/// Android, SKStoreReviewController no iOS). Sem pré-filtro "gostou?".
///
/// Regras: só depois de um momento positivo (3 mensagens enviadas no total,
/// ou um evento criado); nunca no 1º dia desde o 1º uso; no máximo 1 vez a
/// cada 90 dias. O sistema ainda decide se mostra (cota própria do SO).
class AppReviewPrompt {
  AppReviewPrompt({
    ReviewPromptStore? store,
    DateTime Function()? clock,
    Future<bool> Function()? isAvailable,
    Future<void> Function()? request,
  })  : _store = store ?? SharedPrefsReviewStore(),
        _clock = clock ?? DateTime.now,
        _isAvailable = isAvailable ?? InAppReview.instance.isAvailable,
        _request = request ?? InAppReview.instance.requestReview;

  static AppReviewPrompt instance = AppReviewPrompt();

  static const String kFirstLaunch = 'review_first_launch_ms';
  static const String kLastPrompt = 'review_last_prompt_ms';
  static const String kMessages = 'review_messages_sent';
  static const int messagesNeeded = 3;
  static const Duration minAge = Duration(days: 1);
  static const Duration cooldown = Duration(days: 90);

  final ReviewPromptStore _store;
  final DateTime Function() _clock;
  final Future<bool> Function() _isAvailable;
  final Future<void> Function() _request;

  /// Grava a data do 1º uso (chamar na abertura do app).
  Future<void> recordLaunch() async {
    if (await _store.getInt(kFirstLaunch) == null) {
      await _store.setInt(kFirstLaunch, _clock().millisecondsSinceEpoch);
    }
  }

  /// Regra pura de tempo (testável).
  Future<bool> timeAllows() async {
    final now = _clock().millisecondsSinceEpoch;
    final first = await _store.getInt(kFirstLaunch);
    if (first == null) {
      await _store.setInt(kFirstLaunch, now);
      return false;
    }
    if (now - first < minAge.inMilliseconds) return false;
    final last = await _store.getInt(kLastPrompt);
    if (last != null && now - last < cooldown.inMilliseconds) return false;
    return true;
  }

  /// Mensagem enviada com sucesso (DM, grupo). Pede a partir da 3ª no total.
  Future<bool> onMessageSent() async {
    final n = (await _store.getInt(kMessages) ?? 0) + 1;
    await _store.setInt(kMessages, n);
    if (n < messagesNeeded) return false;
    return _maybeRequest();
  }

  /// Evento criado com sucesso.
  Future<bool> onEventCreated() => _maybeRequest();

  Future<bool> _maybeRequest() async {
    try {
      if (!await timeAllows()) return false;
      if (!await _isAvailable()) return false;
      await _store.setInt(kLastPrompt, _clock().millisecondsSinceEpoch);
      await _request();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[AppReviewPrompt] $e');
      return false;
    }
  }
}
