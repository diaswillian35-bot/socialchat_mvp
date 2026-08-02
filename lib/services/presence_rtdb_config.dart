/// Configuração local da Realtime Database (presença).
///
/// Instância default do projeto `socialchatmvp`, criada em `us-central1`.
class PresenceRtdbConfig {
  PresenceRtdbConfig._();

  /// URL confirmada pela API de gerenciamento do Firebase em 2026-07-25.
  static const String databaseURL =
      'https://socialchatmvp-default-rtdb.firebaseio.com';

  /// Máximo de UIDs com listener de presença em um grupo (custo).
  static const int maxGroupPresenceWatches = 80;

  /// Intervalo mínimo entre writes de `lastSeenAt` no Firestore (transições
  /// importantes podem gravar antes; heartbeats NÃO usam Firestore).
  static const Duration firestoreLastSeenMinInterval = Duration(minutes: 15);
}
