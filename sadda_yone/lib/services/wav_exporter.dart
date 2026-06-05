import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'fsk_service.dart';

class WavExporter {
  static Future<String> export(String text) async {
    final pcm = FskService.encodeMessage(text);
    final wav = _buildWav(pcm, FskService.SAMPLE_RATE);
    final filename = 'ultrasonic_${DateTime.now().millisecondsSinceEpoch}.wav';

    if (Platform.isAndroid) {
      // Android < 10: request WRITE_EXTERNAL_STORAGE and write to Downloads
      final sdkInt = await _androidSdkInt();
      if (sdkInt < 29) {
        final status = await Permission.storage.request();
        if (status.isGranted) {
          try {
            final file = File('/storage/emulated/0/Downloads/$filename');
            await file.writeAsBytes(wav);
            return file.path;
          } catch (_) {}
        }
      }

      // Android 10+: app-specific external dir — no permission needed
      try {
        final dir = await getExternalStorageDirectory();
        if (dir != null) {
          await dir.create(recursive: true);
          final file = File('${dir.path}/$filename');
          await file.writeAsBytes(wav);
          return file.path;
        }
      } catch (_) {}
    }

    // Final fallback: internal app documents dir (always accessible)
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(wav);
    return file.path;
  }

  /// Returns the Android SDK integer (e.g. 33 for Android 13)
  static Future<int> _androidSdkInt() async {
    try {
      final result = await Process.run('getprop', ['ro.build.version.sdk']);
      return int.tryParse(result.stdout.toString().trim()) ?? 30;
    } catch (_) {
      return 30; // assume modern if unknown
    }
  }

  static Uint8List _buildWav(Uint8List pcm, int sampleRate) {
    const numChannels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final blockAlign = numChannels * bitsPerSample ~/ 8;
    final dataSize = pcm.length;
    final chunkSize = 36 + dataSize;

    final header = ByteData(44);
    _writeAscii(header, 0, 'RIFF');
    header.setUint32(4, chunkSize, Endian.little);
    _writeAscii(header, 8, 'WAVE');
    _writeAscii(header, 12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    _writeAscii(header, 36, 'data');
    header.setUint32(40, dataSize, Endian.little);

    final result = Uint8List(44 + dataSize);
    result.setAll(0, header.buffer.asUint8List());
    result.setAll(44, pcm);
    return result;
  }

  static void _writeAscii(ByteData bd, int offset, String s) {
    for (int i = 0; i < s.length; i++) {
      bd.setUint8(offset + i, s.codeUnitAt(i));
    }
  }
}
