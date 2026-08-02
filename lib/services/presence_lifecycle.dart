/// Decisões puras de lifecycle de presença (testáveis sem Firebase).
enum PresenceResumeAction {
  /// Conexão ainda válida — só cancela timer; não recria path.
  keepAlive,

  /// Precisa estabelecer/reestabelecer conexão.
  reestablish,
}

enum PresenceGoOnlineAction {
  keepExisting,
  createNew,
}

class PresenceLifecycle {
  PresenceLifecycle._();

  static PresenceResumeAction decideResume({
    required bool connectionActive,
    required bool hasConnectionRef,
  }) {
    if (connectionActive && hasConnectionRef) {
      return PresenceResumeAction.keepAlive;
    }
    return PresenceResumeAction.reestablish;
  }

  static PresenceGoOnlineAction decideGoOnline({
    required bool connectionActive,
    required bool hasConnectionRef,
    required bool forceNew,
  }) {
    if (forceNew) return PresenceGoOnlineAction.createNew;
    if (connectionActive && hasConnectionRef) {
      return PresenceGoOnlineAction.keepExisting;
    }
    return PresenceGoOnlineAction.createNew;
  }

  /// Transições curtas não devem provocar enter/leave no contador.
  static bool shouldBlinkCountersOnResume({
    required PresenceResumeAction action,
  }) {
    return action != PresenceResumeAction.keepAlive;
  }
}
