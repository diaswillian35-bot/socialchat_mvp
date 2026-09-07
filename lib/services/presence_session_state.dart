/// Fase da sessão do writer de presença (testável, sem Firebase).
enum PresenceSessionPhase {
  /// Bootstrap / auth ainda não pronto.
  starting,

  /// Conexão RTDB ativa + heartbeat.
  online,

  /// Offline confirmado (background deferido, stop, detached).
  offline,

  /// Sessão ativa sem conexão; tentando restabelecer.
  recovering,

  /// Presença temporariamente indisponível (auth/RTDB); NÃO é offline confirmado.
  unavailable,
}

/// Status lido para a UI (bolinha). Erro ≠ offline.
enum PresenceReadStatus {
  /// ≥1 conexão fresca confirmada pelo snapshot.
  online,

  /// Snapshot confirmou ausência de conexões frescas.
  offline,

  /// Sem snapshot confiável ainda, ou erro de leitura em recuperação.
  unavailable,
}

/// Transições puras do writer (sem I/O).
class PresenceSessionMachine {
  const PresenceSessionMachine._();

  static PresenceSessionPhase afterStartRequested({
    required bool authReady,
    required bool connectionActive,
  }) {
    if (!authReady) return PresenceSessionPhase.starting;
    if (connectionActive) return PresenceSessionPhase.online;
    return PresenceSessionPhase.recovering;
  }

  static PresenceSessionPhase afterGoOnlineResult({
    required bool connectionActive,
  }) {
    return connectionActive
        ? PresenceSessionPhase.online
        : PresenceSessionPhase.recovering;
  }

  static PresenceSessionPhase afterGoOffline() => PresenceSessionPhase.offline;

  static PresenceSessionPhase afterStop() => PresenceSessionPhase.offline;

  static PresenceSessionPhase afterTransientFailure({
    required bool started,
    required bool foreground,
  }) {
    if (!started) return PresenceSessionPhase.unavailable;
    if (!foreground) return PresenceSessionPhase.offline;
    return PresenceSessionPhase.recovering;
  }

  static PresenceSessionPhase afterAuthLost() => PresenceSessionPhase.offline;

  /// Erro de leitura RTDB nunca vira offline confirmado.
  static PresenceReadStatus readStatusOnListenError({
    required PresenceReadStatus? lastConfirmed,
  }) {
    return PresenceReadStatus.unavailable;
  }

  static PresenceReadStatus readStatusFromSnapshot({
    required bool rawOnline,
  }) {
    return rawOnline
        ? PresenceReadStatus.online
        : PresenceReadStatus.offline;
  }

  /// Bolinha: só verde/cinza em estados confirmados.
  static bool? dotIsOnline(PresenceReadStatus status) {
    switch (status) {
      case PresenceReadStatus.online:
        return true;
      case PresenceReadStatus.offline:
        return false;
      case PresenceReadStatus.unavailable:
        return null;
    }
  }
}
