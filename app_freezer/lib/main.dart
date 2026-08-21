import 'package:flutter/material.dart';
import 'services/timer_service.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await TimerService.initialize();
  runApp(const AppFreezerApp());
}

class AppFreezerApp extends StatelessWidget {
  const AppFreezerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'App Freezer',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent, brightness: Brightness.dark),
      ),
      home: const HomeScreen(),
    );
  }
}
