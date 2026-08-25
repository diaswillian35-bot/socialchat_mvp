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
  ///
  /// Intervalo do keep-alive de presença em foreground.
  static const Duration connectionHeartbeatInterval = Duration(seconds: 45);

  /// Após deploy de Rules + CF que leem `presence/{uid}/heartbeat`,
  /// ligar para deixar de renovar o timestamp em `connections/*`.
  /// Enquanto `false`, o keep-alive canônico continua no path legado
  /// (compatível com Rules publicadas); o path novo é no máx. 1 probe/sessão.
  static const bool separateHeartbeatIsPrimary = false;

  /// Quando `true` (remote config / pós-GO), reabilita probe do path novo
  /// mesmo após denial nesta sessão.
  static bool separateHeartbeatBackendReady = false;

  /// Conexão com timestamp mais velho que isto é tratada como morta (cliente
  /// e Cloud Function). Deve ser > 2× [connectionHeartbeatInterval].
  static const Duration connectionStaleAfter = Duration(minutes: 3);

  /// UI offline hold (ver [PresenceStabilityGate]) — não muda writes RTDB.
  /// 20s cobre blips de `onDisconnect`/wireless sem atrasar muito o offline real
  /// (lifecycle já adia goOffline em 60s).
  static const Duration uiOfflineHold = Duration(seconds: 20);

  /// Public display counter publish interval (server coalesce target).
  static const Duration displayCounterPublishInterval = Duration(seconds: 20);
}
