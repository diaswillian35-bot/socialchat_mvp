import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';


import 'package:socialchat_mvp/services/audio_playback_controller.dart';


class AudioBubble extends StatefulWidget {
  final String audioUrl;
  final bool isMe;
  final int durationMs;
  final String messageId;
  final String timeText;


  const AudioBubble({
    super.key,
    required this.audioUrl,
    required this.isMe,
    required this.messageId,
    this.durationMs = 0,
    this.timeText = '',
  });


  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}


class _AudioBubbleState extends State<AudioBubble> {
  final AudioPlayer _player = AudioPlayer();


  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;


  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration?>? _durSub;
  StreamSubscription<PlayerState>? _stateSub;


  bool get _playing => _player.playing;


  static const Color _text = Color(0xFF111827);
  static const Color _border = Color(0xFFE5E7EB);
  static const Color _remdyBlue = Color(0xFF313A5F);


  @override
  void initState() {
    super.initState();
    _bindPlayer();
    _applyInitialDuration();
  }


  void _applyInitialDuration() {
    if (widget.durationMs > 0) {
      _duration = Duration(milliseconds: widget.durationMs);
    } else {
      _duration = Duration.zero;
    }
  }


  void _bindPlayer() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();


    _posSub = _player.positionStream.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });


    _durSub = _player.durationStream.listen((d) {
      if (!mounted) return;
      if (d != null && d > Duration.zero) {
        setState(() => _duration = d);
      }
    });


    _stateSub = _player.playerStateStream.listen((st) async {
      if (!mounted) return;


      if (st.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
        await _player.pause();
        if (!mounted) return;
        setState(() => _position = Duration.zero);
      } else {
        setState(() {});
      }
    });
  }


  Future<void> _resetForNewMessage() async {
    try {
      await _player.stop();
    } catch (_) {}


    AudioPlaybackController.instance.release(_player);


    _position = Duration.zero;
    _applyInitialDuration();


    try {
      await _player.setUrl(widget.audioUrl);
    } catch (_) {
      // carrega sob demanda quando clicar em play
    }


    if (mounted) setState(() {});
  }


  @override
  void didUpdateWidget(covariant AudioBubble oldWidget) {
    super.didUpdateWidget(oldWidget);


    final changedMessage = oldWidget.messageId != widget.messageId;
    final changedUrl = oldWidget.audioUrl != widget.audioUrl;
    final changedDuration = oldWidget.durationMs != widget.durationMs;


    if (changedMessage || changedUrl) {
      _resetForNewMessage();
      return;
    }


    if (changedDuration && widget.durationMs > 0 && _duration == Duration.zero) {
      setState(() {
        _duration = Duration(milliseconds: widget.durationMs);
      });
    }
  }


  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _stateSub?.cancel();
    AudioPlaybackController.instance.release(_player);
    _player.dispose();
    super.dispose();
  }


  String _fmt(Duration d) {
    final s = d.inSeconds;
    final m = (s ~/ 60).toString();
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }


  Duration get _safeDuration {
    if (_duration > Duration.zero) return _duration;
    if (widget.durationMs > 0) {
      return Duration(milliseconds: widget.durationMs);
    }
    return Duration.zero;
  }


  double get _progress {
    final dur = _safeDuration.inMilliseconds;
    if (dur <= 0) return 0;
    final pos = _position.inMilliseconds.clamp(0, dur);
    return pos / dur;
  }


  Future<void> _toggle() async {
    try {
      if (_playing) {
        await _player.pause();
        return;
      }


      await AudioPlaybackController.instance.playExclusive(_player);


      if (_player.audioSource == null) {
        await _player.setUrl(widget.audioUrl);
      }


      await _player.play();
    } catch (e) {
      debugPrint('ERRO PLAYER (${widget.messageId}): $e');
    }
  }


  void _seekToRatio(double ratio) {
    final dur = _safeDuration;
    if (dur <= Duration.zero) return;


    final ms =
        (dur.inMilliseconds * ratio).round().clamp(0, dur.inMilliseconds);
    _player.seek(Duration(milliseconds: ms));
  }


  @override
  Widget build(BuildContext context) {
    final bg = widget.isMe ? _remdyBlue : Colors.white;
    final fg = widget.isMe ? Colors.white : _text;


    final dur = _safeDuration;
    final left = _fmt(_position);
    final right = dur > Duration.zero ? _fmt(dur) : '--:--';


    return Align(
      alignment: widget.isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: widget.isMe ? null : Border.all(color: _border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: _toggle,
              borderRadius: BorderRadius.circular(999),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  _playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: fg,
                  size: 26,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (_, c) {
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (tap) {
                          final x = tap.localPosition.dx;
                          final w = c.maxWidth <= 0 ? 1.0 : c.maxWidth;
                          final ratio = (x / w).clamp(0.0, 1.0);
                          _seekToRatio(ratio);
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: Container(
                            height: 6,
                            color: widget.isMe
                                ? Colors.white.withOpacity(0.25)
                                : const Color(0xFFE5E7EB),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: _progress.clamp(0.0, 1.0),
                              child: Container(
                                color: widget.isMe
                                    ? Colors.white.withOpacity(0.85)
                                    : _remdyBlue.withOpacity(0.75),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        left,
                        style: TextStyle(
                          color: fg,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        widget.timeText.isEmpty
                            ? right
                            : '$right • ${widget.timeText}',
                        style: TextStyle(
                          color: fg.withOpacity(0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
