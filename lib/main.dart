import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Run full-screen with no system overlays for an immersive watch experience.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: []);
  runApp(const CrownBreakerApp());
}

class CrownBreakerApp extends StatelessWidget {
  const CrownBreakerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Crown Breaker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF03030F),
        colorScheme: const ColorScheme.dark(
          primary: Colors.cyanAccent,
          secondary: Colors.pinkAccent,
          surface: Color(0xFF0A0A1F),
        ),
      ),
      home: const GameScreen(),
    );
  }
}
