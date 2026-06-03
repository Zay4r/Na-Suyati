import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/audio_service.dart';
import '../services/fft_service.dart';
import '../widgets/spectrum_painter.dart';

const Map<int, String> _knownBeacons = {
  18000: 'Retail tracking beacon',
  18500: 'Google Nearby',
  19000: 'Payment terminal',
  19200: 'Cisco Presence',
  20000: 'Chirp.io data',
  20500: 'Motion sensor',
};

const Map<String, Map<String, dynamic>> _animalRanges = {
  'Dog': {'min': 40.0, 'max': 65000.0, 'emoji': '🐕'},
  'Cat': {'min': 48.0, 'max': 79000.0, 'emoji': '🐈'},
  'Bat': {'min': 1000.0, 'max': 100000.0, 'emoji': '🦇'},
};

class DetectorScreen extends StatefulWidget {
  const DetectorScreen({super.key});

  @override
  State<DetectorScreen> createState() => _DetectorScreenState();
}

class _DetectorScreenState extends State<DetectorScreen>
    with TickerProviderStateMixin {
  final AudioService _audioService = AudioService();
  StreamSubscription<FFTResult>? _fftSub;

  bool _isListening = false;
  bool _isLoading = false;
  FFTResult? _lastFFT;

  double _peakFreq = 0;
  double _peakMag = 0;
  double _noiseFloor = 0;
  bool _ultrasonicDetected = false;
  String? _beaconMatch;
  List<String> _animalWarnings = [];

  List<double> _smoothedMags = [];
  static const double _smoothingFactor = 0.4;

  final List<Map<String, dynamic>> _detectionLog = [];

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _fftSub?.cancel();
    _audioService.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _audioService.stop();
      _fftSub?.cancel();
      setState(() {
        _isListening = false;
        _lastFFT = null;
        _smoothedMags = [];
        _peakFreq = 0;
        _peakMag = 0;
        _ultrasonicDetected = false;
        _beaconMatch = null;
        _animalWarnings = [];
      });
      return;
    }

    setState(() => _isLoading = true);
    final started = await _audioService.start();

    if (!started) {
      setState(() => _isLoading = false);
      _showPermissionError();
      return;
    }

    int frameCount = 0;
    double noiseAccum = 0;

    _fftSub = _audioService.fftStream.listen((FFTResult fft) {
      frameCount++;

      if (_smoothedMags.isEmpty) {
        _smoothedMags = List<double>.from(fft.magnitudes);
      }

      for (int i = 0; i < min(_smoothedMags.length, fft.magnitudes.length); i++) {
        _smoothedMags[i] = _smoothedMags[i] * (1 - _smoothingFactor) +
            fft.magnitudes[i] * _smoothingFactor;
      }

      if (frameCount <= 20) {
        noiseAccum += fft.getAverageMagnitudeInRange(100, 2000);
        _noiseFloor = noiseAccum / frameCount;
      }

      final peak = fft.getPeakFrequencyInRange(1000, 22000);
      final mag = fft.getPeakMagnitudeInRange(15000, 22000);
      final normalizedMag = (mag / max(_noiseFloor * 3, 1.0)).clamp(0.0, 10.0);
      final detected = peak >= 17000 && normalizedMag > 1.5;

      String? beacon;
      if (detected) {
        for (final entry in _knownBeacons.entries) {
          if ((peak - entry.key).abs() < 400) {
            beacon = '📡 ${entry.value} (~${entry.key}Hz)';
            break;
          }
        }
      }

      final warnings = <String>[];
      if (peak >= 17000 && normalizedMag > 1.0) {
        for (final entry in _animalRanges.entries) {
          final min_ = (entry.value['min'] as double);
          final max_ = (entry.value['max'] as double);
          if (peak >= min_ && peak <= max_) {
            warnings.add('${entry.value['emoji']} ${entry.key}s can hear this frequency!');
          }
        }
      }

      if (detected && !_ultrasonicDetected) {
        _detectionLog.insert(0, {
          'freq': peak,
          'mag': normalizedMag,
          'time': TimeOfDay.now().format(context),
          'beacon': beacon,
        });
        if (_detectionLog.length > 10) _detectionLog.removeLast();
      }

      setState(() {
        _lastFFT = fft;
        _peakFreq = peak;
        _peakMag = normalizedMag;
        _ultrasonicDetected = detected;
        _beaconMatch = beacon;
        _animalWarnings = warnings;
      });
    });

    setState(() {
      _isListening = true;
      _isLoading = false;
    });
  }

  void _showPermissionError() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A2035),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.mic_off, color: Color(0xFFFF6666)),
          SizedBox(width: 10),
          Text('Permission Required',
              style: TextStyle(color: Colors.white, fontSize: 16)),
        ]),
        content: const Text(
          'Microphone access is needed to scan for ultrasonic frequencies. '
          'Please grant it in your device settings.',
          style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK',
                style: TextStyle(color: Color(0xFF00FF88), fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Color get _statusColor {
    if (!_isListening) return const Color(0xFF334466);
    if (_ultrasonicDetected) return const Color(0xFFFF4444);
    if (_peakFreq >= 15000 && _peakMag > 0.5) return const Color(0xFFFFAA00);
    return const Color(0xFF00FF88);
  }

  String get _statusLabel {
    if (!_isListening) return 'IDLE';
    if (_ultrasonicDetected) return 'DETECTED';
    if (_peakFreq >= 15000 && _peakMag > 0.5) return 'NEAR-ULTRA';
    return 'SCANNING';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C1A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    _buildStatusRow(),
                    const SizedBox(height: 12),
                    _buildSpectrumCard(),
                    const SizedBox(height: 12),
                    _buildMetricsRow(),
                    const SizedBox(height: 12),
                    if (_animalWarnings.isNotEmpty) ...[
                      _buildWarningsCard(),
                      const SizedBox(height: 12),
                    ],
                    if (_beaconMatch != null) ...[
                      _buildBeaconCard(),
                      const SizedBox(height: 12),
                    ],
                    _buildFreqGuide(),
                    const SizedBox(height: 12),
                    if (_detectionLog.isNotEmpty) ...[
                      _buildDetectionLog(),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildFAB(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1A2035))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: const Color(0xFF1E2D4A)),
            ),
            child: const Icon(Icons.waves, color: Color(0xFF00FF88), size: 20),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ultrasonic Detector',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  )),
              Text('Real-time spectrum analyzer',
                  style: TextStyle(
                    color: Color(0xFF445577),
                    fontSize: 11,
                    letterSpacing: 0.2,
                  )),
            ],
          ),
          const Spacer(),
          AnimatedBuilder(
            animation: _pulseAnimation,
            builder: (_, __) => Opacity(
              opacity: _isListening ? _pulseAnimation.value : 0.3,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _statusColor,
                  boxShadow: _isListening
                      ? [BoxShadow(color: _statusColor.withOpacity(0.5), blurRadius: 6)]
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(_statusLabel,
              style: TextStyle(
                color: _statusColor,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              )),
        ],
      ),
    );
  }

  Widget _buildStatusRow() {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _statusColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _statusColor.withOpacity(0.25)),
            ),
            child: Row(
              children: [
                Icon(
                  _ultrasonicDetected
                      ? Icons.warning_amber
                      : _isListening
                          ? Icons.graphic_eq
                          : Icons.mic_off,
                  color: _statusColor,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  _isListening
                      ? _ultrasonicDetected
                          ? 'Ultrasonic frequency detected!'
                          : 'Listening for ultrasonic signals...'
                      : 'Tap START to begin scanning',
                  style: TextStyle(
                    color: _statusColor.withOpacity(0.9),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpectrumCard() {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1A2540)),
        color: const Color(0xFF0A1020),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            CustomPaint(
              painter: SpectrumPainter(
                fftResult: _lastFFT,
                smoothedMags: List<double>.from(_smoothedMags),
              ),
              child: const SizedBox.expand(),
            ),
            if (!_isListening)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.show_chart,
                        color: Colors.white.withOpacity(0.1), size: 36),
                    const SizedBox(height: 6),
                    Text('Spectrum will appear here',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.12),
                          fontSize: 11,
                        )),
                  ],
                ),
              ),
            Positioned(
              top: 6,
              left: 10,
              child: Text('0 Hz',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.2),
                    fontSize: 8,
                  )),
            ),
            Positioned(
              top: 6,
              right: 10,
              child: Text('22 kHz',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.2),
                    fontSize: 8,
                  )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsRow() {
    return Row(
      children: [
        _metricCard('PEAK FREQ',
            _isListening ? '${_peakFreq.toStringAsFixed(0)} Hz' : '—',
            Icons.multitrack_audio),
        const SizedBox(width: 10),
        _metricCard('STRENGTH',
            _isListening ? '${(_peakMag.clamp(0, 9.9) * 10).toStringAsFixed(0)}%' : '—',
            Icons.signal_cellular_alt),
        const SizedBox(width: 10),
        _metricCard(
          'ZONE',
          !_isListening
              ? '—'
              : _peakFreq >= 17000
                  ? 'ULTRA'
                  : _peakFreq >= 15000
                      ? 'NEAR'
                      : 'AUDIBLE',
          Icons.radar,
          accent: !_isListening
              ? null
              : _peakFreq >= 17000
                  ? const Color(0xFFFF4444)
                  : _peakFreq >= 15000
                      ? const Color(0xFFFFAA00)
                      : const Color(0xFF00FF88),
        ),
      ],
    );
  }

  Widget _metricCard(String label, String value, IconData icon, {Color? accent}) {
    final color = accent ?? const Color(0xFF3355AA);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1828),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF1A2840)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color.withOpacity(0.7), size: 14),
            const SizedBox(height: 6),
            Text(value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                )),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                  color: Color(0xFF445577),
                  fontSize: 8.5,
                  letterSpacing: 1.2,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A0A0A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF552222)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.pets, color: Color(0xFFFF6666), size: 14),
            SizedBox(width: 6),
            Text('Animal Hearing Warning',
                style: TextStyle(
                  color: Color(0xFFFF6666),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                )),
          ]),
          const SizedBox(height: 8),
          ..._animalWarnings.map((w) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(w,
                    style: const TextStyle(
                      color: Color(0xFFFF9999),
                      fontSize: 12,
                    )),
              )),
        ],
      ),
    );
  }

  Widget _buildBeaconCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1A0A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF225522)),
      ),
      child: Row(
        children: [
          const Icon(Icons.cell_tower, color: Color(0xFF66FF88), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_beaconMatch ?? '',
                style: const TextStyle(
                  color: Color(0xFF88FF99),
                  fontSize: 12,
                )),
          ),
        ],
      ),
    );
  }

  Widget _buildFreqGuide() {
    final items = [
      ('17,000 Hz', 'Ultrasonic pest repellers', const Color(0xFFFF5555)),
      ('18,000 Hz', 'Retail tracking (Silverpush)', const Color(0xFFFF6666)),
      ('18,500 Hz', 'Google Nearby notifications', const Color(0xFFFF7777)),
      ('19,000 Hz', 'Payment terminals', const Color(0xFFFF8888)),
      ('20,000 Hz', 'Chirp.io data transfer', const Color(0xFFFF9999)),
      ('21,000 Hz', 'Motion sensors / alarms', const Color(0xFFFFAAAA)),
    ];

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1828),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1A2840)),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(children: [
              Icon(Icons.info_outline, color: Color(0xFF3355AA), size: 14),
              SizedBox(width: 6),
              Text('Known Ultrasonic Frequencies',
                  style: TextStyle(
                    color: Color(0xFF6688BB),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  )),
            ]),
          ),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: item.$3),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 80,
                      child: Text(item.$1,
                          style: TextStyle(
                            color: item.$3,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          )),
                    ),
                    Text(item.$2,
                        style: const TextStyle(
                          color: Color(0xFF557799),
                          fontSize: 11,
                        )),
                  ],
                ),
              )),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildDetectionLog() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1828),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1A2840)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(children: [
              Icon(Icons.history, color: Color(0xFF3355AA), size: 14),
              SizedBox(width: 6),
              Text('Detection Log',
                  style: TextStyle(
                    color: Color(0xFF6688BB),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  )),
            ]),
          ),
          ..._detectionLog.take(5).map((entry) => Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
                child: Row(
                  children: [
                    const Icon(Icons.circle, color: Color(0xFF334466), size: 6),
                    const SizedBox(width: 8),
                    Text(entry['time'] as String,
                        style: const TextStyle(
                          color: Color(0xFF445566),
                          fontSize: 10,
                          fontFamily: 'monospace',
                        )),
                    const SizedBox(width: 10),
                    Text(
                      '${(entry['freq'] as double).toStringAsFixed(0)} Hz',
                      style: const TextStyle(
                        color: Color(0xFFFF7777),
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (entry['beacon'] != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry['beacon'] as String,
                          style: const TextStyle(
                            color: Color(0xFF557799),
                            fontSize: 10,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              )),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildFAB() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GestureDetector(
        onTap: _isLoading ? null : _toggleListening,
        child: Container(
          height: 52,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(
              colors: _isListening
                  ? [const Color(0xFF3A0808), const Color(0xFF550C0C)]
                  : [const Color(0xFF003320), const Color(0xFF005533)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: _isListening
                  ? const Color(0xFFFF3333).withOpacity(0.4)
                  : const Color(0xFF00FF88).withOpacity(0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: (_isListening
                        ? const Color(0xFFFF3333)
                        : const Color(0xFF00FF88))
                    .withOpacity(0.15),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: _isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _statusColor,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isListening ? Icons.stop_circle_outlined : Icons.mic,
                        color: _isListening
                            ? const Color(0xFFFF5555)
                            : const Color(0xFF00FF88),
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isListening ? 'STOP SCANNING' : 'START SCANNING',
                        style: TextStyle(
                          color: _isListening
                              ? const Color(0xFFFF5555)
                              : const Color(0xFF00FF88),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
