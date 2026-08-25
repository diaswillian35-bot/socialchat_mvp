import 'presence_rtdb_config.dart';

/// Client-side online/offline hysteresis for presence UI.
///
/// RTDB `onDisconnect` removes `connections/{id}` immediately on brief wireless
/// blips, which made the green dot flicker while the app stayed in foreground.
/// This gate does **not** invent online locally from a closed socket — it only
/// delays emitting **offline** after a previously-online signal, and cancels
/// that delay if an online snapshot returns.
class PresenceStabilityGate {
  PresenceStabilityGate({
    this.offlineHold = PresenceRtdbConfig.uiOfflineHold,
  });

  /// Hold last-online long enough to cover typical RTDB reconnect blips
  /// without delaying real background offline too long (lifecycle already
  /// defers goOffline by 60s). Zero extra RTDB writes/reads.
  static const Duration defaultOfflineHold = PresenceRtdbConfig.uiOfflineHold;

  final Duration offlineHold;

  bool? _emitted;
  bool? _raw;
  DateTime? _offlineSince;

  bool? get lastEmitted => _emitted;

  /// Returns the value to emit, or null if nothing changed vs [lastEmitted].
  bool? consider(bool rawOnline, DateTime now) {
    _raw = rawOnline;
    if (rawOnline) {
      _offlineSince = null;
      if (_emitted == true) return null;
      _emitted = true;
      return true;
    }

    // Going / staying offline.
    if (_emitted != true) {
      // Never confirmed online (or already offline) → emit offline once.
      if (_emitted == false) return null;
      _emitted = false;
      return false;
    }

    _offlineSince ??= now;
    final held = now.difference(_offlineSince!);
    if (held < offlineHold) {
      // Keep showing online during hold.
      return null;
    }
    _emitted = false;
    _offlineSince = null;
    return false;
  }

  /// For timer-driven flush of a pending offline hold.
  bool? flush(DateTime now) {
    if (_raw == true) return null;
    if (_emitted != true || _offlineSince == null) return null;
    if (now.difference(_offlineSince!) < offlineHold) return null;
    _emitted = false;
    _offlineSince = null;
    return false;
  }

  Duration? pendingOfflineRemaining(DateTime now) {
    if (_emitted != true || _offlineSince == null || _raw == true) return null;
    final left = offlineHold - now.difference(_offlineSince!);
    return left.isNegative ? Duration.zero : left;
  }

  void reset() {
    _emitted = null;
    _raw = null;
    _offlineSince = null;
  }
}
