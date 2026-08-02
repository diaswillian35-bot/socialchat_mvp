import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

class AudioPlaybackController {
  AudioPlaybackController._();
  static final AudioPlaybackController instance = AudioPlaybackController._();

  AudioPlayer? _current;

  Future<void> playExclusive(AudioPlayer player) async {
    if (_current != null && _current != player) {
      try {
        if (kDebugMode) {
          debugPrint('AudioPlaybackController: parando player anterior');
        }
        await _current!.stop();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('AudioPlaybackController: erro ao parar anterior: $e\n$st');
        }
      }
    }
    _current = player;
  }

  void release(AudioPlayer player) {
    if (_current == player) _current = null;
  }
}
