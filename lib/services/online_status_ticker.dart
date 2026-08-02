import 'dart:async';

/// Ticker compartilhado local (sem I/O). Útil para reavaliação visual periódica
/// sem criar timers por item e sem acessar Firebase.
///
/// - Um único [Timer.periodic] para toda a app
/// - Sem timer por item da lista
/// - Para automaticamente quando não há listeners
class OnlineStatusTicker {
  OnlineStatusTicker._();
  static final OnlineStatusTicker instance = OnlineStatusTicker._();

  /// Intervalo leve (~1/6 da janela online) para a UI refletir expiração.
  static const Duration period = Duration(seconds: 15);

  StreamController<DateTime>? _controller;
  Timer? _timer;
  int _listenerCount = 0;

  /// Emite [DateTime.now] periodicamente enquanto houver ouvintes.
  Stream<DateTime> get stream {
    _controller ??= StreamController<DateTime>.broadcast(
      onListen: _onListen,
      onCancel: _onCancel,
    );
    return _controller!.stream;
  }

  void _onListen() {
    _listenerCount++;
    if (_timer != null) return;
    _timer = Timer.periodic(period, (_) {
      final c = _controller;
      if (c == null || c.isClosed) return;
      c.add(DateTime.now());
    });
  }

  void _onCancel() {
    _listenerCount--;
    if (_listenerCount > 0) return;
    _listenerCount = 0;
    _timer?.cancel();
    _timer = null;
  }

  /// Só para testes: força um tick imediato.
  void debugEmitNow([DateTime? now]) {
    final c = _controller;
    if (c == null || c.isClosed) return;
    c.add(now ?? DateTime.now());
  }

  /// Só para testes: reinicia estado interno.
  void debugReset() {
    _timer?.cancel();
    _timer = null;
    _listenerCount = 0;
    if (_controller != null && !_controller!.isClosed) {
      _controller!.close();
    }
    _controller = null;
  }
}
