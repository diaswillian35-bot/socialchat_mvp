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

  /// Renova o timestamp da conexão RTDB enquanto o app está em foreground.
  /// Sem isso, nós órfãos (onDisconnect falho) nunca envelhecem de forma
  /// distinguível de uma sessão ativa longa.
  static const Duration connectionHeartbeatInterval = Duration(seconds: 45);

  /// Conexão com timestamp mais velho que isto é tratada como morta (cliente
  /// e Cloud Function). Deve ser > 2× [connectionHeartbeatInterval].
  static const Duration connectionStaleAfter = Duration(minutes: 3);
}
