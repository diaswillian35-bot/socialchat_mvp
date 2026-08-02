import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();

  final AudioRecorder _recorder = AudioRecorder();

  String? _path;
  bool _isRecording = false;
  bool _starting = false;

  bool get isRecording => _isRecording;
  String? get lastPath => _path;

  void _log(String msg) {
    if (kDebugMode) debugPrint('VoiceService: $msg');
  }

  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  Future<String> start() async {
    if (_isRecording || _starting) {
      _log('start ignorado (já gravando/starting) path=$_path');
      return _path ?? '';
    }

    _starting = true;
    try {
      _log('Gravação iniciando…');
      final ok = await _recorder.hasPermission();
      if (!ok) {
        throw Exception('Microphone permission denied');
      }

      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/remdy_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: path,
      );

      _isRecording = true;
      _path = path;
      _log('Gravação iniciou path=$path');
      return path;
    } finally {
      _starting = false;
    }
  }

  Future<String?> stop() async {
    if (!_isRecording) {
      _log('stop ignorado (não gravando)');
      return null;
    }

    _log('Gravação terminando…');
    final path = await _recorder.stop();
    _isRecording = false;
    if (path != null) _path = path;

    final resolved = _path;
    if (resolved != null) {
      await _waitForFileReady(resolved);
    }

    _log('Gravação terminou path=$resolved size=${await _fileSize(resolved)}');
    return resolved;
  }

  Future<void> cancel() async {
    if (!_isRecording) return;
    _log('Gravação cancelada');
    await _recorder.cancel();
    _isRecording = false;
    _path = null;
  }

  Future<void> _waitForFileReady(String path) async {
    final file = File(path);
    for (var i = 0; i < 20; i++) {
      if (await file.exists()) {
        final len = await file.length();
        if (len > 0) {
          _log('Arquivo criado path=$path bytes=$len attempt=$i');
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    _log('Arquivo ainda vazio/ausente após espera path=$path');
  }

  Future<int> _fileSize(String? path) async {
    if (path == null) return 0;
    try {
      final f = File(path);
      if (!await f.exists()) return 0;
      return await f.length();
    } catch (_) {
      return 0;
    }
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }
}
