import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/dsp/dsp_screen.dart';
import 'features/community/community_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/auth/auth_controller.dart';
import 'features/connect/connect_screen.dart';
import 'features/mic/measurement_mic_screen.dart';

void main() {
  runApp(const ProviderScope(child: TunaiProApp()));
}

class TunaiProApp extends StatelessWidget {
  const TunaiProApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'TUNAI Pro',
      debugShowCheckedModeBanner: false,
      home: TunaiProShell(),
    );
  }
}

class TunaiProShell extends StatefulWidget {
  const TunaiProShell({super.key});
  @override
  State<TunaiProShell> createState() => _TunaiProShellState();
}

class _TunaiProShellState extends State<TunaiProShell> {
  int _index = 0;
  final _screens = const [
    ConnectScreen(),
    const DspScreen(),
    MeasurementMicScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          surface: Color(0xFF111111),
        ),
        useMaterial3: true,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: _screens[_index],
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Colors.white12, width: 0.5)),
          ),
          child: BottomNavigationBar(
            currentIndex: _index,
            onTap: (i) => setState(() => _index = i),
            backgroundColor: const Color(0xFF0A0A0A),
            selectedItemColor: Colors.white,
            unselectedItemColor: Colors.white30,
            selectedLabelStyle: const TextStyle(fontSize: 9, letterSpacing: 1.5),
            unselectedLabelStyle: const TextStyle(fontSize: 9, letterSpacing: 1.5),
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.usb, size: 18), label: 'CONNECT'),
              BottomNavigationBarItem(icon: Icon(Icons.equalizer, size: 18), label: 'PEQ'),
              BottomNavigationBarItem(icon: Icon(Icons.mic_none, size: 18), label: 'MIC'),
              BottomNavigationBarItem(icon: Icon(Icons.people_outline, size: 18), label: 'COMMUNITY'),
              BottomNavigationBarItem(icon: Icon(Icons.person_outline, size: 18), label: 'PROFILE'),
            ],
          ),
        ),
      ),
    );
  }
}
