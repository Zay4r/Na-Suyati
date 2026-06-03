import 'dart:math';
import 'dart:typed_data';

/// FSK (Frequency Shift Keying) over ultrasonic range
/// Protocol:
///   - Each character maps to a unique frequency in 18000–21800 Hz
///   - Tone duration: 150ms per character
///   - Gap between chars: 60ms silence
///   - Start beacon: 17500 Hz for 200ms
///   - End beacon:   17200 Hz for 200ms
///   - Supported: ASCII 32–126 (space, A-Z, a-z, 0-9, punctuation)
class FskService {
  static const int SAMPLE_RATE = 44100;

  // Protocol timing (ms)
  static const int TONE_MS = 150;
  static const int GAP_MS = 60;
  static const int BEACON_MS = 200;

  // Frequency range for data
  static const double BASE_FREQ = 18000.0;
  static const double FREQ_STEP = 40.0; // Hz per ASCII step

  // Special beacons
  static const double START_FREQ = 17500.0;
  static const double END_FREQ = 17200.0;

  // Supported ASCII range: 32 (space) to 126 (~)
  static const int ASCII_MIN = 32;
  static const int ASCII_MAX = 126;

  /// Encode a character to its frequency
  static double charToFreq(String c) {
    final code = c.codeUnitAt(0).clamp(ASCII_MIN, ASCII_MAX);
    return BASE_FREQ + (code - ASCII_MIN) * FREQ_STEP;
  }

  /// Decode a frequency back to a character
  /// Returns null if frequency doesn't match any character
  static String? freqToChar(double freq) {
    if ((freq - START_FREQ).abs() < 80) return '\x02'; // STX marker
    if ((freq - END_FREQ).abs() < 80) return '\x03';   // ETX marker

    final offset = freq - BASE_FREQ;
    if (offset < -80 || offset > (ASCII_MAX - ASCII_MIN) * FREQ_STEP + 80) {
      return null;
    }
    final index = (offset / FREQ_STEP).round();
    if (index < 0 || index > ASCII_MAX - ASCII_MIN) return null;
    return String.fromCharCode(ASCII_MIN + index);
  }

  /// Generate PCM16 audio bytes for the full message
  static Uint8List encodeMessage(String text) {
    final allSamples = <double>[];

    // Start beacon
    allSamples.addAll(_generateTone(START_FREQ, BEACON_MS));
    allSamples.addAll(_generateSilence(GAP_MS));

    // Encode each character
    for (int i = 0; i < text.length; i++) {
      final freq = charToFreq(text[i]);
      allSamples.addAll(_generateTone(freq, TONE_MS));
      allSamples.addAll(_generateSilence(GAP_MS));
    }

    // End beacon
    allSamples.addAll(_generateTone(END_FREQ, BEACON_MS));

    return _samplesToBytes(allSamples);
  }

  /// Generate a sine wave tone at given frequency for given duration
  static List<double> _generateTone(double freq, int durationMs) {
    final numSamples = (SAMPLE_RATE * durationMs / 1000).round();
    return List.generate(numSamples, (i) {
      // Apply Hanning envelope to reduce clicking
      final envelope = 0.5 * (1 - cos(2 * pi * i / (numSamples - 1)));
      return sin(2 * pi * freq * i / SAMPLE_RATE) * envelope * 0.8;
    });
  }

  /// Generate silence
  static List<double> _generateSilence(int durationMs) {
    final numSamples = (SAMPLE_RATE * durationMs / 1000).round();
    return List.filled(numSamples, 0.0);
  }

  /// Convert double samples to PCM16 bytes
  static Uint8List _samplesToBytes(List<double> samples) {
    final bytes = ByteData(samples.length * 2);
    for (int i = 0; i < samples.length; i++) {
      final val = (samples[i].clamp(-1.0, 1.0) * 32767).round();
      bytes.setInt16(i * 2, val, Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  /// Total duration of encoded message in seconds
  static double messageDuration(String text) {
    final ms = BEACON_MS + GAP_MS +
        text.length * (TONE_MS + GAP_MS) +
        BEACON_MS;
    return ms / 1000.0;
  }
}

/// State machine for decoding incoming FFT frames into characters
class FskDecoder {
  static const double MAGNITUDE_THRESHOLD = 0.15;
  static const int MIN_FRAMES_FOR_TONE = 3; // ~90ms at 30fps

  // Detection state
  String? _currentChar;
  int _frameCount = 0;
  bool _inMessage = false;
  bool _started = false;

  final StringBuffer _buffer = StringBuffer();
  String get decoded => _buffer.toString();

  // Callback
  final void Function(String char)? onChar;
  final void Function(String message)? onMessage;

  FskDecoder({this.onChar, this.onMessage});

  void reset() {
    _currentChar = null;
    _frameCount = 0;
    _inMessage = false;
    _started = false;
    _buffer.clear();
  }

  /// Feed an FFT frame into the decoder
  void processMagnitudes(List<double> magnitudes, int sampleRate, int fftSize) {
    // Find peak in 17000–22000 Hz range
    final startBin = (17000 * fftSize / sampleRate).round();
    final endBin = (22000 * fftSize / sampleRate).round().clamp(0, magnitudes.length - 1);

    double maxMag = 0;
    int maxBin = startBin;
    for (int i = startBin; i <= endBin; i++) {
      if (magnitudes[i] > maxMag) {
        maxMag = magnitudes[i];
        maxBin = i;
      }
    }

    // Normalize magnitude
    final avgMag = _average(magnitudes, 100, startBin - 1);
    final normalizedMag = avgMag > 0 ? maxMag / (avgMag * 10) : 0.0;

    if (normalizedMag < MAGNITUDE_THRESHOLD) {
      // Silence — commit current char if we had enough frames
      if (_currentChar != null && _frameCount >= MIN_FRAMES_FOR_TONE) {
        _commitChar(_currentChar!);
      }
      _currentChar = null;
      _frameCount = 0;
      return;
    }

    final freq = maxBin * sampleRate / fftSize.toDouble();
    final detectedChar = FskService.freqToChar(freq);

    if (detectedChar == null) {
      _currentChar = null;
      _frameCount = 0;
      return;
    }

    if (detectedChar == _currentChar) {
      _frameCount++;
    } else {
      // New tone started
      if (_currentChar != null && _frameCount >= MIN_FRAMES_FOR_TONE) {
        _commitChar(_currentChar!);
      }
      _currentChar = detectedChar;
      _frameCount = 1;
    }
  }

  void _commitChar(String c) {
    if (c == '\x02') {
      // STX — start of message
      _started = true;
      _inMessage = true;
      _buffer.clear();
    } else if (c == '\x03') {
      // ETX — end of message
      if (_started && _inMessage) {
        _inMessage = false;
        _started = false;
        onMessage?.call(_buffer.toString());
      }
    } else if (_inMessage) {
      _buffer.write(c);
      onChar?.call(c);
    }
  }

  double _average(List<double> mags, int from, int to) {
    if (from >= to || to >= mags.length) return 0;
    double sum = 0;
    for (int i = from; i <= to; i++) sum += mags[i];
    return sum / (to - from + 1);
  }
}
