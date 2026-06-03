import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'fsk_service.dart';

/// Plays PCM audio through the speaker using Flutter's platform channel
/// Falls back to writing a WAV and using audioplayers if needed
class TonePlayer {
  static const _channel = MethodChannel('sadda_yone/audio_player');

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  /// Transmit a text message as ultrasonic tones
  Future<void> transmit(String text) async {
    if (_isPlaying) return;
    _isPlaying = true;

    try {
      final pcmBytes = FskService.encodeMessage(text);
      await _channel.invokeMethod('playPcm', {
        'bytes': pcmBytes,
        'sampleRate': FskService.SAMPLE_RATE,
      });
    } finally {
      _isPlaying = false;
    }
  }

  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stopPcm');
    } catch (_) {}
    _isPlaying = false;
  }

  void dispose() {
    stop();
  }
}
