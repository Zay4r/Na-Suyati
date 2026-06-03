import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:permission_handler/permission_handler.dart';
import 'fft_service.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _subscription;
  final StreamController<FFTResult> _fftController =
      StreamController<FFTResult>.broadcast();

  Stream<FFTResult> get fftStream => _fftController.stream;

  final List<int> _buffer = [];
  static const int _targetBytes = FFTService.FFT_SIZE * 2;

  Future<bool> hasPermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  Future<bool> start() async {
    final granted = await hasPermission();
    if (!granted) return false;

    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: FFTService.SAMPLE_RATE,
          numChannels: 1,
        ),
      );

      _subscription = stream.listen(
        (Uint8List chunk) {
          _buffer.addAll(chunk);
          while (_buffer.length >= _targetBytes) {
            final bytes =
                Uint8List.fromList(_buffer.sublist(0, _targetBytes));
            _buffer.removeRange(0, _targetBytes);
            try {
              final result = FFTService.process(bytes);
              if (!_fftController.isClosed) _fftController.add(result);
            } catch (_) {}
          }
        },
        onError: (_) => stop(),
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
    _buffer.clear();
    await _recorder.stop();
  }

  void dispose() {
    stop();
    _recorder.dispose();
    if (!_fftController.isClosed) _fftController.close();
  }
}
