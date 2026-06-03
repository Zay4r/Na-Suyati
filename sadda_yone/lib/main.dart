import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../screens/detector_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const UltrasonicDetectorApp());
}

class UltrasonicDetectorApp extends StatelessWidget {
  const UltrasonicDetectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ultrasonic Detector',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF080C1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF88),
          secondary: Color(0xFF0088FF),
          surface: Color(0xFF111827),
        ),
      ),
      home: const DetectorScreen(),
    );
  }
}
