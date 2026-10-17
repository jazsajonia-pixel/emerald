import 'package:flutter/material.dart';

import 'home_shell.dart';
import 'theme.dart';

class EmeraldApp extends StatelessWidget {
  const EmeraldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Emerald',
      debugShowCheckedModeBanner: false,
      theme: EmeraldTheme.dark(),
      darkTheme: EmeraldTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const HomeShell(),
    );
  }
}
