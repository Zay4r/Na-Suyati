import 'dart:async';
import 'package:flutter/material.dart';
import '../services/tone_player.dart';
import '../services/fsk_service.dart';
import '../services/wav_exporter.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final TonePlayer _player = TonePlayer();
  final TextEditingController _controller = TextEditingController();

  bool _isSending = false;
  bool _isSaving = false;
  double _progress = 0;
  String _status = 'Type a message and tap SEND';
  String? _savedPath;
  Timer? _progressTimer;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _player.dispose();
    _controller.dispose();
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    final duration = FskService.messageDuration(text);

    setState(() {
      _isSending = true;
      _progress = 0;
      _savedPath = null;
      _status = 'Transmitting...';
    });

    final startTime = DateTime.now();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      final elapsed =
          DateTime.now().difference(startTime).inMilliseconds / 1000.0;
      setState(() => _progress = (elapsed / duration).clamp(0.0, 1.0));
      if (elapsed >= duration) t.cancel();
    });

    await _player.transmit(text);

    _progressTimer?.cancel();
    setState(() {
      _isSending = false;
      _progress = 1.0;
      _status = 'Transmitted successfully!';
    });

    await Future.delayed(const Duration(seconds: 2));
    if (mounted)
      setState(() {
        _progress = 0;
        _status = 'Type a message and tap SEND';
      });
  }

  Future<void> _saveWav() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSaving) return;

    setState(() {
      _isSaving = true;
      _savedPath = null;
      _status = 'Encoding and saving WAV...';
    });

    try {
      final path = await WavExporter.export(text);
      setState(() {
        _isSaving = false;
        _savedPath = path;
        _status = 'Saved!';
      });
    } catch (e) {
      setState(() {
        _isSaving = false;
        _status = 'Failed to save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _controller.text.trim().isNotEmpty;
    final busy = _isSending || _isSaving;

    return Scaffold(
      backgroundColor: const Color(0xFF080C1A),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: const Color(0xFF1E2D4A)),
                  ),
                  child: const Icon(Icons.surround_sound,
                      color: Color(0xFF0088FF), size: 20),
                ),
                const SizedBox(width: 12),
                const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Transmit',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      Text('Send data via ultrasonic sound',
                          style: TextStyle(
                              color: Color(0xFF445577), fontSize: 11)),
                    ]),
              ]),

              const SizedBox(height: 24),

              // Info card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1020),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1A2840)),
                ),
                child: const Row(children: [
                  Icon(Icons.info_outline, color: Color(0xFF3355AA), size: 14),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(
                    'TRANSMIT plays tones through the speaker. SAVE WAV exports a file you can play on a laptop to test receiving.',
                    style: TextStyle(
                        color: Color(0xFF557799), fontSize: 11, height: 1.5),
                  )),
                ]),
              ),

              const SizedBox(height: 24),

              // Text input
              const Text('MESSAGE',
                  style: TextStyle(
                      color: Color(0xFF445577),
                      fontSize: 10,
                      letterSpacing: 1.5)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0E1828),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1A2840)),
                ),
                child: TextField(
                  controller: _controller,
                  enabled: !busy,
                  maxLength: 64,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'Type your message...',
                    hintStyle: TextStyle(color: Color(0xFF334466)),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                    counterStyle:
                        TextStyle(color: Color(0xFF334466), fontSize: 10),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),

              const SizedBox(height: 12),

              // Duration estimate
              if (hasText)
                Text(
                  'Duration: ${FskService.messageDuration(_controller.text.trim()).toStringAsFixed(1)}s  ·  ${_controller.text.trim().length} chars',
                  style:
                      const TextStyle(color: Color(0xFF334466), fontSize: 11),
                ),

              const SizedBox(height: 20),

              // Progress bar
              if (busy || _progress > 0) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _isSaving ? null : _progress,
                    backgroundColor: const Color(0xFF1A2840),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      _isSaving
                          ? const Color(0xFF00FF88)
                          : const Color(0xFF0088FF),
                    ),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Status
              Row(children: [
                Icon(
                  busy ? Icons.graphic_eq : Icons.check_circle_outline,
                  color:
                      busy ? const Color(0xFF0088FF) : const Color(0xFF334466),
                  size: 14,
                ),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_status,
                        style: TextStyle(
                          color: busy
                              ? const Color(0xFF0088FF)
                              : const Color(0xFF445577),
                          fontSize: 12,
                        ))),
              ]),

              // Saved path card
              if (_savedPath != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0A1A0A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF225522)),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [
                          Icon(Icons.check_circle,
                              color: Color(0xFF00FF88), size: 14),
                          SizedBox(width: 6),
                          Text('WAV file saved',
                              style: TextStyle(
                                color: Color(0xFF00FF88),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              )),
                        ]),
                        const SizedBox(height: 8),
                        Text(_savedPath!,
                            style: const TextStyle(
                              color: Color(0xFF557799),
                              fontSize: 10,
                              fontFamily: 'monospace',
                            )),
                        const SizedBox(height: 10),
                        const Text(
                          '→ Open the file on your laptop and play it at full volume\n'
                          '→ On the phone, go to RECEIVE tab and tap START LISTENING',
                          style: TextStyle(
                              color: Color(0xFF445566),
                              fontSize: 11,
                              height: 1.6),
                        ),
                      ]),
                ),
              ],

              const SizedBox(height: 28),

              // TRANSMIT button
              GestureDetector(
                onTap: busy ? null : _send,
                child: Container(
                  height: 52,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: LinearGradient(
                      colors: busy
                          ? [const Color(0xFF08132A), const Color(0xFF0A1830)]
                          : [const Color(0xFF001A3A), const Color(0xFF002255)],
                    ),
                    border: Border.all(
                      color:
                          const Color(0xFF0088FF).withOpacity(busy ? 0.2 : 0.4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0088FF)
                            .withOpacity(busy ? 0.05 : 0.15),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Center(
                    child: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFF0088FF)))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                                Icon(Icons.surround_sound,
                                    color: Color(0xFF0088FF), size: 18),
                                SizedBox(width: 10),
                                Text('TRANSMIT',
                                    style: TextStyle(
                                      color: Color(0xFF0088FF),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2,
                                    )),
                              ]),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // SAVE WAV button
              GestureDetector(
                onTap: (busy || !hasText) ? null : _saveWav,
                child: Container(
                  height: 52,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: const Color(0xFF0E1828),
                    border: Border.all(
                      color: (busy || !hasText)
                          ? const Color(0xFF1A2840)
                          : const Color(0xFF00FF88).withOpacity(0.35),
                    ),
                  ),
                  child: Center(
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Color(0xFF00FF88)))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                                Icon(Icons.download,
                                    color: (busy || !hasText)
                                        ? const Color(0xFF334466)
                                        : const Color(0xFF00FF88),
                                    size: 18),
                                const SizedBox(width: 10),
                                Text('SAVE AS WAV',
                                    style: TextStyle(
                                      color: (busy || !hasText)
                                          ? const Color(0xFF334466)
                                          : const Color(0xFF00FF88),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 2,
                                    )),
                              ]),
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
