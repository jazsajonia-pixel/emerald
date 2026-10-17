import 'package:flutter/material.dart';

void main() {
  runApp(const EmeraldApp());
}

/// Root widget for Emerald.
///
/// Phase 0 only establishes a buildable foundation. Navigation and features
/// arrive in later phases (see DEVELOPMENT_PHASES.md).
class EmeraldApp extends StatelessWidget {
  const EmeraldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emerald',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2EB67D),
          brightness: Brightness.dark,
        ),
      ),
      home: const Scaffold(
        body: Center(child: Text('Emerald', style: TextStyle(fontSize: 32))),
      ),
    );
  }
}
