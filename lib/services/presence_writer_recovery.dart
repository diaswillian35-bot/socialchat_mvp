/// Pure recovery policy when [PresenceService] is started in foreground but
/// has no active RTDB connection (e.g. transient auth/RTDB failure on first
/// `_goOnline`).
class PresenceWriterRecovery {
  PresenceWriterRecovery({
    this.minInterval = const Duration(seconds: 5),
    this.maxInterval = const Duration(seconds: 60),
    this.maxBackoffExponent = 5,
  });

  final Duration minInterval;
  final Duration maxInterval;
  final int maxBackoffExponent;

  int _consecutiveFailures = 0;
  DateTime? _lastAttemptAt;

  int get consecutiveFailures => _consecutiveFailures;

  /// Whether a foreground started session without a live connection should retry.
  bool shouldRecover({
    required bool started,
    required bool foreground,
    required bool connectionActive,
    required bool hasConnectionRef,
  }) {
    if (!started || !foreground) return false;
    return !connectionActive || !hasConnectionRef;
  }

  /// Backoff after failures: 5s → 10s → 20s → 40s → 60s (capped).
  Duration backoffAfterFailures(int failures) {
    if (failures <= 0) return Duration.zero;
    final exp = failures > maxBackoffExponent ? maxBackoffExponent : failures;
    final mult = 1 << (exp - 1);
    final ms = minInterval.inMilliseconds * mult;
    final capped = ms > maxInterval.inMilliseconds
        ? maxInterval.inMilliseconds
        : ms;
    return Duration(milliseconds: capped);
  }

  /// Milliseconds until [now] may attempt again (0 = immediately).
  Duration delayUntilNextAttempt(DateTime now) {
    final last = _lastAttemptAt;
    if (last == null) return Duration.zero;
    final wait = backoffAfterFailures(_consecutiveFailures);
    final elapsed = now.difference(last);
    if (!elapsed.isNegative && elapsed >= wait) return Duration.zero;
    return wait - elapsed;
  }

  void markAttempt(DateTime now) {
    _lastAttemptAt = now;
  }

  bool canAttemptNow(DateTime now) =>
      delayUntilNextAttempt(now) == Duration.zero;

  void markFailure(DateTime now) {
    _consecutiveFailures++;
    _lastAttemptAt = now;
  }

  void markSuccess() {
    _consecutiveFailures = 0;
    _lastAttemptAt = null;
  }

  void reset() {
    _consecutiveFailures = 0;
    _lastAttemptAt = null;
  }

  /// Sanitized log line — no UID/token/connectionId.
  static String sanitizeError(Object? error) {
    if (error == null) return 'unknown';
    final s = error.toString().toLowerCase();
    if (s.contains('permission-denied') ||
        s.contains('permission_denied') ||
        s.contains('permission denied')) {
      return 'permission_denied';
    }
    if (s.contains('network') || s.contains('offline')) return 'network';
    if (s.contains('auth') || s.contains('unauthenticated')) return 'auth';
    if (s.contains('disconnected')) return 'disconnected';
    return 'write_failed';
  }
}
