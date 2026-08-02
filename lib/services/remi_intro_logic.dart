/// Lógica pura da apresentação da Remi (testável sem Firebase/UI).
class RemiIntroLogic {
  RemiIntroLogic._();

  /// Versão atual da apresentação. Futuro: incrementar para 2 reexibe só quem tem < 2.
  static const int currentVersion = 1;

  static String localVersionKey(String uid) => 'remi_intro_version_$uid';

  static String localPendingSyncKey(String uid) => 'remi_intro_pending_sync_$uid';

  /// Valor inválido/ausente ⇒ ainda não visto.
  static int? parseIntroVersion(dynamic raw) {
    if (raw == null) return null;
    if (raw is int) {
      if (raw < 1) return null;
      return raw;
    }
    if (raw is num) {
      final v = raw.toInt();
      if (v < 1) return null;
      return v;
    }
    if (raw is String) {
      final v = int.tryParse(raw.trim());
      if (v == null || v < 1) return null;
      return v;
    }
    return null;
  }

  /// `true` se o usuário já concluiu uma versão >= [requiredVersion].
  static bool hasSeenIntro(
    dynamic remiIntroVersion, {
    int requiredVersion = currentVersion,
  }) {
    final v = parseIntroVersion(remiIntroVersion);
    if (v == null) return false;
    return v >= requiredVersion;
  }

  /// Merge idempotente: nunca reduz a versão já vista.
  static int nextStoredVersion(int? currentStored, {int target = currentVersion}) {
    final base = currentStored ?? 0;
    return base > target ? base : target;
  }
}
