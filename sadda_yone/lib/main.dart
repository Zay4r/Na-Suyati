import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../screens/send_screen.dart';
import '../screens/receive_screen.dart';
import 'screens/detector_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const UltrasonicApp());
}

class UltrasonicApp extends StatelessWidget {
  const UltrasonicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ultrasonic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF080C1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00FF88),
          secondary: Color(0xFF0088FF),
          surface: Color(0xFF111827),
        ),
      ),
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _tab = 1; // default to Receive

  final _screens = const [
    SendScreen(),
    ReceiveScreen(),
    DetectorScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C1A),
      body: IndexedStack(index: _tab, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF1A2035))),
          color: Color(0xFF080C1A),
        ),
        child: BottomNavigationBar(
          currentIndex: _tab,
          onTap: (i) => setState(() => _tab = i),
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: const Color(0xFF00FF88),
          unselectedItemColor: const Color(0xFF334466),
          selectedFontSize: 10,
          unselectedFontSize: 10,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.surround_sound, size: 22),
              label: 'SEND',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.hearing, size: 22),
              label: 'RECEIVE',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.radar, size: 22),
              label: 'DETECT',
            ),
          ],
        ),
      ),
    );
  }
}
