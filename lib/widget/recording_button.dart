import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:socialchat_mvp/services/voice_service.dart';
import '../l10n/app_texts.dart';

class RecordingButton extends StatefulWidget {
  final void Function(String? path)? onRecorded;
  final VoidCallback? onRecordStart;
  final VoidCallback? onRecordStop;
  final bool enabled;

  const RecordingButton({
    super.key,
    this.onRecorded,
    this.onRecordStart,
    this.onRecordStop,
    this.enabled = true,
  });

  @override
  State<RecordingButton> createState() => _RecordingButtonState();
}

class _RecordingButtonState extends State<RecordingButton> {
  bool _isRecording = false;
  bool _willCancel = false;
  bool _pressActive = false;
  bool _startInFlight = false;

  static const double _cancelDx = -70;

  Timer? _waveTimer;
  Timer? _elapsedTimer;

  List<double> _waves = List.generate(16, (_) => 2);
  int _seconds = 0;

  final Random _rnd = Random();

  static const Color _remdyBlue = Color(0xFF313A5F);

  void _log(String msg) {
    if (kDebugMode) debugPrint('RecordingButton: $msg');
  }

  void _startWave() {
    _waveTimer?.cancel();
    _waveTimer = Timer.periodic(
      const Duration(milliseconds: 120),
      (_) {
        if (!_isRecording || !mounted) return;
        setState(() {
          _waves = List.generate(16, (_) => 4 + _rnd.nextDouble() * 10);
        });
      },
    );
  }

  void _stopWave() {
    _waveTimer?.cancel();
    _waveTimer = null;
  }

  void _startElapsed() {
    _elapsedTimer?.cancel();
    _seconds = 0;
    _elapsedTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!_isRecording || !mounted) return;
        setState(() => _seconds++);
      },
    );
  }

  void _stopElapsed() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  String _fmt(int total) {
    final m = (total ~/ 60).toString();
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _start() async {
    if (!widget.enabled) return;
    if (_isRecording || _startInFlight) return;

    _startInFlight = true;
    try {
      final ok = await VoiceService.instance.hasPermission();
      if (!ok) {
        _log('Permissão de microfone negada');
        return;
      }

      // Dedo já soltou enquanto a permissão/start rodava.
      if (!_pressActive) {
        _log('Press solto antes do start — abortando gravação');
        return;
      }

      await VoiceService.instance.start();

      if (!mounted) return;

      if (!_pressActive) {
        _log('Press solto durante start — parando imediatamente');
        final path = await VoiceService.instance.stop();
        widget.onRecordStop?.call();
        if (path != null && widget.onRecorded != null) {
          widget.onRecorded!(path);
        }
        return;
      }

      setState(() {
        _isRecording = true;
        _willCancel = false;
        _seconds = 0;
      });

      widget.onRecordStart?.call();
      _startWave();
      _startElapsed();
      _log('UI gravação ativa');
    } on PlatformException catch (e, st) {
      _log('Erro PlatformException no start: $e\n$st');
    } catch (e, st) {
      _log('Erro no start: $e\n$st');
    } finally {
      _startInFlight = false;
    }
  }

  Future<void> _stop({required bool cancel}) async {
    if (!_isRecording && !VoiceService.instance.isRecording) return;

    try {
      _stopWave();
      _stopElapsed();

      String? path;
      if (cancel) {
        await VoiceService.instance.cancel();
        path = null;
        _log('Stop com cancel');
      } else {
        path = await VoiceService.instance.stop();
        _log('Stop com arquivo path=$path');
      }

      widget.onRecordStop?.call();

      if (!mounted) return;

      setState(() {
        _isRecording = false;
        _willCancel = false;
        _seconds = 0;
      });

      if (!cancel && widget.onRecorded != null) {
        widget.onRecorded!(path);
      }
    } catch (e, st) {
      _log('Erro no stop: $e\n$st');
      widget.onRecordStop?.call();

      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _willCancel = false;
        _seconds = 0;
      });
    }
  }

  void _onMove(LongPressMoveUpdateDetails d) {
    if (!_isRecording) return;
    final cancel = d.localOffsetFromOrigin.dx <= _cancelDx;
    if (cancel != _willCancel) {
      setState(() => _willCancel = cancel);
    }
  }

  Widget _wave() {
    return SizedBox(
      height: 16,
      width: 76,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: _waves.map((h) {
          return Container(
            width: 2,
            height: h,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: _remdyBlue,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  void dispose() {
    _stopWave();
    _stopElapsed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTexts.current;

    // Mesmo GestureDetector nos dois estados — evita perder onLongPressEnd
    // quando a UI troca de idle → gravando (causa raiz intermitente).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onLongPressStart: (_) {
        _pressActive = true;
        _willCancel = false;
        _start();
      },
      onLongPressMoveUpdate: _onMove,
      onLongPressEnd: (_) {
        _pressActive = false;
        if (_isRecording || VoiceService.instance.isRecording) {
          _stop(cancel: _willCancel);
        }
      },
      onLongPressCancel: () {
        _pressActive = false;
        if (_isRecording || VoiceService.instance.isRecording) {
          _stop(cancel: true);
        }
      },
      child: _isRecording
          ? Container(
              constraints: const BoxConstraints(
                minHeight: 34,
                minWidth: 34,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.mic,
                    color: _remdyBlue,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  _wave(),
                  const SizedBox(width: 6),
                  Text(
                    _fmt(_seconds),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _remdyBlue,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _willCancel ? t.get('cancel') : t.get('recording'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: _remdyBlue,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            )
          : Container(
              constraints: const BoxConstraints(
                minHeight: 34,
                minWidth: 34,
              ),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: const Icon(
                Icons.mic_none,
                color: Color(0xFF6B7280),
                size: 18,
              ),
            ),
    );
  }
}
