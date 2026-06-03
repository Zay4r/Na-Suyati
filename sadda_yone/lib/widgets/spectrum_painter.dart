import 'dart:math';
import 'package:flutter/material.dart';
import '../services/fft_service.dart';

class SpectrumPainter extends CustomPainter {
  final FFTResult? fftResult;
  final double maxFreq;
  final List<double> smoothedMags;

  const SpectrumPainter({
    this.fftResult,
    this.maxFreq = 22000,
    required this.smoothedMags,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawZones(canvas, size);
    _drawGrid(canvas, size);
    if (fftResult != null && smoothedMags.isNotEmpty) {
      _drawSpectrum(canvas, size);
    }
    _drawFreqLabels(canvas, size);
    _drawZoneLabels(canvas, size);
  }

  void _drawBackground(Canvas canvas, Size size) {
    final paint = Paint()..color = const Color(0xFF0A1020);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(0),
      ),
      paint,
    );
  }

  void _drawZones(Canvas canvas, Size size) {
    final yellowStart = size.width * 15000 / maxFreq;
    final ultraStart = size.width * 17000 / maxFreq;

    canvas.drawRect(
      Rect.fromLTWH(yellowStart, 0, ultraStart - yellowStart, size.height),
      Paint()..color = const Color(0x0FFFCC00),
    );

    canvas.drawRect(
      Rect.fromLTWH(ultraStart, 0, size.width - ultraStart, size.height),
      Paint()..color = const Color(0x14FF3333),
    );
  }

  void _drawGrid(Canvas canvas, Size size) {
    final hPaint = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 0.5;

    for (int i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), hPaint);
    }

    final freqMarkers = [2000, 5000, 10000, 15000, 17000, 19000, 21000];
    for (final freq in freqMarkers) {
      final x = size.width * freq / maxFreq;
      final paint = Paint()
        ..color = freq >= 17000
            ? const Color(0x33FF5555)
            : const Color(0x22FFFFFF)
        ..strokeWidth = freq == 17000 ? 1.0 : 0.5
        ..style = PaintingStyle.stroke;

      if (freq == 17000) {
        _drawDashedLine(canvas, Offset(x, 0), Offset(x, size.height), paint);
      } else {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
      }
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashHeight = 4.0;
    const gapHeight = 4.0;
    double currentY = start.dy;
    while (currentY < end.dy) {
      canvas.drawLine(
        Offset(start.dx, currentY),
        Offset(start.dx, min(currentY + dashHeight, end.dy)),
        paint,
      );
      currentY += dashHeight + gapHeight;
    }
  }

  void _drawSpectrum(Canvas canvas, Size size) {
    final maxBin = fftResult!.freqToBin(maxFreq);
    if (maxBin <= 0 || smoothedMags.isEmpty) return;

    final displayBins = min(maxBin, smoothedMags.length);

    final sorted = List<double>.from(smoothedMags.take(displayBins))..sort();
    final p95index = (sorted.length * 0.95).toInt().clamp(0, sorted.length - 1);
    final refMax = max(sorted[p95index], 0.01);

    final fillPath = Path();
    fillPath.moveTo(0, size.height);

    for (int bin = 0; bin < displayBins; bin++) {
      final x = size.width * bin / displayBins;
      final mag = smoothedMags[bin];
      final normalized = (mag / refMax).clamp(0.0, 1.5);
      final logMag = normalized > 0
          ? (log(normalized * 9 + 1) / log(10)).clamp(0.0, 1.0)
          : 0.0;
      final y = size.height * (1.0 - logMag * 0.95);
      fillPath.lineTo(x, y);
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final peakFreq = fftResult!.getPeakFrequencyInRange(1000, maxFreq);
    final Color topColor;
    final Color bottomColor;

    if (peakFreq >= 17000) {
      topColor = const Color(0xAAFF4444);
      bottomColor = const Color(0x22FF2222);
    } else if (peakFreq >= 15000) {
      topColor = const Color(0xAAFFAA00);
      bottomColor = const Color(0x22FF8800);
    } else {
      topColor = const Color(0xAA00FF88);
      bottomColor = const Color(0x2200CC66);
    }

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor, bottomColor],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final linePath = Path();
    linePath.moveTo(0, size.height);
    for (int bin = 0; bin < displayBins; bin++) {
      final x = size.width * bin / displayBins;
      final mag = smoothedMags[bin];
      final normalized = (mag / refMax).clamp(0.0, 1.5);
      final logMag = normalized > 0
          ? (log(normalized * 9 + 1) / log(10)).clamp(0.0, 1.0)
          : 0.0;
      final y = size.height * (1.0 - logMag * 0.95);
      linePath.lineTo(x, y);
    }

    canvas.drawPath(
      linePath,
      Paint()
        ..color = topColor.withOpacity(0.9)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawFreqLabels(Canvas canvas, Size size) {
    final labels = {
      2000: '2k',
      5000: '5k',
      10000: '10k',
      15000: '15k',
      17000: '17k',
      19000: '19k',
      21000: '21k',
    };

    for (final entry in labels.entries) {
      final x = size.width * entry.key / maxFreq;
      final isUltrasonic = entry.key >= 17000;

      final tp = TextPainter(
        text: TextSpan(
          text: entry.value,
          style: TextStyle(
            color: isUltrasonic
                ? const Color(0x99FF6666)
                : const Color(0x66FFFFFF),
            fontSize: 8.5,
            letterSpacing: 0.3,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(x - tp.width / 2, size.height - 13));
    }
  }

  void _drawZoneLabels(Canvas canvas, Size size) {
    final ultraX = size.width * 17000 / maxFreq;
    final labelWidth = size.width - ultraX;
    if (labelWidth > 40) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'ULTRASONIC',
          style: TextStyle(
            color: Color(0x44FF4444),
            fontSize: 7,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(
        canvas,
        Offset(ultraX + (labelWidth - tp.width) / 2, 6),
      );
    }
  }

  @override
  bool shouldRepaint(SpectrumPainter oldDelegate) =>
      oldDelegate.fftResult != fftResult ||
      oldDelegate.smoothedMags != smoothedMags;
}
