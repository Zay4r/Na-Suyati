import 'dart:math';
import 'dart:typed_data';

/// Holds the result of an FFT computation
class FFTResult {
  final List<double> magnitudes;
  final int sampleRate;
  final int fftSize;

  FFTResult({
    required this.magnitudes,
    required this.sampleRate,
    required this.fftSize,
  });

  /// Convert bin index to frequency in Hz
  double binToFreq(int bin) => bin * sampleRate / fftSize;

  /// Convert frequency in Hz to bin index
  int freqToBin(double freq) =>
      (freq * fftSize / sampleRate).round().clamp(0, magnitudes.length - 1);

  /// Get the peak frequency within a range (in Hz)
  double getPeakFrequencyInRange(double minFreq, double maxFreq) {
    final startBin = freqToBin(minFreq);
    final endBin = freqToBin(maxFreq);
    double maxMag = 0;
    int maxBin = startBin;
    for (int i = startBin; i <= endBin && i < magnitudes.length; i++) {
      if (magnitudes[i] > maxMag) {
        maxMag = magnitudes[i];
        maxBin = i;
      }
    }
    return binToFreq(maxBin);
  }

  /// Get the peak magnitude within a frequency range
  double getPeakMagnitudeInRange(double minFreq, double maxFreq) {
    final startBin = freqToBin(minFreq);
    final endBin = freqToBin(maxFreq);
    double maxMag = 0;
    for (int i = startBin; i <= endBin && i < magnitudes.length; i++) {
      if (magnitudes[i] > maxMag) maxMag = magnitudes[i];
    }
    return maxMag;
  }

  /// Get average magnitude within a frequency range
  double getAverageMagnitudeInRange(double minFreq, double maxFreq) {
    final startBin = freqToBin(minFreq);
    final endBin = freqToBin(maxFreq);
    if (startBin >= endBin) return 0;
    double sum = 0;
    for (int i = startBin; i <= endBin && i < magnitudes.length; i++) {
      sum += magnitudes[i];
    }
    return sum / (endBin - startBin + 1);
  }
}

class FFTService {
  static const int FFT_SIZE = 4096;
  static const int SAMPLE_RATE = 44100;

  // Precompute Hanning window to reduce spectral leakage
  static final List<double> _window = List.generate(
    FFT_SIZE,
    (i) => 0.5 * (1 - cos(2 * pi * i / (FFT_SIZE - 1))),
  );

  /// Process raw PCM16 bytes and return FFT magnitudes
  static FFTResult process(Uint8List rawBytes) {
    final samples = _bytesToSamples(rawBytes);
    final windowed = List<double>.filled(FFT_SIZE, 0.0);
    final len = min(samples.length, FFT_SIZE);

    for (int i = 0; i < len; i++) {
      windowed[i] = samples[i] * _window[i];
    }

    final magnitudes = _computeFFT(windowed);

    return FFTResult(
      magnitudes: magnitudes,
      sampleRate: SAMPLE_RATE,
      fftSize: FFT_SIZE,
    );
  }

  /// Convert raw PCM16 little-endian bytes to normalized doubles [-1.0, 1.0]
  static List<double> _bytesToSamples(Uint8List bytes) {
    final samples = <double>[];
    for (int i = 0; i + 1 < bytes.length; i += 2) {
      int raw = bytes[i] | (bytes[i + 1] << 8);
      if (raw > 32767) raw -= 65536;
      samples.add(raw / 32768.0);
    }
    return samples;
  }

  /// Cooley-Tukey radix-2 DIT FFT
  static List<double> _computeFFT(List<double> samples) {
    final n = FFT_SIZE;
    final real = List<double>.from(samples);
    final imag = List<double>.filled(n, 0.0);

    // Bit-reversal permutation
    int j = 0;
    for (int i = 1; i < n; i++) {
      int bit = n >> 1;
      while ((j & bit) != 0) {
        j ^= bit;
        bit >>= 1;
      }
      j ^= bit;
      if (i < j) {
        double t = real[i];
        real[i] = real[j];
        real[j] = t;
        t = imag[i];
        imag[i] = imag[j];
        imag[j] = t;
      }
    }

    // Butterfly operations
    int len = 2;
    while (len <= n) {
      final ang = -2.0 * pi / len;
      final wBaseR = cos(ang);
      final wBaseI = sin(ang);

      for (int i = 0; i < n; i += len) {
        double wrR = 1.0;
        double wrI = 0.0;

        for (int k = 0; k < len ~/ 2; k++) {
          final uR = real[i + k];
          final uI = imag[i + k];
          final vR = real[i + k + len ~/ 2] * wrR - imag[i + k + len ~/ 2] * wrI;
          final vI = real[i + k + len ~/ 2] * wrI + imag[i + k + len ~/ 2] * wrR;

          real[i + k] = uR + vR;
          imag[i + k] = uI + vI;
          real[i + k + len ~/ 2] = uR - vR;
          imag[i + k + len ~/ 2] = uI - vI;

          final newWrR = wrR * wBaseR - wrI * wBaseI;
          wrI = wrR * wBaseI + wrI * wBaseR;
          wrR = newWrR;
        }
      }
      len <<= 1;
    }

    return List.generate(
      n ~/ 2,
      (i) => sqrt(real[i] * real[i] + imag[i] * imag[i]),
    );
  }
}
