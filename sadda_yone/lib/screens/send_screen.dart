import 'dart:async';
import 'package:flutter/material.dart';
import '../services/tone_player.dart';
import '../services/fsk_service.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final TonePlayer _player = TonePlayer();
  final TextEditingController _controller = TextEditingController();

  bool _isSending = false;
  double _progress = 0;
  String _status = 'Type a message and tap SEND';
  Timer? _progressTimer;

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
      _status = 'Transmitting "${text.length > 20 ? text.substring(0, 20) + "..." : text}"';
    });

    // Animate progress bar
    final startTime = DateTime.now();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 50), (t) {
      final elapsed = DateTime.now().difference(startTime).inMilliseconds / 1000.0;
      setState(() => _progress = (elapsed / duration).clamp(0.0, 1.0));
      if (elapsed >= duration) t.cancel();
    });

    await _player.transmit(text);

    _progressTimer?.cancel();
    setState(() {
      _isSending = false;
      _progress = 1.0;
      _status = 'Sent! "${text.length > 20 ? text.substring(0, 20) + "..." : text}"';
    });

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() { _progress = 0; _status = 'Type a message and tap SEND'; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C1A),
      body: SafeArea(
        child: Padding(
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
                  child: const Icon(Icons.surround_sound, color: Color(0xFF0088FF), size: 20),
                ),
                const SizedBox(width: 12),
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Transmit', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('Send data via ultrasonic sound', style: TextStyle(color: Color(0xFF445577), fontSize: 11)),
                ]),
              ]),

              const SizedBox(height: 28),

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
                  Expanded(child: Text(
                    'Messages are encoded as ultrasonic tones (~18–22 kHz). Hold phones 0.5–2m apart.',
                    style: TextStyle(color: Color(0xFF557799), fontSize: 11, height: 1.5),
                  )),
                ]),
              ),

              const SizedBox(height: 24),

              // Text input
              const Text('MESSAGE', style: TextStyle(color: Color(0xFF445577), fontSize: 10, letterSpacing: 1.5)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0E1828),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF1A2840)),
                ),
                child: TextField(
                  controller: _controller,
                  enabled: !_isSending,
                  maxLength: 64,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  decoration: const InputDecoration(
                    hintText: 'Type your message...',
                    hintStyle: TextStyle(color: Color(0xFF334466)),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                    counterStyle: TextStyle(color: Color(0xFF334466), fontSize: 10),
                  ),
                  onSubmitted: (_) => _send(),
                ),
              ),

              const SizedBox(height: 20),

              // Duration estimate
              if (_controller.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    'Estimated transmission: ${FskService.messageDuration(_controller.text).toStringAsFixed(1)}s',
                    style: const TextStyle(color: Color(0xFF334466), fontSize: 11),
                  ),
                ),

              // Progress bar
              if (_isSending || _progress > 0) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _progress,
                    backgroundColor: const Color(0xFF1A2840),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF0088FF)),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Status
              Row(children: [
                Icon(
                  _isSending ? Icons.graphic_eq : Icons.check_circle_outline,
                  color: _isSending ? const Color(0xFF0088FF) : const Color(0xFF334466),
                  size: 14,
                ),
                const SizedBox(width: 8),
                Text(_status, style: TextStyle(
                  color: _isSending ? const Color(0xFF0088FF) : const Color(0xFF445577),
                  fontSize: 12,
                )),
              ]),

              const Spacer(),

              // Send button
              GestureDetector(
                onTap: _isSending ? null : _send,
                child: AnimatedBuilder(
                  animation: const AlwaysStoppedAnimation(0),
                  builder: (_, __) => Container(
                    height: 52,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        colors: _isSending
                            ? [const Color(0xFF08132A), const Color(0xFF0A1830)]
                            : [const Color(0xFF001A3A), const Color(0xFF002255)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: const Color(0xFF0088FF).withOpacity(_isSending ? 0.2 : 0.4),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0088FF).withOpacity(_isSending ? 0.05 : 0.15),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: Center(
                      child: _isSending
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF0088FF),
                              ),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.send, color: Color(0xFF0088FF), size: 18),
                                SizedBox(width: 10),
                                Text('TRANSMIT', style: TextStyle(
                                  color: Color(0xFF0088FF),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                )),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
