import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/search/index_controller.dart';
import 'home_shell.dart';
import 'theme.dart';

class EmeraldApp extends ConsumerWidget {
  const EmeraldApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the link/search index alive for the whole session so it builds in
    // the background as soon as a vault is open.
    ref.listen(indexControllerProvider, (_, _) {});
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
