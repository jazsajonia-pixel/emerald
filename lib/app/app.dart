import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/search/index_controller.dart';
import '../features/sync/sync_lifecycle.dart';
import 'home_shell.dart';
import 'theme.dart';

class SapphireApp extends ConsumerWidget {
  const SapphireApp({super.key, this.reduceMotion = false});

  /// Test harnesses can disable ambient motion so pumpAndSettle can complete.
  final bool reduceMotion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep the link/search index alive for the whole session so it builds in
    // the background as soon as a vault is open.
    ref.listen(indexControllerProvider, (_, _) {});
    return MaterialApp(
      title: 'Sapphire',
      debugShowCheckedModeBanner: false,
      theme: SapphireTheme.dark(),
      darkTheme: SapphireTheme.dark(),
      themeMode: ThemeMode.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations:
              reduceMotion || MediaQuery.of(context).disableAnimations,
        ),
        child: child!,
      ),
      home: const SyncLifecycle(child: HomeShell()),
    );
  }
}
