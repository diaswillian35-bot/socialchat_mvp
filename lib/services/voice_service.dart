

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';


class VoiceService {
  VoiceService._();
  static final VoiceService instance = VoiceService._();


  final AudioRecorder _recorder = AudioRecorder();


  String? _path;
  bool _isRecording = false;


  bool get isRecording => _isRecording;
  String? get lastPath => _path;


  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }


 Future<String> start() async {
  final ok = await _recorder.hasPermission();
  if (!ok) throw Exception('Microphone permission denied');


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
  return path;
}


  Future<String?> stop() async {
    final path = await _recorder.stop();
    _isRecording = false;
    if (path != null) _path = path;
    return path;
  }


  Future<void> cancel() async {
    await _recorder.stop();
    _isRecording = false;
  }


 

Future<void> dispose() async {
  await _recorder.dispose();
}

}
