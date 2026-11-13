import 'package:flutter/material.dart';
import 'app/theme.dart';
import 'features/setup/setup_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SpiralApp());
}

class SpiralApp extends StatelessWidget {
  const SpiralApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spiral Quest',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const GameSetupScreen(),
    );
  }
}
