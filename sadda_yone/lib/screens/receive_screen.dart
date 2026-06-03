import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/audio_service.dart';
import '../services/fft_service.dart';
import '../services/fsk_service.dart';
import '../widgets/spectrum_painter.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen>
    with TickerProviderStateMixin {
  final AudioService _audioService = AudioService();
  late FskDecoder _decoder;
  StreamSubscription<FFTResult>? _fftSub;

  bool _isListening = false;
  bool _isLoading = false;
  FFTResult? _lastFFT;
  List<double> _smoothedMags = [];
  static const double _smoothingFactor = 0.35;

  String _currentReceiving = '';
  final List<Map<String, String>> _messageLog = [];

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _decoder = FskDecoder(
      onChar: (c) {
        if (mounted) setState(() => _currentReceiving += c);
      },
      onMessage: (msg) {
        if (mounted) {
          setState(() {
            _messageLog.insert(0, {
              'msg': msg,
              'time': TimeOfDay.now().format(context),
            });
            if (_messageLog.length > 20) _messageLog.removeLast();
            _currentReceiving = '';
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _fftSub?.cancel();
    _audioService.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_isListening) {
      await _audioService.stop();
      _fftSub?.cancel();
      _decoder.reset();
      setState(() {
        _isListening = false;
        _lastFFT = null;
        _smoothedMags = [];
        _currentReceiving = '';
      });
      return;
    }

    setState(() => _isLoading = true);
    final started = await _audioService.start();
    if (!started) {
      setState(() => _isLoading = false);
      return;
    }

    _fftSub = _audioService.fftStream.listen((FFTResult fft) {
      if (_smoothedMags.isEmpty) {
        _smoothedMags = List<double>.from(fft.magnitudes);
      }
      for (int i = 0;
          i < min(_smoothedMags.length, fft.magnitudes.length);
          i++) {
        _smoothedMags[i] = _smoothedMags[i] * (1 - _smoothingFactor) +
            fft.magnitudes[i] * _smoothingFactor;
      }

      _decoder.processMagnitudes(fft.magnitudes, fft.sampleRate, fft.fftSize);

      setState(() => _lastFFT = fft);
    });

    setState(() {
      _isListening = true;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C1A),
      body: SafeArea(
        child: Column(children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF1A2035))),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF111827),
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: const Color(0xFF1E2D4A)),
                ),
                child: const Icon(Icons.hearing,
                    color: Color(0xFF00FF88), size: 20),
              ),
              const SizedBox(width: 12),
              const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Receive',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    Text('Decode incoming ultrasonic messages',
                        style:
                            TextStyle(color: Color(0xFF445577), fontSize: 11)),
                  ]),
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
                      color: _isListening
                          ? const Color(0xFF00FF88)
                          : const Color(0xFF334466),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _isListening ? 'LIVE' : 'OFF',
                style: TextStyle(
                  color: _isListening
                      ? const Color(0xFF00FF88)
                      : const Color(0xFF334466),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.5,
                ),
              ),
            ]),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                // Spectrum
                Container(
                  height: 140,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1A2540)),
                    color: const Color(0xFF0A1020),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CustomPaint(
                      painter: SpectrumPainter(
                        fftResult: _lastFFT,
                        smoothedMags: List<double>.from(_smoothedMags),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Currently receiving
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1020),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _currentReceiving.isNotEmpty
                          ? const Color(0xFF0088FF).withOpacity(0.4)
                          : const Color(0xFF1A2840),
                    ),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(
                            Icons.radio_button_checked,
                            color: _currentReceiving.isNotEmpty
                                ? const Color(0xFF0088FF)
                                : const Color(0xFF334466),
                            size: 12,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _currentReceiving.isNotEmpty
                                ? 'RECEIVING...'
                                : 'WAITING',
                            style: TextStyle(
                              color: _currentReceiving.isNotEmpty
                                  ? const Color(0xFF0088FF)
                                  : const Color(0xFF334466),
                              fontSize: 10,
                              letterSpacing: 1.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ]),
                        const SizedBox(height: 10),
                        Text(
                          _currentReceiving.isNotEmpty
                              ? _currentReceiving
                              : '—',
                          style: TextStyle(
                            color: _currentReceiving.isNotEmpty
                                ? Colors.white
                                : const Color(0xFF334466),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ]),
                ),

                const SizedBox(height: 16),

                // Message log
                if (_messageLog.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
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
                            Icon(Icons.mark_chat_read,
                                color: Color(0xFF00FF88), size: 14),
                            SizedBox(width: 6),
                            Text('Received Messages',
                                style: TextStyle(
                                  color: Color(0xFF6688BB),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                )),
                          ]),
                        ),
                        ..._messageLog.map((entry) => Container(
                              margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0A1530),
                                borderRadius: BorderRadius.circular(8),
                                border:
                                    Border.all(color: const Color(0xFF1A3050)),
                              ),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(entry['msg']!,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        )),
                                    const SizedBox(height: 4),
                                    Text(entry['time']!,
                                        style: const TextStyle(
                                          color: Color(0xFF445566),
                                          fontSize: 10,
                                          fontFamily: 'monospace',
                                        )),
                                  ]),
                            )),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(32),
                    child: Column(children: [
                      Icon(Icons.inbox,
                          color: Colors.white.withOpacity(0.08), size: 48),
                      const SizedBox(height: 10),
                      Text('No messages yet',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.15),
                              fontSize: 13)),
                      const SizedBox(height: 4),
                      Text('Start listening and transmit from another device',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.08),
                              fontSize: 11),
                          textAlign: TextAlign.center),
                    ]),
                  ),
                ],

                const SizedBox(height: 80),
              ]),
            ),
          ),
        ]),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: GestureDetector(
          onTap: _isLoading ? null : _toggle,
          child: Container(
            height: 52,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(
                colors: _isListening
                    ? [const Color(0xFF3A0808), const Color(0xFF550C0C)]
                    : [const Color(0xFF003320), const Color(0xFF005533)],
              ),
              border: Border.all(
                color: _isListening
                    ? const Color(0xFFFF3333).withOpacity(0.4)
                    : const Color(0xFF00FF88).withOpacity(0.35),
              ),
            ),
            child: Center(
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF00FF88)))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(
                        _isListening
                            ? Icons.stop_circle_outlined
                            : Icons.hearing,
                        color: _isListening
                            ? const Color(0xFFFF5555)
                            : const Color(0xFF00FF88),
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _isListening ? 'STOP' : 'START LISTENING',
                        style: TextStyle(
                          color: _isListening
                              ? const Color(0xFFFF5555)
                              : const Color(0xFF00FF88),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2,
                        ),
                      ),
                    ]),
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
