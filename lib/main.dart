import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'features/connect/connect_screen.dart';
import 'features/measure/measure_screen.dart';
import 'features/ai/ai_screen.dart';
import 'features/listen/listen_screen.dart';
import 'features/more/more_screen.dart';
import 'core/dsp_safety_notice.dart';

void main() {
  runApp(const ProviderScope(child: TunaiProApp()));
}

class TunaiProApp extends StatelessWidget {
  const TunaiProApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TUNAI Pro',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: DspSafetyNotice.scaffoldMessengerKey,
      home: const TunaiProShell(),
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
    MeasureScreen(),
    AiScreen(),
    ListenScreen(),
    MoreScreen(),
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
            unselectedItemColor: Colors.white54,
            selectedLabelStyle:
                const TextStyle(fontSize: 11, letterSpacing: 1.5),
            unselectedLabelStyle:
                const TextStyle(fontSize: 11, letterSpacing: 1.5),
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(
                  icon: Icon(Icons.usb, size: 22), label: 'CONNECT'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.mic_none, size: 22), label: 'MEASURE'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.auto_awesome_outlined, size: 22),
                  label: 'AI'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.volume_up_outlined, size: 22),
                  label: 'LISTEN'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.more_horiz, size: 22), label: 'MORE'),
            ],
          ),
        ),
      ),
    );
  }
}
